// 구조 참고: gksdud main.swift(#60 백업·소유권·복원) (MIT)
import Foundation

/// Caps 대신 내보낼 F 키. 키코드는 가상 키코드, usage는 HID 사용값(키보드 페이지 0x07).
public struct CapsKey: Equatable, Sendable {
    public let keyCode: Int
    public let usage: UInt64

    public init(keyCode: Int, usage: UInt64) {
        self.keyCode = keyCode
        self.usage = usage
    }

    public static let capsLockUsage: UInt64 = 0x700000039
    public static let f18 = CapsKey(keyCode: 79, usage: 0x70000006D)
    /// 우선순위 순서. F14, F15, F20은 단축키가 동작하지 않아 뺀다(gksdud).
    public static let candidates: [CapsKey] = [
        f18,
        CapsKey(keyCode: 80, usage: 0x70000006E),
        CapsKey(keyCode: 64, usage: 0x70000006C),
        CapsKey(keyCode: 106, usage: 0x70000006B),
        CapsKey(keyCode: 105, usage: 0x700000068),
    ]

    /// 비어 있는 키를 고른다. 60번 항목은 사용 중으로 세지 않는다.
    /// - hotkeys: `AppleSymbolicHotKeys` 전체
    /// - mappedTargets: 다른 매핑이 내는 사용값(우리 Caps 기록의 target은 호출 쪽에서 뺀다)
    /// - preferred: 저장된 우리 키코드. 비어 있으면 유지한다.
    public static func pick(hotkeys: [String: Any], mappedTargets: Set<UInt64>, preferred: Int?) -> CapsKey? {
        var used = Set<Int>()
        for (id, value) in hotkeys where id != "60" {
            guard let entry = value as? [String: Any], isEnabled(entry),
                let params = (entry["value"] as? [String: Any])?["parameters"] as? [Any], params.count >= 2,
                let kc = (params[1] as? NSNumber)?.intValue
            else { continue }
            used.insert(kc)
        }
        func free(_ k: CapsKey) -> Bool { !used.contains(k.keyCode) && !mappedTargets.contains(k.usage) }
        if let preferred, let k = candidates.first(where: { $0.keyCode == preferred }), free(k) { return k }
        return candidates.first(where: free)
    }

    private static func isEnabled(_ entry: [String: Any]) -> Bool {
        (entry["enabled"] as? NSNumber)?.boolValue ?? false
    }
}

/// #60(이전 입력 소스 선택) 소유권 판단. 시스템에 닿지 않는다.
public enum ShortcutOwnership {
    /// 우리가 쓰는 값인가: 켜짐, `[65535, 우리 키코드, 0 또는 SecondaryFn(0x800000)]`.
    public static func isOurs(entry: [String: Any]?, keyCode: Int) -> Bool {
        isOurs(entry: entry, keyCodes: [keyCode])
    }

    public static func isOurs(entry: [String: Any]?, keyCodes: [Int]) -> Bool {
        guard let entry, (entry["enabled"] as? NSNumber)?.boolValue == true,
            let params = (entry["value"] as? [String: Any])?["parameters"] as? [Any], params.count == 3,
            let a = (params[0] as? NSNumber)?.intValue, a == 65535,
            let k = (params[1] as? NSNumber)?.intValue, keyCodes.contains(k),
            let m = (params[2] as? NSNumber)?.uint64Value, m == 0 || m == 0x800000
        else { return false }
        return true
    }

    /// 복원에 쓸 수 있는 모양인가: `enabled`와 `value.parameters` 3개.
    public static func isWellFormed(_ entry: [String: Any]) -> Bool {
        guard entry["enabled"] is NSNumber,
            let params = (entry["value"] as? [String: Any])?["parameters"] as? [Any], params.count == 3
        else { return false }
        return true
    }

    public static func entry(keyCode: Int) -> [String: Any] {
        ["enabled": true, "value": ["type": "standard", "parameters": [65535, keyCode, 0]] as [String: Any]]
    }
}

/// 시스템 접근 묶음. 기본값 없는 클로저만 둬서 시험에서 실제 시스템이 돌 수 없게 한다.
public struct ShortcutPreferences {
    /// `AppleSymbolicHotKeys` 전체. 읽지 못하면 nil.
    public var read: () -> [String: Any]?
    public var write: ([String: Any]) -> Bool
    /// activateSettings 실행 파일이 있는가. 없으면 쓰기를 시작하지 않는다.
    public var canActivate: () -> Bool
    public var activate: (@escaping (Bool) -> Void) -> Void

    public init(
        read: @escaping () -> [String: Any]?,
        write: @escaping ([String: Any]) -> Bool,
        canActivate: @escaping () -> Bool,
        activate: @escaping (@escaping (Bool) -> Void) -> Void
    ) {
        self.read = read
        self.write = write
        self.canActivate = canActivate
        self.activate = activate
    }

    /// `AppleSymbolicHotKeys` 원시 값을 해석한다. 03-08 WR-10: `CFPreferencesCopyAppValue`가 nil이면
    /// 키가 없는 계정이다. 그때만 빈 사전으로 시작한다. 값이 사전이 아니면 읽기 실패로 보고 쓰지 않는다.
    public static func interpret(raw: Any?) -> [String: Any]? {
        guard let raw else { return [:] }
        return raw as? [String: Any]
    }
}

/// #60 백업·적용·복원. 불변식: 지금 값이 우리 값인 동안 `originalShortcut`은 지워지지 않는다.
public final class ShortcutManager {
    static let backedUpKey = "shortcutBackedUp"
    static let originalKey = "originalShortcut"
    static let managedKey = "managedShortcutKeyCode"
    static let pendingKeyCodeKey = "shortcutPendingKeyCode"
    static let restorePendingKey = "shortcutRestorePending"
    public static let retryInterval: TimeInterval = 30

    private let defaults: UserDefaults
    private let prefs: ShortcutPreferences
    private let now: () -> TimeInterval
    private var nextApplyAt: TimeInterval?
    private var nextRestoreAt: TimeInterval?
    /// 이 프로세스에서 activate까지 마친 키코드.
    private var activatedKeyCode: Int?

    public init(defaults: UserDefaults, prefs: ShortcutPreferences, now: @escaping () -> TimeInterval) {
        self.defaults = defaults
        self.prefs = prefs
        self.now = now
    }

    /// 백업이나 우리 값이 남아 있는가(복원할 것이 있는가). 시스템을 읽지 않는다.
    public var hasStoredState: Bool {
        defaults.bool(forKey: Self.backedUpKey) || defaults.bool(forKey: Self.restorePendingKey)
            || defaults.object(forKey: Self.managedKey) != nil
            || defaults.object(forKey: Self.pendingKeyCodeKey) != nil
    }

    public var managedKeyCode: Int? { defaults.object(forKey: Self.managedKey) as? Int }

    // MARK: 시스템 값 표현

    private func encode(_ entry: [String: Any]) -> Data? {
        try? PropertyListSerialization.data(fromPropertyList: entry, format: .binary, options: 0)
    }

    private func decode(_ data: Data) -> [String: Any]? { Self.decodeEntry(data) }

    static func decodeEntry(_ data: Data) -> [String: Any]? {
        (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)) as? [String: Any]
    }

    /// W5: 백업해 둔 #60 원래 조합을 읽기만 한다. 손상 값·꺼진 값은 nil(T-04-76).
    /// 04-21이 겹침 집합의 extraChords로 쓴다.
    public static func originalChord(defaults: UserDefaults) -> KeyChord? {
        guard let data = defaults.data(forKey: originalKey),
            let entry = Self.decodeEntry(data),
            ShortcutOwnership.isWellFormed(entry),
            (entry["enabled"] as? NSNumber)?.boolValue == true,
            let params = (entry["value"] as? [String: Any])?["parameters"] as? [Any], params.count == 3,
            let keyCode = (params[1] as? NSNumber)?.uint16Value,
            let modifiers = (params[2] as? NSNumber)?.uint64Value
        else { return nil }
        return KeyChord(keyCode: keyCode, modifiers: modifiers)
    }

    private func same(_ a: [String: Any]?, _ b: [String: Any]?) -> Bool {
        switch (a, b) {
        case (nil, nil): return true
        case (let x?, let y?): return NSDictionary(dictionary: x).isEqual(to: y)
        default: return false
        }
    }

    private var ourKeyCodes: [Int] {
        [defaults.object(forKey: Self.managedKey) as? Int, defaults.object(forKey: Self.pendingKeyCodeKey) as? Int]
            .compactMap { $0 }
    }

    private func clearStored() {
        for k in [Self.backedUpKey, Self.originalKey, Self.managedKey, Self.pendingKeyCodeKey, Self.restorePendingKey] {
            defaults.removeObject(forKey: k)
        }
        defaults.synchronize()
    }

    /// 60번 항목만 바꾼 전체 사전을 쓴다. 다른 단축키는 그대로 둔다.
    private func writeEntry(_ entry: [String: Any]?, base: [String: Any]) -> Bool {
        var all = base
        all["60"] = entry
        if entry == nil { all.removeValue(forKey: "60") }
        guard prefs.write(all) else { return false }
        let back = prefs.read()
        return same(back?["60"] as? [String: Any], entry)
    }

    // MARK: 적용

    /// 순서: 백업 저장 → 다시 읽어 확인 → 60번만 쓰기 → 다시 읽어 확인 → activate.
    /// completion은 정확히 한 번 불린다. 실패하면 쓰기 직전 값으로 되돌리고, 다음 적용은 30초 뒤에야 시도한다.
    public func apply(keyCode: Int, completion: @escaping (Bool) -> Void) {
        if let next = nextApplyAt, now() < next {
            completion(false)
            return
        }
        guard prefs.canActivate() else {
            completion(false)
            return
        }
        guard let all = prefs.read() else {
            failApply()
            completion(false)
            return
        }
        let entry = all["60"] as? [String: Any]
        // 저장 상태가 없으면 지금 값이 앱 값이라고 볼 근거가 없다(CR-01): 같은 모양이어도 원래 값으로 백업한다.
        let ourKeys = hasStoredState ? ourKeyCodes + [keyCode] : ourKeyCodes
        let ours = ShortcutOwnership.isOurs(entry: entry, keyCodes: ourKeys)
        let sameKey = ShortcutOwnership.isOurs(entry: entry, keyCode: keyCode)

        if ours && sameKey && defaults.bool(forKey: Self.backedUpKey) && activatedKeyCode == keyCode
            && !defaults.bool(forKey: Self.restorePendingKey)
        {
            completion(true)
            return
        }

        // 백업: 우리 값이 아닐 때만. 저장 상태가 있는 동안의 우리 값은 원래 값으로 저장하지 않는다.
        if !ours {
            let data = entry.flatMap(encode)
            if entry != nil && data == nil {
                failApply()
                completion(false)
                return
            }
            defaults.set(true, forKey: Self.backedUpKey)
            if let data { defaults.set(data, forKey: Self.originalKey) } else { defaults.removeObject(forKey: Self.originalKey) }
            defaults.synchronize()
            guard defaults.bool(forKey: Self.backedUpKey), defaults.data(forKey: Self.originalKey) == data else {
                // 저장을 확인하지 못했다: 쓰지 않는다.
                defaults.removeObject(forKey: Self.backedUpKey)
                defaults.removeObject(forKey: Self.originalKey)
                failApply()
                completion(false)
                return
            }
        }
        // 이 시점부터 pending 복원 표시는 의미가 없다(백업은 유지, 표시만 지운다).
        defaults.removeObject(forKey: Self.restorePendingKey)
        defaults.set(keyCode, forKey: Self.pendingKeyCodeKey)
        defaults.synchronize()

        // 이미 같은 값이면 다시 쓰지 않는다(백업과 managed 기록은 위아래에서 남긴다).
        if !sameKey {
            if !writeEntry(ShortcutOwnership.entry(keyCode: keyCode), base: all) {
                // 쓰기 직전 값으로 되돌린다.
                // 되돌리기가 확인됐을 때만 키코드 표시를 지운다(WR-03). 실패하면 표시를 남겨 복원이 우리 값으로 판정하게 한다.
                if writeEntry(entry, base: prefs.read() ?? all) { rollbackKeys() }
                failApply()
                completion(false)
                return
            }
        }
        prefs.activate { [weak self] ok in
            guard let self else { return }
            if ok {
                self.defaults.set(keyCode, forKey: Self.managedKey)
                self.defaults.removeObject(forKey: Self.pendingKeyCodeKey)
                self.defaults.synchronize()
                self.activatedKeyCode = keyCode
                self.nextApplyAt = nil
                completion(true)
            } else {
                if self.writeEntry(entry, base: self.prefs.read() ?? all) { self.rollbackKeys() }
                self.failApply()
                completion(false)
            }
        }
    }

    private func failApply() {
        nextApplyAt = now() + Self.retryInterval
        activatedKeyCode = nil
    }

    /// 쓰기를 되돌렸으니 이번 시도에서 만든 키코드 표시를 지운다. 직전 managed는 그대로 둔다.
    private func rollbackKeys() {
        defaults.removeObject(forKey: Self.pendingKeyCodeKey)
        defaults.synchronize()
    }

    // MARK: 복원

    /// 할 일이 없으면 아무것도 저장하지 않는다. 우리 값이면 백업을 쓰고 → activate → 그 뒤에 키를 지운다.
    /// 실패하면 키를 남겨 다음 호출이 이어받는다. `force`는 30초 간격을 무시한다(되돌리기, 종료).
    public func restore(force: Bool, completion: @escaping (Bool) -> Void) {
        if !force, let next = nextRestoreAt, now() < next {
            completion(false)
            return
        }
        let backedUp = defaults.bool(forKey: Self.backedUpKey)
        let pending = defaults.bool(forKey: Self.restorePendingKey)
        let hasKeys = hasStoredState
        let all = prefs.read()
        let entry = all?["60"] as? [String: Any]
        let ours = ShortcutOwnership.isOurs(entry: entry, keyCodes: ourKeyCodes)
        if !backedUp && !pending && !ours {
            if hasKeys { clearStored() }
            completion(true)
            return
        }
        guard let all else {
            failRestore()
            completion(false)
            return
        }
        defaults.set(true, forKey: Self.restorePendingKey)
        defaults.synchronize()

        if ours {
            let expected = restoreTarget(backedUp: backedUp)
            guard writeEntry(expected, base: all) else {
                failRestore()
                completion(false)
                return
            }
        } else if !pending {
            // 사용자가 바꿨거나 이미 되돌아가 있다: 쓰지 않고 기록만 지운다.
            clearStored()
            completion(true)
            return
        }
        // 쓰기를 마쳤거나(이어받기 포함) 되돌린 값을 시스템에 반영한다.
        guard prefs.canActivate() else {
            clearStored()
            completion(true)
            return
        }
        prefs.activate { [weak self] ok in
            guard let self else { return }
            if ok {
                self.clearStored()
                self.nextRestoreAt = nil
                self.activatedKeyCode = nil
                completion(true)
            } else {
                self.failRestore()
                completion(false)
            }
        }
    }

    /// 복원할 값. nil이면 60번 항목을 지워 OS 기본으로 돌아간다.
    private func restoreTarget(backedUp: Bool) -> [String: Any]? {
        guard backedUp, let data = defaults.data(forKey: Self.originalKey) else { return nil }
        guard let entry = decode(data), ShortcutOwnership.isWellFormed(entry) else { return nil }
        return entry
    }

    private func failRestore() {
        nextRestoreAt = now() + Self.retryInterval
    }
}
