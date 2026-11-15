import Foundation
import Testing
@testable import FnCapsCore

/// 가짜 시스템 단축키 저장소. 실제 시스템에 닿지 않는다.
final class FakePrefs {
    var all: [String: Any]
    var writes = 0
    var activates = 0
    var activateOK = true
    var canActivate = true
    var onWrite: (() -> Void)?

    init(hotkey60: [String: Any]?, others: [String: Any] = ["32": ["enabled": true, "value": ["type": "standard", "parameters": [65535, 123, 8650752]] as [String: Any]] as [String: Any]]) {
        all = others
        if let hotkey60 { all["60"] = hotkey60 }
    }

    var entry60: [String: Any]? { all["60"] as? [String: Any] }

    var prefs: ShortcutPreferences {
        ShortcutPreferences(
            read: { [unowned self] in self.all },
            write: { [unowned self] new in
                self.writes += 1
                self.onWrite?()
                self.all = new
                return true
            },
            canActivate: { [unowned self] in self.canActivate },
            activate: { [unowned self] done in
                self.activates += 1
                done(self.activateOK)
            })
    }
}

private func userEntry() -> [String: Any] {
    ["enabled": true, "value": ["type": "standard", "parameters": [32, 49, 262144]] as [String: Any]]
}

private func ours(_ kc: Int, mask: Int = 0) -> [String: Any] {
    ["enabled": true, "value": ["type": "standard", "parameters": [65535, kc, mask]] as [String: Any]]
}

private final class Clock {
    var t: TimeInterval = 1000
}

private func make(_ p: FakePrefs, _ d: UserDefaults = MemoryDefaults(), clock: Clock = Clock()) -> ShortcutManager {
    ShortcutManager(defaults: d, prefs: p.prefs, now: { clock.t })
}

private func sync(_ body: (@escaping (Bool) -> Void) -> Void) -> Bool {
    var result: Bool?
    body { result = $0 }
    return result ?? false
}

private func equal(_ a: [String: Any]?, _ b: [String: Any]?) -> Bool {
    guard let a, let b else { return a == nil && b == nil }
    return NSDictionary(dictionary: a).isEqual(to: b)
}

@Suite struct ShortcutOwnershipTests {
    // MARK: 적용

    @Test func backupIsSavedBeforeWriteAndReadBack() {
        let d = MemoryDefaults()
        let p = FakePrefs(hotkey60: userEntry())
        var backedUpAtWrite = false
        var originalAtWrite: Data?
        p.onWrite = {
            backedUpAtWrite = d.bool(forKey: ShortcutManager.backedUpKey)
            originalAtWrite = d.data(forKey: ShortcutManager.originalKey)
        }
        let m = make(p, d)
        #expect(sync { m.apply(keyCode: 79, completion: $0) })
        #expect(backedUpAtWrite)
        #expect(originalAtWrite != nil)
        #expect(ShortcutOwnership.isOurs(entry: p.entry60, keyCode: 79))
        #expect(p.activates == 1)
    }

    @Test func unverifiedBackupMeansNoWrite() {
        let d = DroppingDefaults()
        d.droppedKeys = [ShortcutManager.backedUpKey]
        let p = FakePrefs(hotkey60: userEntry())
        let m = make(p, d)
        #expect(sync { m.apply(keyCode: 79, completion: $0) } == false)
        #expect(p.writes == 0)
        #expect(p.activates == 0)
        #expect(equal(p.entry60, userEntry()))
    }

    @Test func unverifiedOriginalMeansNoWrite() {
        let d = DroppingDefaults()
        d.droppedKeys = [ShortcutManager.originalKey]
        let p = FakePrefs(hotkey60: userEntry())
        let m = make(p, d)
        #expect(sync { m.apply(keyCode: 79, completion: $0) } == false)
        #expect(p.writes == 0)
    }

    @Test func missingActivateSettingsMeansNoWrite() {
        let p = FakePrefs(hotkey60: userEntry())
        p.canActivate = false
        let m = make(p)
        #expect(sync { m.apply(keyCode: 79, completion: $0) } == false)
        #expect(p.writes == 0)
        #expect(p.activates == 0)
        #expect(m.hasStoredState == false)
    }

    @Test func activateFailureRevertsAndRetriesEvery30Seconds() {
        let clock = Clock()
        let p = FakePrefs(hotkey60: userEntry())
        p.activateOK = false
        let m = make(p, clock: clock)
        #expect(sync { m.apply(keyCode: 79, completion: $0) } == false)
        #expect(equal(p.entry60, userEntry()))
        let writesAfterFirst = p.writes
        clock.t += 10
        #expect(sync { m.apply(keyCode: 79, completion: $0) } == false)  // 간격 대기: 호출도 false
        #expect(p.writes == writesAfterFirst)
        clock.t += 25
        p.activateOK = true
        #expect(sync { m.apply(keyCode: 79, completion: $0) })
        #expect(ShortcutOwnership.isOurs(entry: p.entry60, keyCode: 79))
    }

    @Test func activateFailureOnKeyChangeRevertsToPreviousOurValue() {
        let p = FakePrefs(hotkey60: userEntry())
        let m = make(p)
        #expect(sync { m.apply(keyCode: 79, completion: $0) })
        p.activateOK = false
        let clock = Clock()
        _ = clock
        #expect(sync { m.apply(keyCode: 80, completion: $0) } == false)
        #expect(ShortcutOwnership.isOurs(entry: p.entry60, keyCode: 79))
        #expect(equal(p.entry60, ours(79)))
    }

    @Test func managedKeyChangeKeepsBackup() {
        let p = FakePrefs(hotkey60: userEntry())
        let d = MemoryDefaults()
        let m = make(p, d)
        #expect(sync { m.apply(keyCode: 79, completion: $0) })
        let backup = d.data(forKey: ShortcutManager.originalKey)
        #expect(sync { m.apply(keyCode: 80, completion: $0) })
        #expect(d.data(forKey: ShortcutManager.originalKey) == backup)
        #expect(ShortcutOwnership.isOurs(entry: p.entry60, keyCode: 80))
    }

    @Test func existingOurShapedValueWithoutStoredStateIsBackedUpAsOriginal() {
        // CR-01: 저장 상태가 없으면 #60이 앱과 같은 모양이어도 사용자의 원래 값이다.
        let p = FakePrefs(hotkey60: ours(79))
        let d = MemoryDefaults()
        let m = make(p, d)
        #expect(sync { m.apply(keyCode: 79, completion: $0) })
        #expect(d.bool(forKey: ShortcutManager.backedUpKey))
        #expect(d.data(forKey: ShortcutManager.originalKey) != nil)
        #expect(d.object(forKey: ShortcutManager.managedKey) as? Int == 79)
        #expect(sync { m.restore(force: true, completion: $0) })
        #expect(equal(p.entry60, ours(79)))
        #expect(m.hasStoredState == false)
    }

    @Test func storedStateWithOurValueDoesNotChangeBackup() {
        // 저장 상태가 있으면 #60 = 앱 값은 앱이 쓴 값이다: 백업을 바꾸지 않는다.
        let p = FakePrefs(hotkey60: userEntry())
        let d = MemoryDefaults()
        #expect(sync { make(p, d).apply(keyCode: 79, completion: $0) })
        let backup = d.data(forKey: ShortcutManager.originalKey)
        #expect(sync { make(p, d).apply(keyCode: 79, completion: $0) })
        #expect(d.data(forKey: ShortcutManager.originalKey) == backup)
        #expect(sync { make(p, d).restore(force: true, completion: $0) })
        #expect(equal(p.entry60, userEntry()))
    }

    @Test func userChangedValueBecomesNewBackup() {
        let p = FakePrefs(hotkey60: userEntry())
        let d = MemoryDefaults()
        let m = make(p, d)
        #expect(sync { m.apply(keyCode: 79, completion: $0) })
        // 사용자가 그동안 값을 바꿨다.
        let changed: [String: Any] = ["enabled": true, "value": ["type": "standard", "parameters": [65535, 12, 1048576]] as [String: Any]]
        p.all["60"] = changed
        let clock = Clock()
        _ = clock
        #expect(sync { m.apply(keyCode: 79, completion: $0) })
        #expect(sync { m.restore(force: true, completion: $0) })
        #expect(equal(p.entry60, changed))
    }

    @Test func maskZeroAndSecondaryFnAreBothOurs() {
        #expect(ShortcutOwnership.isOurs(entry: ours(79, mask: 0), keyCode: 79))
        #expect(ShortcutOwnership.isOurs(entry: ours(79, mask: 0x800000), keyCode: 79))
        #expect(ShortcutOwnership.isOurs(entry: ours(79, mask: 262144), keyCode: 79) == false)
        #expect(ShortcutOwnership.isOurs(entry: userEntry(), keyCode: 79) == false)
        #expect(ShortcutOwnership.isOurs(entry: nil, keyCode: 79) == false)
    }

    @Test func isOursCoversRequestedAndManagedKeyCodes() {
        #expect(ShortcutOwnership.isOurs(entry: ours(79), keyCodes: [80, 79]))
        #expect(ShortcutOwnership.isOurs(entry: ours(79), keyCodes: [80]) == false)
    }

    @Test func otherShortcutsSurviveWrites() {
        let p = FakePrefs(hotkey60: userEntry())
        let other = p.all["32"] as? [String: Any]
        let m = make(p)
        #expect(sync { m.apply(keyCode: 79, completion: $0) })
        #expect(equal(p.all["32"] as? [String: Any], other))
        #expect(sync { m.restore(force: true, completion: $0) })
        #expect(equal(p.all["32"] as? [String: Any], other))
    }

    @Test func applyWithPendingFlagAndOurValueKeepsBackup() {
        let p = FakePrefs(hotkey60: userEntry())
        let d = MemoryDefaults()
        let m = make(p, d)
        #expect(sync { m.apply(keyCode: 79, completion: $0) })
        let backup = d.data(forKey: ShortcutManager.originalKey)
        d.set(true, forKey: ShortcutManager.restorePendingKey)
        let m2 = make(p, d)  // 새 프로세스
        #expect(sync { m2.apply(keyCode: 79, completion: $0) })
        #expect(d.data(forKey: ShortcutManager.originalKey) == backup)
        #expect(d.bool(forKey: ShortcutManager.restorePendingKey) == false)
    }

    // MARK: 복원

    @Test func restoreWritesBackupThenActivatesThenClearsKeys() {
        let p = FakePrefs(hotkey60: userEntry())
        let d = MemoryDefaults()
        let m = make(p, d)
        #expect(sync { m.apply(keyCode: 79, completion: $0) })
        var keysDuringActivate: (Bool, Bool)?
        var entryDuringActivate: [String: Any]?
        let base = p.prefs
        let spy = ShortcutPreferences(
            read: base.read, write: base.write, canActivate: base.canActivate,
            activate: { done in
                keysDuringActivate = (
                    d.bool(forKey: ShortcutManager.backedUpKey), d.data(forKey: ShortcutManager.originalKey) != nil)
                entryDuringActivate = p.entry60
                done(true)
            })
        let m2 = ShortcutManager(defaults: d, prefs: spy, now: { 0 })
        #expect(sync { m2.restore(force: true, completion: $0) })
        #expect(keysDuringActivate?.0 == true)
        #expect(keysDuringActivate?.1 == true)
        #expect(equal(entryDuringActivate, userEntry()))
        #expect(m2.hasStoredState == false)
        #expect(equal(p.entry60, userEntry()))
    }

    /// WR-03: 적용도 되돌리기도 실패해 #60이 앱 값으로 남았을 때, 복원이 백업을 버리지 않는다.
    @Test func failedRollbackKeepsKeyCodeSoRestoreStillReturnsOriginal() {
        let p = FakePrefs(hotkey60: userEntry())
        p.activateOK = false
        var spy = p.prefs
        let baseWrite = spy.write
        var blockWrites = false
        spy.write = { new in blockWrites ? false : baseWrite(new) }
        // activate가 실패하는 순간부터 쓰기를 막아 되돌리기를 실패시킨다.
        spy.activate = { done in
            p.activates += 1
            blockWrites = true
            done(p.activateOK)
        }
        let d = MemoryDefaults()
        let m = ShortcutManager(defaults: d, prefs: spy, now: { 0 })
        #expect(sync { m.apply(keyCode: 79, completion: $0) } == false)
        #expect(ShortcutOwnership.isOurs(entry: p.entry60, keyCode: 79))  // 되돌리지 못했다
        #expect(d.object(forKey: ShortcutManager.pendingKeyCodeKey) != nil)
        blockWrites = false
        p.activateOK = true
        #expect(sync { m.restore(force: true, completion: $0) })
        #expect(equal(p.entry60, userEntry()))
        #expect(m.hasStoredState == false)
    }

    @Test func restoreFailureKeepsKeysAndNextCallRetries() {
        let clock = Clock()
        let p = FakePrefs(hotkey60: userEntry())
        let d = MemoryDefaults()
        let m = make(p, d, clock: clock)
        #expect(sync { m.apply(keyCode: 79, completion: $0) })
        p.activateOK = false
        #expect(sync { m.restore(force: true, completion: $0) } == false)
        #expect(equal(p.entry60, userEntry()))  // 값은 이미 돌아갔다
        #expect(d.bool(forKey: ShortcutManager.restorePendingKey))
        #expect(d.data(forKey: ShortcutManager.originalKey) != nil)
        p.activateOK = true
        clock.t += 31
        #expect(sync { m.restore(force: false, completion: $0) })
        #expect(m.hasStoredState == false)
    }

    @Test func restoreRetryWaitsThirtySecondsButForceIgnoresIt() {
        let clock = Clock()
        let p = FakePrefs(hotkey60: userEntry())
        let m = make(p, clock: clock)
        #expect(sync { m.apply(keyCode: 79, completion: $0) })
        p.activateOK = false
        #expect(sync { m.restore(force: true, completion: $0) } == false)
        let w = p.writes, a = p.activates
        clock.t += 5
        #expect(sync { m.restore(force: false, completion: $0) } == false)
        #expect(p.writes == w)
        #expect(p.activates == a)
        p.activateOK = true
        #expect(sync { m.restore(force: true, completion: $0) })
        #expect(p.activates == a + 1)
    }

    @Test func restoreWhenNotOursOnlyClearsBackup() {
        let p = FakePrefs(hotkey60: userEntry())
        let d = MemoryDefaults()
        let m = make(p, d)
        #expect(sync { m.apply(keyCode: 79, completion: $0) })
        let changed: [String: Any] = ["enabled": false, "value": ["type": "standard", "parameters": [65535, 65535, 0]] as [String: Any]]
        p.all["60"] = changed
        let w = p.writes, a = p.activates
        #expect(sync { m.restore(force: true, completion: $0) })
        #expect(p.writes == w)
        #expect(p.activates == a)
        #expect(equal(p.entry60, changed))
        #expect(m.hasStoredState == false)
    }

    @Test func originalWithoutEntryIsRemovedOnRestore() {
        let p = FakePrefs(hotkey60: nil)
        let m = make(p)
        #expect(sync { m.apply(keyCode: 79, completion: $0) })
        #expect(sync { m.restore(force: true, completion: $0) })
        #expect(p.entry60 == nil)
    }

    @Test func disabledOriginalReturnsDisabled() {
        let disabled: [String: Any] = ["enabled": false, "value": ["type": "standard", "parameters": [32, 49, 262144]] as [String: Any]]
        let p = FakePrefs(hotkey60: disabled)
        let m = make(p)
        #expect(sync { m.apply(keyCode: 79, completion: $0) })
        #expect(sync { m.restore(force: true, completion: $0) })
        #expect(equal(p.entry60, disabled))
    }

    @Test func brokenBackupFallsBackToDeletingEntry() {
        let p = FakePrefs(hotkey60: userEntry())
        let d = MemoryDefaults()
        let m = make(p, d)
        #expect(sync { m.apply(keyCode: 79, completion: $0) })
        // 백업을 깨뜨린다: parameters가 2개뿐.
        let broken: [String: Any] = ["enabled": true, "value": ["type": "standard", "parameters": [32, 49]] as [String: Any]]
        d.set(try! PropertyListSerialization.data(fromPropertyList: broken, format: .binary, options: 0), forKey: ShortcutManager.originalKey)
        #expect(sync { m.restore(force: true, completion: $0) })
        #expect(p.entry60 == nil)
    }

    @Test func noBackupAndOurValueRestoreDeletesEntry() {
        let p = FakePrefs(hotkey60: ours(79))
        let d = MemoryDefaults()
        d.set(79, forKey: ShortcutManager.managedKey)
        let m = make(p, d)
        #expect(sync { m.restore(force: true, completion: $0) })
        #expect(p.entry60 == nil)
    }

    @Test func nothingToDoStoresNothingAndWritesNothing() {
        let p = FakePrefs(hotkey60: userEntry())
        let d = MemoryDefaults()
        let m = make(p, d)
        #expect(sync { m.restore(force: true, completion: $0) })
        #expect(p.writes == 0)
        #expect(p.activates == 0)
        #expect(d.store.isEmpty)
    }

    @Test func originalIsKeptWhileValueIsOurs() {
        let p = FakePrefs(hotkey60: userEntry())
        let d = MemoryDefaults()
        let m = make(p, d)
        #expect(sync { m.apply(keyCode: 79, completion: $0) })
        // 쓰기는 실패하지만 값이 남아 있는 상황: 복원 쓰기 실패.
        let bad = FakePrefs(hotkey60: ours(79))
        bad.all = p.all
        let spy = ShortcutPreferences(
            read: { bad.all }, write: { _ in false }, canActivate: { true }, activate: { $0(true) })
        let m2 = ShortcutManager(defaults: d, prefs: spy, now: { 0 })
        #expect(sync { m2.restore(force: true, completion: $0) } == false)
        #expect(d.data(forKey: ShortcutManager.originalKey) != nil)
    }

    // MARK: 키 선택

    @Test func pickSkipsKeysUsedByOtherShortcutsAndMappings() {
        let used: [String: Any] = [
            "100": ["enabled": true, "value": ["parameters": [65535, 79, 0]] as [String: Any]] as [String: Any],
            "60": ours(80),
        ]
        let k = CapsKey.pick(hotkeys: used, mappedTargets: [], preferred: nil)
        #expect(k?.keyCode == 80)  // 79는 다른 단축키가 씀, 60번 항목의 80은 세지 않음
        let k2 = CapsKey.pick(hotkeys: used, mappedTargets: [CapsKey.candidates[1].usage], preferred: nil)
        #expect(k2?.keyCode == 64)
    }

    @Test func pickKeepsPreferredWhenFreeAndReturnsNilWhenAllUsed() {
        let k = CapsKey.pick(hotkeys: [:], mappedTargets: [], preferred: 80)
        #expect(k?.keyCode == 80)
        var all: [String: Any] = [:]
        for (i, c) in CapsKey.candidates.enumerated() {
            all["\(200 + i)"] = ["enabled": true, "value": ["parameters": [65535, c.keyCode, 0]] as [String: Any]] as [String: Any]
        }
        #expect(CapsKey.pick(hotkeys: all, mappedTargets: [], preferred: 80) == nil)
    }

    @Test func pickIgnoresPreferredWhenTaken() {
        let all: [String: Any] = [
            "300": ["enabled": true, "value": ["parameters": [65535, 80, 0]] as [String: Any]] as [String: Any]
        ]
        #expect(CapsKey.pick(hotkeys: all, mappedTargets: [], preferred: 80)?.keyCode == 79)
    }
}

/// W5: 백업해 둔 #60 원래 조합을 읽는다. 읽기만 하고 시스템에 닿지 않는다.
@Suite struct OriginalChordTests {
    private func plist(_ entry: [String: Any]) -> Data {
        try! PropertyListSerialization.data(fromPropertyList: entry, format: .binary, options: 0)
    }

    private func stored(_ entry: [String: Any]) -> MemoryDefaults {
        let d = MemoryDefaults()
        d.set(plist(entry), forKey: ShortcutManager.originalKey)
        return d
    }

    @Test func readsBackedUpChord() {
        let d = stored(["enabled": true, "value": ["type": "standard", "parameters": [32, 49, 262144]] as [String: Any]])
        #expect(ShortcutManager.originalChord(defaults: d) == KeyChord(keyCode: 49, modifiers: 0x40000))
    }

    @Test func missingKeyReturnsNil() {
        #expect(ShortcutManager.originalChord(defaults: MemoryDefaults()) == nil)
    }

    @Test func disabledOriginalReturnsNil() {
        let d = stored(["enabled": false, "value": ["type": "standard", "parameters": [32, 49, 262144]] as [String: Any]])
        #expect(ShortcutManager.originalChord(defaults: d) == nil)
    }

    @Test func malformedEntryReturnsNil() {
        // parameters가 2개뿐: isWellFormed가 아니다.
        let short = stored(["enabled": true, "value": ["type": "standard", "parameters": [32, 49]] as [String: Any]])
        #expect(ShortcutManager.originalChord(defaults: short) == nil)
        // 사전이 아닌 plist.
        let bad = MemoryDefaults()
        bad.set(Data("not a plist".utf8), forKey: ShortcutManager.originalKey)
        #expect(ShortcutManager.originalChord(defaults: bad) == nil)
        // value가 없다.
        let noValue = stored(["enabled": true])
        #expect(ShortcutManager.originalChord(defaults: noValue) == nil)
    }

    @Test func normalizesNonModifierBits() {
        // 8650752 = 0x840000: fn 비트(0x800000)와 ⌃(0x40000)이 섞인 값은 ⌃만 남긴다.
        let d = stored(["enabled": true, "value": ["type": "standard", "parameters": [32, 123, 8650752]] as [String: Any]])
        #expect(ShortcutManager.originalChord(defaults: d) == KeyChord(keyCode: 123, modifiers: 0x40000))
    }
}

@Suite struct ShortcutLifecycleTests {
    @Test func newInstanceAfterForceKillWithEnabledKeepsBackupAndWritesNothing() {
        let p = FakePrefs(hotkey60: userEntry())
        let d = MemoryDefaults()
        #expect(sync { make(p, d).apply(keyCode: 79, completion: $0) })
        let backup = d.data(forKey: ShortcutManager.originalKey)
        let w = p.writes
        #expect(sync { make(p, d).apply(keyCode: 79, completion: $0) })  // 새 프로세스
        #expect(p.writes == w)
        #expect(d.data(forKey: ShortcutManager.originalKey) == backup)
    }

    @Test func newInstanceAfterForceKillWithDisabledRestoresOriginal() {
        let p = FakePrefs(hotkey60: userEntry())
        let d = MemoryDefaults()
        #expect(sync { make(p, d).apply(keyCode: 79, completion: $0) })
        #expect(sync { make(p, d).restore(force: false, completion: $0) })
        #expect(equal(p.entry60, userEntry()))
        #expect(make(p, d).hasStoredState == false)
    }

    @Test func restoreResumesActivateAfterWriteThenKill() {
        let p = FakePrefs(hotkey60: userEntry())
        let d = MemoryDefaults()
        #expect(sync { make(p, d).apply(keyCode: 79, completion: $0) })
        // 복원 쓰기만 끝나고 activate 전에 종료: 값은 이미 원래대로, 표시와 백업이 남는다.
        p.all["60"] = userEntry()
        d.set(true, forKey: ShortcutManager.restorePendingKey)
        let a = p.activates, w = p.writes
        #expect(sync { make(p, d).restore(force: true, completion: $0) })
        #expect(p.activates == a + 1)
        #expect(p.writes == w)
        #expect(equal(p.entry60, userEntry()))
        #expect(make(p, d).hasStoredState == false)
    }

    @Test func restoreWithPendingAndOurValueWritesBackupBeforeActivateThenClearsKeys() {
        let p = FakePrefs(hotkey60: userEntry())
        let d = MemoryDefaults()
        #expect(sync { make(p, d).apply(keyCode: 79, completion: $0) })
        d.set(true, forKey: ShortcutManager.restorePendingKey)  // 앞 복원이 쓰기 전에 표시만 남기고 종료
        var order: [String] = []
        p.onWrite = { order.append("write") }
        let base = p.prefs
        let spy = ShortcutPreferences(
            read: base.read, write: base.write, canActivate: base.canActivate,
            activate: { done in
                order.append("activate:\(d.data(forKey: ShortcutManager.originalKey) != nil)")
                done(true)
            })
        #expect(sync { ShortcutManager(defaults: d, prefs: spy, now: { 0 }).restore(force: true, completion: $0) })
        #expect(order == ["write", "activate:true"])
        #expect(equal(p.entry60, userEntry()))
        #expect(d.data(forKey: ShortcutManager.originalKey) == nil)
        #expect(d.bool(forKey: ShortcutManager.restorePendingKey) == false)
    }

    // MARK: CR-01 강제 종료 시점별 경로 (사용자의 원래 값 = 앱 모양의 F18)

    /// activate가 끝나지 않는 가짜: 그 지점에서 프로세스가 죽은 것으로 본다.
    private func hanging(_ p: FakePrefs) -> ShortcutPreferences {
        let base = p.prefs
        return ShortcutPreferences(
            read: base.read, write: base.write, canActivate: base.canActivate, activate: { _ in })
    }

    private func finishAndExpectOriginalKept(_ p: FakePrefs, _ d: MemoryDefaults) {
        let backup = d.data(forKey: ShortcutManager.originalKey)
        #expect(backup != nil)
        #expect(sync { make(p, d).apply(keyCode: 79, completion: $0) })
        #expect(d.data(forKey: ShortcutManager.originalKey) == backup)
        #expect(sync { make(p, d).restore(force: true, completion: $0) })
        #expect(equal(p.entry60, ours(79)))
        #expect(make(p, d).hasStoredState == false)
    }

    @Test func crashAfterApplyCompleteKeepsOriginalAppShapedValue() {
        let p = FakePrefs(hotkey60: ours(79))
        let d = MemoryDefaults()
        #expect(sync { make(p, d).apply(keyCode: 79, completion: $0) })
        finishAndExpectOriginalKept(p, d)
    }

    @Test func crashDuringApplyWithPendingKeyCodeKeepsOriginalAppShapedValue() {
        let p = FakePrefs(hotkey60: ours(79))
        let d = MemoryDefaults()
        ShortcutManager(defaults: d, prefs: hanging(p), now: { 0 }).apply(keyCode: 79) { _ in }
        #expect(d.object(forKey: ShortcutManager.pendingKeyCodeKey) as? Int == 79)
        #expect(d.object(forKey: ShortcutManager.managedKey) == nil)
        finishAndExpectOriginalKept(p, d)
    }

    @Test func crashBeforeRestoreWriteKeepsOriginalAppShapedValue() {
        let p = FakePrefs(hotkey60: ours(79))
        let d = MemoryDefaults()
        #expect(sync { make(p, d).apply(keyCode: 79, completion: $0) })
        d.set(true, forKey: ShortcutManager.restorePendingKey)
        finishAndExpectOriginalKept(p, d)
    }

    @Test func crashDuringRestoreBeforeActivateKeepsOriginalAppShapedValue() {
        let p = FakePrefs(hotkey60: ours(79))
        let d = MemoryDefaults()
        #expect(sync { make(p, d).apply(keyCode: 79, completion: $0) })
        ShortcutManager(defaults: d, prefs: hanging(p), now: { 0 }).restore(force: true) { _ in }
        #expect(d.bool(forKey: ShortcutManager.restorePendingKey))
        finishAndExpectOriginalKept(p, d)
    }
}

/// 03-08 WR-10: 읽은 값이 없음(새 계정)과 형식이 사전이 아님(읽기 실패)을 가른다.
@Suite struct ShortcutPreferencesInterpretTests {
    @Test func missingKeyMeansNewAccountStartsEmpty() {
        #expect(ShortcutPreferences.interpret(raw: nil)?.isEmpty == true)
    }

    @Test func dictionaryPassesThroughUnchanged() {
        let raw: Any = ["60": ["enabled": true]] as NSDictionary
        let value = ShortcutPreferences.interpret(raw: raw)
        #expect(value?["60"] != nil)
        #expect(equal(value, ["60": ["enabled": true] as [String: Any]]))
    }

    @Test func nonDictionaryValueIsAReadFailure() {
        #expect(ShortcutPreferences.interpret(raw: "garbage" as NSString) == nil)
        #expect(ShortcutPreferences.interpret(raw: [1, 2] as NSArray) == nil)
    }

    @Test func newAccountCanStartWritingShortcut60() {
        let p = FakePrefs(hotkey60: nil, others: [:])
        // 키가 없는 계정: CFPreferencesCopyAppValue가 nil을 준다.
        var stored: Any?
        let prefs = ShortcutPreferences(
            read: { ShortcutPreferences.interpret(raw: stored) },
            write: { new in
                p.writes += 1
                p.all = new
                stored = new
                return true
            },
            canActivate: { true },
            activate: { done in done(true) })
        let m = ShortcutManager(defaults: MemoryDefaults(), prefs: prefs, now: { 1000 })
        #expect(sync { m.apply(keyCode: 79, completion: $0) })
        #expect(ShortcutOwnership.isOurs(entry: p.entry60, keyCode: 79))
    }
}
