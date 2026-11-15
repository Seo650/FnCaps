import Foundation

/// D-46 「지정 단축키」: 지정 소스 하나에 붙는 키 조합. 키코드와 수정 키 비트만 저장한다.
/// 수정 키는 `HotkeyChord.modifierBits`(⌃⌥⇧⌘) 안만 남긴다(T-04-61). 손상 값도 init과
/// 디코더 양쪽에서 같은 정규화를 거친다.
public struct KeyChord: Hashable, Codable, Sendable {
    public let keyCode: UInt16
    public let modifiers: UInt64

    public init(keyCode: UInt16, modifiers: UInt64) {
        self.keyCode = keyCode
        self.modifiers = modifiers & HotkeyChord.modifierBits
    }

    private enum CodingKeys: String, CodingKey {
        case keyCode, modifiers
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            keyCode: try c.decode(UInt16.self, forKey: .keyCode),
            modifiers: try c.decodeIfPresent(UInt64.self, forKey: .modifiers) ?? 0)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(keyCode, forKey: .keyCode)
        try c.encode(modifiers, forKey: .modifiers)
    }
}

/// 녹화 결과 판정. 시스템에 닿지 않는다. 같은 조합의 다른 소유자는 거절하지 않고 알린다(W4).
public enum ChordValidation {
    public enum Refusal: Equatable, Sendable {
        case noModifier, notAKey
    }

    public enum Result: Equatable, Sendable {
        case accepted(KeyChord, takenFrom: SourceID?)
        case refused(Refusal)
    }

    /// 수정 키 자체의 가상 키코드(⌘ 54/55, ⇧ 56/60, ⇪ 57, ⌥ 58/61, ⌃ 59/62, fn 63)와 🌐 179.
    static let modifierKeyCodes: Set<UInt16> = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63, 179]

    /// 조합 하나를 판정한다. 수정 키는 `HotkeyChord.modifierBits`(⌃⌥⇧⌘)만 센다(연구 §1-3).
    /// 수정 키 하나만 있어도 받는다(D-46). 연구 §3-3의 「둘 이상」 권고는 채택하지 않았다.
    /// `reservedKeyCode`는 Caps 대신 내보내는 F 키(보통 F18 79)다.
    /// Esc·Delete·Tab의 「수정 키 없음」 처리는 녹화기(04-22)가 이 함수 앞에서 가로챈다.
    public static func validate(
        keyCode: UInt16, flags: UInt64, for id: SourceID,
        existing: [SourceID: KeyChord], reservedKeyCode: UInt16?
    ) -> Result {
        // 04-REVIEW IN-03: Caps 키는 나중에 다른 후보로 바뀔 수 있으므로 후보 전부를 거절한다.
        if modifierKeyCodes.contains(keyCode) || keyCode == reservedKeyCode
            || CapsKey.candidates.contains(where: { $0.keyCode == Int(keyCode) }) {
            return .refused(.notAKey)
        }
        let chord = KeyChord(keyCode: keyCode, modifiers: flags)
        guard chord.modifiers != 0 else { return .refused(.noModifier) }
        let owner = existing.first { $0.key != id && $0.value == chord }?.key
        return .accepted(chord, takenFrom: owner)
    }

    /// ⇧ 하나뿐인 조합은 대문자 입력을 가로챈다(연구 §3-3). ⌥ 단독·⌥⇧는 특수 문자·죽은 키를
    /// 가로챈다(IN-04, 권장안 채택 — user away, review at UAT). 저장·맞춤에는 영향이 없고
    /// 화면 알림(04-22)만 쓴다. 사용자가 허용했으므로 거절하지 않는다(T-04-65, D-46).
    /// 방향키·기능 키처럼 글자를 내지 않는 키는 알리지 않는다(05 2차 검토 IN-05, 05-11 UAT 사용자 결정).
    public static func blocksTyping(_ chord: KeyChord) -> Bool {
        [0x20000, 0x80000, 0xA0000].contains(chord.modifiers) && !nonCharacterKeyCodes.contains(chord.keyCode)
    }

    /// 글자를 내지 않는 키의 가상 키 코드(ANSI): Return, Tab, Delete, Escape, 키패드 Clear·Enter,
    /// F1~F20, Help, Home, End, Page Up·Down, Forward Delete, 방향키.
    static let nonCharacterKeyCodes: Set<UInt16> = [
        36, 48, 51, 53, 71, 76,
        122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111, 105, 107, 113, 106, 64, 79, 80, 90,
        114, 115, 116, 117, 119, 121,
        123, 124, 125, 126,
    ]
}

/// 앱이 꺼졌거나 「FnCaps 끄기」 앱이 맨 앞이면 지정 단축키도 꺼진다(D-46 사용자 확정).
/// 04-21 AppModel이 탭 맞춤 표를 비울지 이것으로 정한다.
public enum AssignedShortcutPolicy {
    public static func isActive(enabled: Bool, appOff: Bool) -> Bool { enabled && !appOff }
}

/// 시스템 기호 단축키 집합(`CopySymbolicHotKeys` 결과를 04-21이 넣는다). 시스템 호출 없음.
/// Carbon 수정 키(⌘ 0x100, ⇧ 0x200, ⌥ 0x800, ⌃ 0x1000)만 CGEventFlags 비트로 바꾸고
/// ⇪(0x400)·fn(0x20000)은 버린다(연구 §3-1).
public struct SystemChordSet: Sendable {
    private var chords: Set<KeyChord> = []

    /// - Parameters:
    ///   - carbonEntries: (keyCode, carbonModifiers, enabled). 꺼진 항목은 넣지 않는다.
    ///   - extraChords: 시스템 목록에 없는 입력 소스 조합(원래 #60, ⌃⌥Space, 연구 §3-3).
    public init(
        carbonEntries: [(keyCode: Int, carbonModifiers: Int, enabled: Bool)],
        extraChords: [KeyChord] = []
    ) {
        for entry in carbonEntries where entry.enabled {
            guard entry.keyCode >= 0, entry.keyCode <= Int(UInt16.max) else { continue }
            var bits: UInt64 = 0
            if entry.carbonModifiers & 0x100 != 0 { bits |= 0x100000 }  // ⌘
            if entry.carbonModifiers & 0x200 != 0 { bits |= 0x20000 }   // ⇧
            if entry.carbonModifiers & 0x800 != 0 { bits |= 0x80000 }   // ⌥
            if entry.carbonModifiers & 0x1000 != 0 { bits |= 0x40000 }  // ⌃
            chords.insert(KeyChord(keyCode: UInt16(entry.keyCode), modifiers: bits))
        }
        chords.formUnion(extraChords)
    }

    public func contains(_ chord: KeyChord) -> Bool { chords.contains(chord) }
}

/// 탭 콜백의 맞춤 상태 기계(연구 §1-3). 표와 비교만 하고 친 키 내용을 남기지 않는다(T-04-63).
/// 삼킨 keyDown의 keyCode 하나만 기억해 짝 keyUp·자동 반복을 삼킨다. 다음 keyUp·reset에 지운다.
public struct ShortcutMatcher: Sendable {
    public enum Action: Equatable, Sendable {
        case pass, swallow, switchTo(SourceID)
    }

    public var table: [KeyChord: SourceID]
    /// 녹화 중이거나 꺼진 동안 true. 맞춤은 쉬고 이미 삼킨 키의 나머지 이벤트만 삼킨다.
    public var paused: Bool
    private var swallowedKeyCode: UInt16?

    public init(table: [KeyChord: SourceID] = [:], paused: Bool = false) {
        self.table = table
        self.paused = paused
    }

    public mutating func handle(
        isDown: Bool, keyCode: UInt16, flags: UInt64, autorepeat: Bool
    ) -> Action {
        if swallowedKeyCode == keyCode {
            if !isDown { swallowedKeyCode = nil }
            return .swallow
        }
        guard isDown, !paused else { return .pass }
        let chord = KeyChord(keyCode: keyCode, modifiers: flags)
        guard let target = table[chord] else { return .pass }
        swallowedKeyCode = keyCode
        return autorepeat ? .swallow : .switchTo(target)
    }

    public mutating func reset() { swallowedKeyCode = nil }
}

/// 저장하지 않고 그릴 때 계산하는 표시 글자(연구 §2-3, §4). 수정 키 순서는 ⌃⌥⇧⌘(HIG).
public enum ChordFormatter {
    public static func modifierText(_ modifiers: UInt64) -> String {
        var text = ""
        if modifiers & 0x40000 != 0 { text += "⌃" }
        if modifiers & 0x80000 != 0 { text += "⌥" }
        if modifiers & 0x20000 != 0 { text += "⇧" }
        if modifiers & 0x100000 != 0 { text += "⌘" }
        return text
    }

    /// - Parameter keyName: ASCII 가능 자판에서 얻은 글자(04-21 FnCapsSystem). nil이면 `#38`.
    public static func text(_ chord: KeyChord, keyName: (UInt16) -> String?) -> String {
        modifierText(chord.modifiers) + keyText(chord.keyCode, keyName: keyName)
    }

    static func keyText(_ keyCode: UInt16, keyName: (UInt16) -> String?) -> String {
        if let special = specialKeys[keyCode] { return special }
        if let name = keyName(keyCode), !name.isEmpty { return name.uppercased() }
        return "#\(keyCode)"
    }

    /// 고정 기호 표(KeyboardShortcuts `keyToSpecialKeyMapping` 참고, MIT). 키코드는 Carbon `kVK_*`.
    public static let specialKeys: [UInt16: String] = [
        36: "↩", 48: "⇥", 49: "␣", 51: "⌫", 117: "⌦", 53: "⎋",
        123: "←", 124: "→", 125: "↓", 126: "↑",
        115: "↖", 119: "↘", 116: "⇞", 121: "⇟",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
        98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
        105: "F13", 107: "F14", 113: "F15", 106: "F16",
        64: "F17", 79: "F18", 80: "F19", 90: "F20",
    ]
}
