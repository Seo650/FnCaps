import Foundation
import Testing
@testable import FnCapsCore

@Suite struct KeyListsTests {
    static let us = makeSource("us", ["en"])
    static let none = makeSource("none", [])

    @Test func reconciledAddsNewByRole() {
        let base = KeyLists(caps: [Fx.abc.id], fn: [Fx.ko2.id], excluded: [])
        let r = base.reconciled(with: [Fx.abc, Fx.ko2, Self.us, Fx.ja, Self.none])
        #expect(r.lists.caps == [Fx.abc.id, "us"])
        #expect(r.lists.fn == [Fx.ko2.id, Fx.ja.id])
        #expect(r.lists.excluded == ["none"])
        #expect(r.added == ["us", Fx.ja.id])
    }

    @Test func reconciledKeepsDisabledAndReturnedAreNotAdded() {
        let base = KeyLists(caps: [Fx.abc.id], fn: [Fx.ko2.id, Fx.ja.id], excluded: [])
        let off = base.reconciled(with: [Fx.abc])
        #expect(off.lists.fn == [Fx.ko2.id, Fx.ja.id])
        #expect(off.added.isEmpty)
        let back = off.lists.reconciled(with: [Fx.abc, Fx.ko2, Fx.ja])
        #expect(back.added.isEmpty)
        #expect(back.lists.fn == [Fx.ko2.id, Fx.ja.id])
    }

    @Test func reconciledNoChangeEqualsSelf() {
        let l = KeyLists.initial(for: [Fx.abc, Fx.ko2])
        #expect(l.reconciled(with: [Fx.abc, Fx.ko2]).lists == l)
    }

    /// 같은 목록 안 중복과 빈 ID는 지우고, 다른 목록 사이 복제는 남긴다. 엔진 목록에 있으면 excluded에서 뺀다.
    @Test func normalizedKeepsCrossListDuplicates() {
        let l = KeyLists(caps: ["a", "a", ""], fn: ["a", "b", "b"], excluded: ["b", "c"]).normalized()
        #expect(l.caps == ["a"])
        #expect(l.fn == ["a", "b"])
        #expect(l.excluded == ["c"])
    }

    @Test func movingFollowsOnMoveRule() {
        let l = KeyLists(caps: ["a", "b", "c"], fn: [], excluded: [])
        #expect(l.moving(.caps, fromOffsets: [0], toOffset: 2).caps == ["b", "a", "c"])
        #expect(l.moving(.caps, fromOffsets: [2], toOffset: 0).caps == ["c", "a", "b"])
        #expect(l.moving(.caps, fromOffsets: [0], toOffset: 99).caps == ["b", "c", "a"])
        #expect(l.moving(.caps, fromOffsets: [9], toOffset: 0).caps == ["a", "b", "c"])
    }

    @Test func moved() {
        let l = KeyLists(caps: ["a"], fn: ["b"], excluded: [])
        let m = l.moved("a", to: .fn)
        #expect(m.caps == [] && m.fn == ["b", "a"])
        #expect(l.moved("b", to: .fn) == l)
        #expect(l.moved("new", to: .excluded).excluded == ["new"])
    }

    @Test func nudged() {
        let l = KeyLists(caps: ["a", "b", "c"], fn: [], excluded: [])
        #expect(l.nudged("b", by: -1).caps == ["b", "a", "c"])
        #expect(l.nudged("b", by: 1).caps == ["a", "c", "b"])
        #expect(l.nudged("a", by: -1) == l)
        #expect(l.nudged("c", by: 1) == l)
    }

    @Test func decodeRoundTrip() {
        let l = KeyLists(caps: ["a"], fn: ["b"], excluded: ["c"], names: ["a": "A"])
        #expect(KeyLists.decoded(l.encoded()) == .valid(l))
        #expect(KeyLists.decoded(nil) == .missing)
        #expect(KeyLists.decoded(Data("nope".utf8)) == .corrupt)
    }

    @Test func decodeNormalizesTamperedValue() {
        let t = KeyLists(caps: ["a", "a"], fn: ["a"], excluded: ["a"])
        #expect(KeyLists.decoded(t.encoded()) == .valid(KeyLists(caps: ["a"], fn: ["a"], excluded: [])))
    }

    // MARK: 지정 목록과 조합(D-46, Task 1)

    private static let control = KeyChord(keyCode: 38, modifiers: 0x40000)

    @Test func decodeRoundTripKeepsAssignedAndChords() {
        let l = KeyLists(caps: ["a"], fn: ["b"], assigned: ["r"], excluded: ["c"],
                         names: ["r": "R"], chords: ["r": Self.control])
        #expect(KeyLists.decoded(l.encoded()) == .valid(l))
        // chords JSON은 소스 ID 문자열 키를 쓴다.
        let object = (try? JSONSerialization.jsonObject(with: l.encoded()!)) as? [String: Any]
        let chords = object?["chords"] as? [String: Any]
        #expect(chords?["r"] != nil)
    }

    @Test func keyChordKeepsOnlyModifierBits() {
        // ⌃ 0x40000, ⌥ 0x80000만 남고 ⇪ 0x10000, 숫자패드 0x800000은 지운다.
        let c = KeyChord(keyCode: 38, modifiers: 0x40000 | 0x80000 | 0x10000 | 0x800000)
        #expect(c.keyCode == 38)
        #expect(c.modifiers == 0x40000 | 0x80000)
    }

    @Test func keyChordDecodeAlsoNormalizes() {
        // 8454144 = ⇪ 0x10000 + 숫자패드 0x800000
        let raw = Data(#"{"keyCode":38,"modifiers":8454144}"#.utf8)
        guard let c = try? JSONDecoder().decode(KeyChord.self, from: raw) else {
            Issue.record("KeyChord decode failed")
            return
        }
        #expect(c.keyCode == 38)
        #expect(c.modifiers == 0)
    }

    @Test func normalizedKeepsChordOfDuplicatedAssignedSource() {
        let l = KeyLists(caps: [], fn: ["r"], assigned: ["r"], excluded: [],
                         chords: ["r": Self.control]).normalized()
        #expect(l.fn == ["r"])
        #expect(l.assigned == ["r"])
        #expect(l.chords == ["r": Self.control])
    }

    @Test func normalizedDropsChordWhenSourceLeavesAssigned() {
        let l = KeyLists(caps: [], fn: ["r"], assigned: [], excluded: [],
                         chords: ["r": Self.control]).normalized()
        #expect(l.fn == ["r"])
        #expect(l.chords == [:])
    }

    @Test func normalizedDropsChordOfUnknownSource() {
        let l = KeyLists(caps: [], fn: [], assigned: ["r"], excluded: [],
                         chords: ["gone": Self.control]).normalized()
        #expect(l.assigned == ["r"])
        #expect(l.chords == [:])
    }

    @Test func normalizedKeepsFirstSourceForSharedChord() {
        let l = KeyLists(caps: [], fn: [], assigned: ["r", "v"], excluded: [],
                         chords: ["r": Self.control, "v": Self.control]).normalized()
        #expect(l.assigned == ["r", "v"])
        #expect(l.chords == ["r": Self.control])
    }

    @Test func normalizedPriorityPutsAssignedBeforeExcluded() {
        let l = KeyLists(caps: ["a"], fn: [], assigned: ["a", "r"], excluded: ["r"]).normalized()
        #expect(l.caps == ["a"])
        #expect(l.assigned == ["a", "r"])
        #expect(l.excluded == [])
    }

    @Test func reconciledKnowsAssignedAndDoesNotReaddIt() {
        let r = makeSource("r", ["ru"])
        let base = KeyLists(caps: ["e"], fn: ["k"], assigned: ["r"], excluded: [])
        let out = base.reconciled(with: [makeSource("e", ["en"]), makeSource("k", ["ko"]), r])
        #expect(out.added.isEmpty)
        #expect(out.lists.fn == ["k"])
        #expect(out.lists.assigned == ["r"])
    }

    @Test func reconciledAssignedOverflowMovesToExcludedAndDropsChord() {
        let ids = ["r1", "r2", "r3", "r4", "r5", "r6", "r7"]
        let langs = ["ru", "vi", "el", "th", "fr", "de", "es"]
        let sources = ids.enumerated().map { makeSource($0.element, [langs[$0.offset]]) }
        let base = KeyLists(caps: [], fn: [], assigned: ids, excluded: [],
                            chords: ["r7": Self.control])
        let out = base.reconciled(with: sources)
        #expect(out.lists.assigned == Array(ids.prefix(6)))
        #expect(out.lists.excluded == ["r7"])
        #expect(out.lists.chords == [:])
        #expect(out.added == ["r7"])
    }

    @Test func reconciledNewSourceNeverGoesToAssigned() {
        let base = KeyLists(caps: [], fn: [], assigned: [], excluded: [])
        let out = base.reconciled(with: [makeSource("r", ["ru"])])
        #expect(out.lists.assigned == [])
        #expect(out.lists.fn == ["r"])
        #expect(out.added == ["r"])
    }

    @Test func movedIntoAssignedLeavesFn() {
        let l = KeyLists(caps: [], fn: ["k", "r"], excluded: [])
        let m = l.moved("r", to: .assigned)
        #expect(m.fn == ["k"])
        #expect(m.assigned == ["r"])
    }

    @Test func movedIntoFullAssignedIsRefused() {
        let six = ["r1", "r2", "r3", "r4", "r5", "r6"]
        let l = KeyLists(caps: ["e"], fn: [], assigned: six, excluded: [])
        #expect(l.moved("e", to: .assigned, live: Set(six + ["e"])) == l)
        #expect(l.moved("e", to: .assigned, at: 0, live: Set(six + ["e"])) == l)
    }

    @Test func movedOutOfAssignedDropsChord() {
        let l = KeyLists(caps: [], fn: [], assigned: ["r"], excluded: [],
                         chords: ["r": Self.control])
        let toCaps = l.moved("r", to: .caps)
        #expect(toCaps.assigned == [])
        #expect(toCaps.caps == ["r"])
        #expect(toCaps.chords == [:])
        let toFnAt = l.moved("r", to: .fn, at: 0)
        #expect(toFnAt.fn == ["r"])
        #expect(toFnAt.chords == [:])
    }

    @Test func reorderInsideAssignedKeepsChord() {
        let l = KeyLists(caps: [], fn: [], assigned: ["r", "v"], excluded: [],
                         chords: ["r": Self.control])
        #expect(l.moved("r", to: .assigned, at: 1).assigned == ["v", "r"])
        #expect(l.moved("r", to: .assigned, at: 1).chords == ["r": Self.control])
        #expect(l.moving(.assigned, fromOffsets: [0], toOffset: 2).chords == ["r": Self.control])
        #expect(l.nudged("r", by: 1).chords == ["r": Self.control])
    }

    @Test func settingChordRequiresAssignedSource() {
        let l = KeyLists(caps: [], fn: ["k"], excluded: [])
        #expect(l.settingChord(Self.control, for: "k") == l)
        #expect(l.settingChord(Self.control, for: "ghost") == l)
    }

    @Test func settingChordStealsFromOtherAssignedSource() {
        let other = KeyChord(keyCode: 5, modifiers: 0x80000)
        let l = KeyLists(caps: [], fn: [], assigned: ["r", "v"], excluded: [],
                         chords: ["v": Self.control])
        #expect(l.chordOwner(of: Self.control, excluding: "r") == "v")
        let m = l.settingChord(Self.control, for: "r")
        #expect(m.chords == ["r": Self.control])
        #expect(m.settingChord(nil, for: "r").chords == [:])
        #expect(l.settingChord(other, for: "v").chords == ["v": other])
    }

    @Test func chordTableKeepsOnlyLiveAssignedWithChord() {
        let off = KeyChord(keyCode: 3, modifiers: 0x20000)
        let l = KeyLists(caps: [], fn: [], assigned: ["r", "v", "off"], excluded: [],
                         chords: ["r": Self.control, "off": off])
        #expect(l.chordTable(live: ["r", "v", "off"]) == [Self.control: "r", off: "off"])
        #expect(l.chordTable(live: ["r", "v"]) == [Self.control: "r"])
        #expect(l.chordTable(live: ["v"]).isEmpty)
    }
}
