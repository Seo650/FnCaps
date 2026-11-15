import Foundation
import Testing
@testable import FnCapsCore

@Suite struct DragSessionTests {
    private let counts: [SourceList: Int] = [.caps: 1, .fn: 3, .excluded: 0]

    private func fnSession() -> DragSession { DragSession(id: "k", origin: .fn, originIndex: 1) }

    @Test func initialTargetIsOrigin() {
        #expect(fnSession().target == .slot(.fn, 1))
    }

    @Test func staysInPlaceAtOriginalAngle() {
        var s = fnSession()
        s.update(zone: .fn, angle: RingGeometry.slotAngle(index: 1, count: 3), counts: counts)
        #expect(s.target == .slot(.fn, 1))
    }

    @Test func otherBoxOpensSlotByAngle() {
        var s = fnSession()
        s.update(zone: .caps, angle: 0, counts: counts)
        #expect(s.target == .slot(.caps, 1))
        var t = fnSession()
        t.update(zone: .caps, angle: .pi, counts: counts)
        #expect(t.target == .slot(.caps, 0))
    }

    @Test func fullOtherBoxRefuses() {
        var s = fnSession()
        s.update(zone: .caps, angle: 0, counts: [.caps: 6, .fn: 3, .excluded: 0])
        #expect(s.target == .refused(.caps))
    }

    @Test func fullOwnBoxIsNotRefused() {
        var s = DragSession(id: "c", origin: .caps, originIndex: 2)
        s.update(zone: .caps, angle: RingGeometry.slotAngle(index: 2, count: 6), counts: [.caps: 6, .fn: 0, .excluded: 0])
        #expect(s.target == .slot(.caps, 2))
    }

    @Test func excludedBoxAppendsAtEndIgnoringAngle() {
        var s = fnSession()
        s.update(zone: .excluded, angle: 1.0, counts: [.caps: 1, .fn: 3, .excluded: 2])
        #expect(s.target == .slot(.excluded, 2))
        // 같은 상자 안에서는 빈 칸이 원래 자리에 남는다(WR-04).
        var e = DragSession(id: "x", origin: .excluded, originIndex: 0)
        e.update(zone: .excluded, angle: nil, counts: [.caps: 1, .fn: 3, .excluded: 2])
        #expect(e.target == .slot(.excluded, 0))
        #expect(e.outcome() == .none)
    }

    @Test func nilZoneIsNone() {
        var s = fnSession()
        s.update(zone: nil, angle: nil, counts: counts)
        #expect(s.target == .none)
    }

    @Test func nilAngleInKeyBoxMeansFront() {
        var s = fnSession()
        s.update(zone: .caps, angle: nil, counts: counts)
        #expect(s.target == .slot(.caps, 0))
    }

    @Test func sameZoneUsesPreviousForHysteresis() {
        // fn 3개, 칸 수 m = 3. 칸 0(180°)과 칸 1(300°)의 경계는 240°.
        var s = fnSession()
        s.update(zone: .fn, angle: 185 * .pi / 180, counts: counts)
        #expect(s.target == .slot(.fn, 0))
        s.update(zone: .fn, angle: 245 * .pi / 180, counts: counts)
        #expect(s.target == .slot(.fn, 0))
        s.update(zone: .fn, angle: 250 * .pi / 180, counts: counts)
        #expect(s.target == .slot(.fn, 1))
    }

    @Test func enteringFromOtherZoneHasNoPrevious() {
        // caps 칸 0이 앞 target이어도, fn에 들어오면 previous 없이 가장 가까운 칸이다.
        var s = fnSession()
        s.update(zone: .caps, angle: .pi, counts: counts)
        #expect(s.target == .slot(.caps, 0))
        s.update(zone: .fn, angle: 245 * .pi / 180, counts: counts)
        #expect(s.target == .slot(.fn, 1))
    }

    @Test func slotsOpenGapInOwnRing() {
        var s = fnSession()
        s.update(zone: .fn, angle: RingGeometry.slotAngle(index: 2, count: 3), counts: counts)
        #expect(s.target == .slot(.fn, 2))
        #expect(s.slots(for: .fn, ids: ["a", "k", "b"]) == ["a", "b", nil])
    }

    @Test func slotsCloseOriginWhenTargetElsewhere() {
        var s = fnSession()
        s.update(zone: .caps, angle: .pi, counts: counts)
        #expect(s.slots(for: .fn, ids: ["a", "k", "b"]) == ["a", "b"])
        #expect(s.slots(for: .caps, ids: ["c"]) == [nil, "c"])
    }

    @Test func slotsKeepOriginGapWhenNoneOrRefused() {
        var s = fnSession()
        s.update(zone: nil, angle: nil, counts: counts)
        #expect(s.slots(for: .fn, ids: ["a", "k", "b"]) == ["a", nil, "b"])
        var r = fnSession()
        r.update(zone: .caps, angle: 0, counts: [.caps: 6, .fn: 3, .excluded: 0])
        #expect(r.slots(for: .fn, ids: ["a", "k", "b"]) == ["a", nil, "b"])
    }

    @Test func slotsOfUntargetedOtherListUnchanged() {
        let s = fnSession()
        #expect(s.slots(for: .caps, ids: ["c"]) == ["c"])
    }

    @Test func outcomeInPlaceIsNone() {
        #expect(fnSession().outcome() == .none)
    }

    @Test func outcomeMoveToOtherBox() {
        var s = fnSession()
        s.update(zone: .caps, angle: .pi, counts: counts)
        #expect(s.outcome() == .move("k", .caps, 0))
    }

    @Test func outcomeRefusedAndNoneAreNone() {
        var r = fnSession()
        r.update(zone: .caps, angle: 0, counts: [.caps: 6, .fn: 3, .excluded: 0])
        #expect(r.outcome() == .none)
        var n = fnSession()
        n.update(zone: nil, angle: nil, counts: counts)
        #expect(n.outcome() == .none)
    }

    @Test func outcomeExcludedAlreadyAtEndIsNone() {
        var e = DragSession(id: "x", origin: .excluded, originIndex: 1)
        e.update(zone: .excluded, angle: nil, counts: [.caps: 1, .fn: 3, .excluded: 2])
        #expect(e.target == .slot(.excluded, 1))
        #expect(e.outcome() == .none)
    }

    // MARK: 지정 상자(D-46, Task 1)

    @Test func assignedBoxAppendsAtEndIgnoringAngle() {
        var s = fnSession()
        s.update(zone: .assigned, angle: 0,
                 counts: [.caps: 1, .fn: 3, .excluded: 0, .assigned: 2])
        #expect(s.target == .slot(.assigned, 2))
        var t = fnSession()
        t.update(zone: .assigned, angle: nil,
                 counts: [.caps: 1, .fn: 3, .excluded: 0, .assigned: 2])
        #expect(t.target == .slot(.assigned, 2))
    }

    @Test func fullAssignedBoxRefuses() {
        var s = fnSession()
        s.update(zone: .assigned, angle: 0, counts: [.fn: 3, .assigned: 6])
        #expect(s.target == .refused(.assigned))
    }

    @Test func assignedOwnBoxIsNotRefused() {
        var s = DragSession(id: "r", origin: .assigned, originIndex: 0)
        s.update(zone: .assigned, angle: 0, counts: [.assigned: 6])
        #expect(s.target == .slot(.assigned, 0))
        #expect(s.outcome() == .none)
    }

    @Test func cancelClearsTarget() {
        var s = fnSession()
        s.update(zone: .caps, angle: .pi, counts: counts)
        s.cancel()
        #expect(s.target == .none)
        #expect(s.outcome() == .none)
    }
}

/// ⌥ 끌기 복제와 복제가 든 목록으로 옮기기(2026-11-11).
@Suite struct DragSessionCopyTests {
    @Test func copyIntoOtherListOutcome() {
        var s = DragSession(id: "k", origin: .caps, originIndex: 1, copy: true)
        s.update(zone: .assigned, angle: nil, counts: [.assigned: 1])
        #expect(s.outcome() == .copy("k", .assigned, 1))
        // 원래 목록은 빈 칸 없이 그대로다.
        #expect(s.slots(for: .caps, ids: ["e", "k"]) == ["e", "k"])
    }

    @Test func copyRefusedWhereAlreadyPresentOrOwnOrUnused() {
        var s = DragSession(id: "k", origin: .caps, originIndex: 1, present: [.fn], copy: true)
        s.update(zone: .fn, angle: 0, counts: [.fn: 2])
        #expect(s.target == .refused(.fn))
        s.update(zone: .caps, angle: 0, counts: [.caps: 2])
        #expect(s.outcome() == .none)
        s.update(zone: .excluded, angle: nil, counts: [.excluded: 0])
        #expect(s.outcome() == .none)
    }

    @Test func copyRefusedWhenFull() {
        var s = DragSession(id: "k", origin: .caps, originIndex: 0, copy: true)
        s.update(zone: .assigned, angle: nil, counts: [.assigned: 6])
        #expect(s.target == .refused(.assigned))
    }

    @Test func moveIntoListWithCopyMergesAndHidesExisting() {
        var s = DragSession(id: "k", origin: .caps, originIndex: 1, present: [.assigned])
        s.update(zone: .assigned, angle: nil, counts: [.assigned: 6])
        // 꽉 찼어도 이미 있는 소스라 합치기는 받는다.
        #expect(s.target == .slot(.assigned, 5))
        #expect(s.slots(for: .assigned, ids: ["a", "k"]).count == 2)
        #expect(s.slots(for: .assigned, ids: ["a", "k"]).contains(nil))
        #expect(s.outcome() == .move("k", .assigned, 5))
    }

    @Test func toggleCopyDuringDrag() {
        var s = DragSession(id: "k", origin: .caps, originIndex: 1)
        s.copy = true
        s.update(zone: .assigned, angle: nil, counts: [.assigned: 0])
        #expect(s.outcome() == .copy("k", .assigned, 0))
        s.copy = false
        s.update(zone: .assigned, angle: nil, counts: [.assigned: 0])
        #expect(s.outcome() == .move("k", .assigned, 0))
    }
}
