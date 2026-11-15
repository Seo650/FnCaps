import Foundation
import Testing
@testable import FnCapsCore

/// 가짜 키보드. 시스템에 닿지 않는다.
final class FakeKeyboard: KeyboardDevice {
    let registryID: UInt64
    var mappings: [KeyMapping]
    var writes = 0
    var failWrite = false
    var failRead = false
    /// true면 쓰기가 성공처럼 보이지만 값이 바뀌지 않는다(다시 읽기 실패 흉내).
    var ignoreWrites = false
    var onWrite: (() -> Void)?

    init(id: UInt64, mappings: [KeyMapping] = []) {
        registryID = id
        self.mappings = mappings
    }

    struct Failure: Error {}

    func readMappings() throws -> [KeyMapping] {
        if failRead { throw Failure() }
        return mappings
    }

    func writeMappings(_ m: [KeyMapping]) throws {
        writes += 1
        onWrite?()
        if failWrite { throw Failure() }
        if !ignoreWrites { mappings = m }
    }
}

private let caps = CapsKey.capsLockUsage
private let f18 = CapsKey.f18.usage
private let f19: UInt64 = 0x70000006E
private let other = KeyMapping(src: 0x700000064, dst: 0x700000035)

private func manager(_ d: UserDefaults, boot: String = "boot-1") -> KeyMappingManager {
    KeyMappingManager(defaults: d, bootSession: boot)
}

@Suite struct KeyMappingRecordTests {
    @Test func mergeKeepsOtherMappings() {
        let kb = FakeKeyboard(id: 1, mappings: [other])
        let r = manager(MemoryDefaults()).apply(devices: [kb], target: f18)
        #expect(r.results[1] == .ok)
        #expect(KeyMappingOps.sameSet(kb.mappings, [other, KeyMapping(src: caps, dst: f18)]))
    }

    @Test func conflictWritesNothing() {
        let kb = FakeKeyboard(id: 1, mappings: [KeyMapping(src: 0x700000064, dst: f18)])
        let r = manager(MemoryDefaults()).apply(devices: [kb], target: f18)
        #expect(r.results[1] == .conflict)
        #expect(kb.writes == 0)
    }

    @Test func otherCapsMappingIsNotOverwritten() {
        let kb = FakeKeyboard(id: 1, mappings: [KeyMapping(src: caps, dst: 0x700000029)])
        let d = MemoryDefaults()
        let m = manager(d)
        let r = m.apply(devices: [kb], target: f18)
        #expect(r.results[1] == .capsTaken)
        #expect(r.anyCapsTaken)
        #expect(kb.writes == 0)
        #expect(m.hasRecords == false)
    }

    @Test func recordIsSavedBeforeWrite() {
        let d = MemoryDefaults()
        let m = manager(d)
        let kb = FakeKeyboard(id: 7, mappings: [KeyMapping(src: other.src, dst: other.dst)])
        var seen: KeyMappingRecord?
        kb.onWrite = { seen = m.loadRecords()["7"] }
        _ = m.apply(devices: [kb], target: f18)
        #expect(seen == KeyMappingRecord(original: nil, target: f18, pendingTarget: f18, away: false))
        #expect(m.loadRecords()["7"]?.pendingTarget == nil)
    }

    @Test func existingF18WithoutRecordIsKeptAsOriginalAndRestored() {
        // CR-01: 기록 없이 Caps가 이미 F18을 내면 사용자의 원래 값이다. 복원이 그 값을 돌려놓는다.
        let kb = FakeKeyboard(id: 1, mappings: [other, KeyMapping(src: caps, dst: f18)])
        let m = manager(MemoryDefaults())
        let a = m.apply(devices: [kb], target: f18)
        #expect(a.allApplied)
        #expect(m.loadRecords()["1"]?.original == f18)
        let r = m.restore(devices: [kb])
        #expect(r.restoreComplete)
        #expect(KeyMappingOps.sameSet(kb.mappings, [other, KeyMapping(src: caps, dst: f18)]))
        #expect(m.hasRecords == false)
    }

    @Test func existingF18KeepsOriginalAcrossReapplyWithRecord() {
        let kb = FakeKeyboard(id: 1, mappings: [KeyMapping(src: caps, dst: f18)])
        let d = MemoryDefaults()
        _ = manager(d).apply(devices: [kb], target: f18)
        // 새 실행: 기록이 있으므로 original은 그대로다.
        let m2 = manager(d)
        _ = m2.apply(devices: [kb], target: f18)
        #expect(m2.loadRecords()["1"]?.original == f18)
    }

    @Test func restoreReturnsToOriginalCapsMapping() {
        let orig: UInt64 = 0x700000039 + 1
        // 원래 Caps가 다른 값을 낸다 -> capsTaken이라 덮어쓰지 않는다. 원래 값 복원은 기록 있는 경우로 시험한다.
        let kb = FakeKeyboard(id: 1, mappings: [KeyMapping(src: caps, dst: orig)])
        let d = MemoryDefaults()
        // 앞 실행 기록: original = orig, target = f18, 지금 Caps = f18
        let rec = KeyMappingRecord(original: orig, target: f18)
        d.set(["1": try! JSONEncoder().encode(rec)], forKey: KeyMappingManager.recordsKey)
        kb.mappings = [KeyMapping(src: caps, dst: f18)]
        let m = manager(d)
        let r = m.restore(devices: [kb])
        #expect(r.results[1] == .ok)
        #expect(kb.mappings == [KeyMapping(src: caps, dst: orig)])
        #expect(m.hasRecords == false)
    }

    @Test func readbackMismatchRevertsAndFails() {
        let kb = FakeKeyboard(id: 1, mappings: [other])
        kb.ignoreWrites = true
        let m = manager(MemoryDefaults())
        let r = m.apply(devices: [kb], target: f18)
        #expect(r.results[1] == .failed)
        #expect(KeyMappingOps.sameSet(kb.mappings, [other]))
        #expect(kb.writes == 2)  // 적용 시도 + 되돌림 시도
        #expect(m.hasRecords == false)
    }

    /// WR-04: 쓰기가 실패하고 되돌리기가 성공해도, 쓰기 전 기록이 있었으면 지우지 않는다.
    @Test func failedWriteAfterRecordedMappingKeepsRecord() {
        let kb = FakeKeyboard(id: 1, mappings: [KeyMapping(src: caps, dst: f18)])
        let d = MemoryDefaults()
        let rec = KeyMappingRecord(original: nil, target: f18)
        d.set(["1": try! JSONEncoder().encode(rec)], forKey: KeyMappingManager.recordsKey)
        let m = manager(d)
        kb.failWrite = true
        let r = m.apply(devices: [kb], target: f19)
        #expect(r.results[1] == .failed)
        #expect(m.loadRecords()["1"]?.target == f18)
        #expect(m.loadRecords()["1"]?.pendingTarget == nil)
        kb.failWrite = false
        // 기록이 남아 있으니 Caps -> F18은 남의 매핑이 아니라 우리 것이다.
        #expect(m.check(devices: [kb], target: f18).results[1] == .ok)
        #expect(m.restore(devices: [kb]).results[1] == .ok)
        #expect(KeyMappingOps.capsOutput(kb.mappings) == nil)
    }

    @Test func oneKeyboardFailureDoesNotBlockTheOther() {
        let bad = FakeKeyboard(id: 1)
        bad.failWrite = true
        let good = FakeKeyboard(id: 2)
        let r = manager(MemoryDefaults()).apply(devices: [bad, good], target: f18)
        #expect(r.results[1] == .failed)
        #expect(r.results[2] == .ok)
        #expect(good.mappings == [KeyMapping(src: caps, dst: f18)])
        #expect(r.allApplied == false)
    }

    @Test func restoreOnlyWhenCapsOutputsOurTarget() {
        let m = manager(MemoryDefaults())
        let kb = FakeKeyboard(id: 1)
        _ = m.apply(devices: [kb], target: f18)
        // 사용자가 그동안 Caps를 다른 값으로 바꿨다.
        kb.mappings = [KeyMapping(src: caps, dst: 0x700000029)]
        let before = kb.writes
        let r = m.restore(devices: [kb])
        #expect(kb.writes == before)
        #expect(r.results[1] == .ok)
        #expect(kb.mappings == [KeyMapping(src: caps, dst: 0x700000029)])
        #expect(m.hasRecords == false)
    }

    @Test func failedRestoreKeepsRecord() {
        let m = manager(MemoryDefaults())
        let kb = FakeKeyboard(id: 1)
        _ = m.apply(devices: [kb], target: f18)
        kb.ignoreWrites = true
        let r = m.restore(devices: [kb])
        #expect(r.results[1] == .failed)
        #expect(r.restoreComplete == false)
        #expect(m.hasRecords)
    }

    @Test func comparisonIgnoresOrder() {
        let a = [KeyMapping(src: 1, dst: 2), KeyMapping(src: 3, dst: 4)]
        #expect(KeyMappingOps.sameSet(a, a.reversed()))
        #expect(KeyMappingOps.sameSet(a, [KeyMapping(src: 1, dst: 2)]) == false)
    }

    @Test func newManagerResumesAfterForceKill() {
        let d = MemoryDefaults()
        let orig: UInt64 = 0x700000029
        let kb = FakeKeyboard(id: 1)
        // 앞 실행: original = orig, 쓰기 직후 강제 종료(pendingTarget 남음)
        let rec = KeyMappingRecord(original: orig, target: f18, pendingTarget: f18)
        d.set(["1": try! JSONEncoder().encode(rec)], forKey: KeyMappingManager.recordsKey)
        d.set("boot-1", forKey: KeyMappingManager.bootKey)
        kb.mappings = [KeyMapping(src: caps, dst: f18)]
        let m2 = manager(d)
        let r = m2.apply(devices: [kb], target: f18)
        #expect(r.results[1] == .ok)
        #expect(m2.loadRecords()["1"]?.original == orig)  // F18을 원래 값으로 저장하지 않는다
        #expect(m2.loadRecords()["1"]?.pendingTarget == nil)
        _ = m2.restore(devices: [kb])
        #expect(kb.mappings == [KeyMapping(src: caps, dst: orig)])
    }

    @Test func secondApplyWithSameTargetIsUnchanged() {
        let m = manager(MemoryDefaults())
        let kb = FakeKeyboard(id: 1)
        _ = m.apply(devices: [kb], target: f18)
        let w = kb.writes
        let r = m.apply(devices: [kb], target: f18)
        #expect(r.results[1] == .unchanged)
        #expect(kb.writes == w)
        #expect(r.allApplied)
    }

    @Test func bootSessionChangeClearsRecords() {
        let d = MemoryDefaults()
        let kb = FakeKeyboard(id: 1)
        _ = manager(d, boot: "boot-1").apply(devices: [kb], target: f18)
        #expect(manager(d, boot: "boot-1").hasRecords)
        #expect(manager(d, boot: "boot-2").hasRecords == false)
    }

    @Test func differentTargetKeepsOriginal() {
        let d = MemoryDefaults()
        let orig: UInt64 = 0x700000029
        let rec = KeyMappingRecord(original: orig, target: f18)
        d.set(["1": try! JSONEncoder().encode(rec)], forKey: KeyMappingManager.recordsKey)
        let kb = FakeKeyboard(id: 1, mappings: [KeyMapping(src: caps, dst: f18)])
        let m = manager(d)
        let r = m.apply(devices: [kb], target: f19)
        #expect(r.results[1] == .ok)
        #expect(m.loadRecords()["1"]?.original == orig)
        #expect(m.loadRecords()["1"]?.target == f19)
    }

    // MARK: 복원과 열거

    @Test func recordForMissingKeyboardIsDroppedAndNotCountedAsFailure() {
        let m = manager(MemoryDefaults())
        let a = FakeKeyboard(id: 1)
        let b = FakeKeyboard(id: 2)
        _ = m.apply(devices: [a, b], target: f18)
        let r = m.restore(devices: [a])
        #expect(r.restoreComplete)
        #expect(r.droppedRecords == [2])
        #expect(a.mappings.isEmpty)
        #expect(m.loadRecords()["2"] == nil)
    }

    @Test func emptyEnumerationKeepsRecordsAndFails() {
        let m = manager(MemoryDefaults())
        let a = FakeKeyboard(id: 1)
        _ = m.apply(devices: [a], target: f18)
        let r = m.restore(devices: [])
        #expect(r.enumerationFailed)
        #expect(r.restoreComplete == false)
        #expect(m.hasRecords)
        let r2 = m.restore(devices: nil)
        #expect(r2.enumerationFailed)
        #expect(m.hasRecords)
    }

    @Test func noRecordsAndNoKeyboardsIsNotAFailure() {
        let m = manager(MemoryDefaults())
        #expect(m.restore(devices: nil).restoreComplete)
        #expect(m.restore(devices: []).restoreComplete)
    }
}

@Suite struct KeyMappingCheckTests {
    @Test func checkNeverWrites() {
        let m = manager(MemoryDefaults())
        let free = FakeKeyboard(id: 1)
        let taken = FakeKeyboard(id: 2, mappings: [KeyMapping(src: caps, dst: 0x700000029)])
        let clash = FakeKeyboard(id: 3, mappings: [KeyMapping(src: 0x700000064, dst: f18)])
        let r = m.check(devices: [free, taken, clash], target: f18)
        #expect(r.results[1] == .ok)
        #expect(r.results[2] == .capsTaken)
        #expect(r.results[3] == .conflict)
        #expect(free.writes + taken.writes + clash.writes == 0)
        #expect(m.hasRecords == false)
    }
}

@Suite struct KeyMappingLifecycleTests {
    private let esc: UInt64 = 0x700000029

    @Test func awayRoundTripKeepsRecordAndOriginal() {
        let d = MemoryDefaults()
        let m = manager(d)
        let kb = FakeKeyboard(id: 1, mappings: [other])
        #expect(m.apply(devices: [kb], target: f18).results[1] == .ok)
        let away = m.markAway(devices: [kb])
        #expect(away.results[1] == .ok)
        #expect(KeyMappingOps.sameSet(kb.mappings, [other]))  // Caps가 원래대로
        let rec = m.loadRecords()["1"]
        #expect(rec?.away == true)
        #expect(rec?.original == nil)
        #expect(m.hasRecords)
        // 복귀: 재적용하면 away가 지워지고 original이 그대로다.
        #expect(m.apply(devices: [kb], target: f18).results[1] == .ok)
        #expect(m.loadRecords()["1"]?.away == false)
        #expect(m.loadRecords()["1"]?.original == nil)
        #expect(KeyMappingOps.sameSet(kb.mappings, [other, KeyMapping(src: caps, dst: f18)]))
    }

    @Test func awayWithNonNilOriginalReturnsItAndKeepsIt() {
        let d = MemoryDefaults()
        let rec = KeyMappingRecord(original: esc, target: f18)
        d.set(["1": try! JSONEncoder().encode(rec)], forKey: KeyMappingManager.recordsKey)
        d.set("boot-1", forKey: KeyMappingManager.bootKey)
        let kb = FakeKeyboard(id: 1, mappings: [KeyMapping(src: caps, dst: f18)])
        let m = manager(d)
        #expect(m.markAway(devices: [kb]).results[1] == .ok)
        #expect(kb.mappings == [KeyMapping(src: caps, dst: esc)])
        // 원래 값이 나오는 것은 남의 매핑이 아니다: 점유로 보지 않고 original을 잇는다.
        #expect(m.check(devices: [kb], target: f18).results[1] == .ok)
        #expect(m.apply(devices: [kb], target: f18).results[1] == .ok)
        #expect(m.loadRecords()["1"]?.original == esc)
        _ = m.restore(devices: [kb])
        #expect(kb.mappings == [KeyMapping(src: caps, dst: esc)])
    }

    @Test func otherUsersF18DuringAwayIsNeverStoredAsOriginal() {
        let d = MemoryDefaults()
        let m = manager(d)
        let kb = FakeKeyboard(id: 1)
        _ = m.apply(devices: [kb], target: f18)
        _ = m.markAway(devices: [kb])
        // 다른 사용자 세션이 같은 값을 만들어 두었다.
        kb.mappings = [KeyMapping(src: caps, dst: f18)]
        _ = m.apply(devices: [kb], target: f18)
        #expect(m.loadRecords()["1"]?.original == nil)
        _ = m.restore(devices: [kb])
        #expect(kb.mappings.isEmpty)
    }

    @Test func awayWithoutRecordsOrKeyboardsWritesNothing() {
        let m = manager(MemoryDefaults())
        let kb = FakeKeyboard(id: 1)
        #expect(m.markAway(devices: [kb]).results.isEmpty)
        #expect(kb.writes == 0)
        _ = m.apply(devices: [kb], target: f18)
        #expect(m.markAway(devices: []).enumerationFailed)
        #expect(m.markAway(devices: nil).enumerationFailed)
        #expect(m.hasRecords)
    }

    @Test func awayWriteFailureKeepsRecordNotAway() {
        let m = manager(MemoryDefaults())
        let kb = FakeKeyboard(id: 1)
        _ = m.apply(devices: [kb], target: f18)
        kb.failWrite = true
        #expect(m.markAway(devices: [kb]).results[1] == .failed)
        #expect(m.loadRecords()["1"]?.away == false)
    }

    @Test func bootChangeClearsMappingRecordsButKeepsShortcutBackup() {
        let d = MemoryDefaults()
        let p = FakePrefs(hotkey60: ["enabled": true, "value": ["type": "standard", "parameters": [32, 49, 262144]] as [String: Any]])
        let s = ShortcutManager(defaults: d, prefs: p.prefs, now: { 0 })
        var ok = false
        s.apply(keyCode: 79) { ok = $0 }
        #expect(ok)
        let kb = FakeKeyboard(id: 1)
        _ = manager(d, boot: "boot-1").apply(devices: [kb], target: f18)
        let rec = KeyMappingRecord(original: nil, target: f18, pendingTarget: f18)
        d.set(["1": try! JSONEncoder().encode(rec)], forKey: KeyMappingManager.recordsKey)
        let after = manager(d, boot: "boot-2")
        #expect(after.hasRecords == false)
        let s2 = ShortcutManager(defaults: d, prefs: p.prefs, now: { 0 })
        #expect(s2.hasStoredState)
        #expect(d.bool(forKey: ShortcutManager.backedUpKey))
        #expect(d.data(forKey: ShortcutManager.originalKey) != nil)
    }

    @Test func rebootWithoutAppThenRestoreWritesNoMappingAndReturnsShortcut() {
        let d = MemoryDefaults()
        let user: [String: Any] = ["enabled": true, "value": ["type": "standard", "parameters": [32, 49, 262144]] as [String: Any]]
        let p = FakePrefs(hotkey60: user)
        let s = ShortcutManager(defaults: d, prefs: p.prefs, now: { 0 })
        var ok = false
        s.apply(keyCode: 79) { ok = $0 }
        #expect(ok)
        // 재부팅: 매핑은 사라지고, 기록은 부트 변경으로 지워진다.
        let kb = FakeKeyboard(id: 1)
        let m = manager(d, boot: "boot-9")
        let w = kb.writes
        #expect(m.restore(devices: [kb]).restoreComplete)
        #expect(kb.writes == w)
        var restored = false
        ShortcutManager(defaults: d, prefs: p.prefs, now: { 0 }).restore(force: true) { restored = $0 }
        #expect(restored)
        #expect(NSDictionary(dictionary: p.entry60 ?? [:]).isEqual(to: user))
    }

    @Test func warnsOnlyAfterThreeConsecutiveFailuresAndSuccessResets() {
        let m = manager(MemoryDefaults())
        let kb = FakeKeyboard(id: 1)
        kb.failWrite = true
        #expect(m.apply(devices: [kb], target: f18).shouldWarn == false)
        #expect(m.apply(devices: [kb], target: f18).shouldWarn == false)
        #expect(m.apply(devices: [kb], target: f18).shouldWarn)
        kb.failWrite = false
        let r = m.apply(devices: [kb], target: f18)
        #expect(r.results[1] == .ok)
        #expect(r.shouldWarn == false)
        // 성공 뒤 횟수는 0이다: 다시 실패 두 번까지는 경고하지 않는다.
        let m2 = manager(MemoryDefaults())
        let kb2 = FakeKeyboard(id: 2)
        kb2.failWrite = true
        _ = m2.apply(devices: [kb2], target: f18)
        _ = m2.apply(devices: [kb2], target: f18)
        kb2.failWrite = false
        _ = m2.apply(devices: [kb2], target: f18)
        kb2.failWrite = true
        kb2.mappings = []
        #expect(m2.apply(devices: [kb2], target: f18).shouldWarn == false)
    }

    @Test func newKeyboardGetsAppliedAndExistingOneIsNotWritten() {
        let m = manager(MemoryDefaults())
        let a = FakeKeyboard(id: 1)
        _ = m.apply(devices: [a], target: f18)
        let w = a.writes
        let b = FakeKeyboard(id: 2)
        let r = m.apply(devices: [a, b], target: f18)
        #expect(r.results[1] == .unchanged)
        #expect(r.results[2] == .ok)
        #expect(a.writes == w)
        #expect(b.mappings == [KeyMapping(src: caps, dst: f18)])
    }
}
