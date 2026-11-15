import Foundation
import Testing
@testable import FnCapsCore

/// 입력 소스 복제(todo 2026-11-11 input-source-duplication 결론안).
@Suite struct KeyListsDuplicateTests {
    static let control = KeyChord(keyCode: 18, modifiers: 0x40000)

    @Test func copyAddsWithoutRemoving() {
        let l = KeyLists(caps: ["E", "K"], fn: ["J"], excluded: ["Z"])
        let c = l.copied("K", to: .fn)
        #expect(c.caps == ["E", "K"])
        #expect(c.fn == ["J", "K"])
        #expect(c.lists(of: "K") == [.caps, .fn])
    }

    @Test func copyAtIndex() {
        let l = KeyLists(caps: ["E", "K"], fn: ["J", "C"], excluded: [])
        #expect(l.copied("K", to: .fn, at: 1).fn == ["J", "K", "C"])
    }

    @Test func copyFromUnusedTakesItOutOfUnused() {
        let l = KeyLists(caps: ["E"], fn: [], excluded: ["Z"])
        let c = l.copied("Z", to: .caps)
        #expect(c.caps == ["E", "Z"])
        #expect(c.excluded == [])
    }

    @Test func copyRefusals() {
        let l = KeyLists(caps: ["E", "K"], fn: ["K"], excluded: [])
        #expect(l.copied("K", to: .fn) == l)           // 같은 목록 안 중복 금지
        #expect(l.copied("K", to: .excluded) == l)     // 「사용 안 함」에는 복제하지 않는다
        let full = KeyLists(caps: ["E"], fn: ["1", "2", "3", "4", "5", "6"], excluded: [])
        #expect(full.copied("E", to: .fn) == full)     // 목록마다 6개 상한
    }

    @Test func removeFromOneListKeepsOtherCopy() {
        let l = KeyLists(caps: ["E", "K"], fn: ["K", "J"], excluded: [])
        let r = l.removed("K", from: .caps)
        #expect(r.caps == ["E"])
        #expect(r.fn == ["K", "J"])
        #expect(r.excluded == [])
    }

    @Test func removeLastCopyGoesToUnused() {
        let l = KeyLists(caps: ["E"], fn: ["K"], excluded: ["Z"])
        let r = l.removed("K", from: .fn)
        #expect(r.fn == [])
        #expect(r.excluded == ["Z", "K"])
    }

    @Test func removeFromAssignedClearsChord() {
        let l = KeyLists(caps: [], fn: ["R"], assigned: ["R"], excluded: [], chords: ["R": Self.control])
        let r = l.removed("R", from: .assigned)
        #expect(r.assigned == [])
        #expect(r.fn == ["R"])
        #expect(r.chords == [:])
    }

    @Test func moveOneCopyLeavesOthers() {
        let l = KeyLists(caps: ["E", "K"], fn: ["K"], assigned: [], excluded: [])
        let m = l.moved("K", from: .caps, to: .assigned)
        #expect(m.caps == ["E"])
        #expect(m.fn == ["K"])
        #expect(m.assigned == ["K"])
    }

    @Test func moveIntoListWithCopyMerges() {
        let l = KeyLists(caps: ["E", "K"], fn: ["J", "K", "C"], excluded: [])
        let m = l.moved("K", from: .caps, to: .fn, at: 0)
        #expect(m.caps == ["E"])
        #expect(m.fn == ["K", "J", "C"])
    }

    @Test func moveToUnusedRemovesOnlyThatCopy() {
        let l = KeyLists(caps: ["E", "K"], fn: ["K"], excluded: [])
        let m = l.moved("K", from: .fn, to: .excluded)
        #expect(m.caps == ["E", "K"])
        #expect(m.fn == [])
        #expect(m.excluded == [])
    }

    @Test func moveOutOfAssignedClearsChordButNotWithin() {
        let l = KeyLists(caps: [], fn: [], assigned: ["R", "V"], excluded: [], chords: ["R": Self.control])
        #expect(l.moved("R", from: .assigned, to: .assigned, at: 1).chords == ["R": Self.control])
        #expect(l.moved("R", from: .assigned, to: .fn).chords == [:])
    }

    @Test func moveWithinListReorders() {
        let l = KeyLists(caps: ["E", "K", "J"], fn: [], excluded: [])
        #expect(l.moved("E", from: .caps, to: .caps, at: 2).caps == ["K", "J", "E"])
    }

    @Test func nudgeInGivenList() {
        let l = KeyLists(caps: ["E", "K"], fn: ["J", "K"], excluded: [])
        #expect(l.nudged("K", in: .fn, by: -1).fn == ["K", "J"])
        #expect(l.nudged("K", in: .fn, by: -1).caps == ["E", "K"])
    }

    @Test func reconcileOverflowDoesNotPutDuplicateInUnused() {
        let live = ["1", "2", "3", "4", "5", "6", "7"].map { makeSource($0, ["ja"]) }
        let l = KeyLists(caps: ["7"], fn: ["1", "2", "3", "4", "5", "6", "7"], excluded: [])
        let r = l.reconciled(with: live).lists
        #expect(r.fn.count == 6)
        #expect(r.caps == ["7"])
        #expect(!r.excluded.contains("7"))
    }

    /// 한국어가 Caps·fn·지정에 함께 있을 때 엔진 판정(결론안 예시).
    @Test func engineWithDuplicatedSource() {
        let all = [makeSource("E", ["en"]), makeSource("K", ["ko"]), makeSource("J", ["ja"])]
        let l = KeyLayout(caps: ["E", "K"], fn: ["K", "J"], assigned: ["K"], sources: all, rule: .nextAfterLast)
        var t = ListTracker()
        t.observe(selected: "K", layout: l, inFlight: false)
        #expect(t.last(in: .caps) == "K" && t.last(in: .fn) == "K" && t.last(in: .assigned) == "K")
        #expect(ListSwitcher.decide(.caps, current: "K", layout: l, tracker: t) == .switchTo("E"))
        #expect(ListSwitcher.decide(.fn, current: "K", layout: l, tracker: t) == .switchTo("J"))
        #expect(ListSwitcher.decideAssigned("K", current: "J", layout: l) == .switchTo("K"))
    }
}
