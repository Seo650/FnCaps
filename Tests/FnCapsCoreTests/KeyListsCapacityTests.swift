import Foundation
import Testing
@testable import FnCapsCore

private func src(_ id: String, _ languages: [String]) -> SourceInfo {
    SourceInfo(
        id: id, localizedName: id, languages: languages,
        type: "TISTypeKeyboardInputMode", bundleID: nil, inputModeID: nil,
        isSelectCapable: true, isEnabled: true)
}

private func en(_ id: String) -> SourceInfo { src(id, ["en"]) }

/// 외국어 소스. 서로 다른 언어 코드를 쓰면 언어 모드가 겹치지 않는다.
private let foreignLangs = ["ko", "ja", "de", "fr", "es", "it", "ru", "el", "th", "vi"]
private func foreign(_ id: String, _ n: Int) -> SourceInfo { src(id, [foreignLangs[n % foreignLangs.count]]) }

private func sameLists(_ a: KeyLists, _ b: KeyLists) -> Bool {
    a.caps == b.caps && a.fn == b.fn && a.excluded == b.excluded
}

/// D-30(한 키 최대 6개), M1(꽉 차면 사용 안 함으로), M2(꺼진 소스 자리 기억), R4(다시 켜짐 넘침).
@Suite struct KeyListsCapacityTests {
    static let six = ["f1", "f2", "f3", "f4", "f5", "f6"]

    @Test func maxPerKeyIsSix() {
        #expect(KeyLists.maxPerKey == 6)
    }

    @Test func isFullWithoutLiveCountsAll() {
        let l = KeyLists(caps: Self.six, fn: ["a"], excluded: Self.six.map { "x" + $0 } + ["y"])
        #expect(l.isFull(.caps))
        #expect(!l.isFull(.fn))
        #expect(!l.isFull(.excluded))
    }

    @Test func isFullWithLiveCountsOnlyLive() {
        let l = KeyLists(caps: Self.six, fn: [], excluded: [])
        #expect(!l.isFull(.caps, live: Set(Self.six.dropFirst())))
        #expect(l.isFull(.caps, live: Set(Self.six)))
        #expect(!l.isFull(.excluded, live: Set(Self.six)))
    }

    @Test func movedIntoFullListIsRefused() {
        let l = KeyLists(caps: ["x"], fn: Self.six, excluded: ["y"])
        let live = Set(Self.six + ["x", "y"])
        #expect(l.moved("x", to: .fn, live: live) == l)
        #expect(l.moved("y", to: .fn, live: live) == l)
        #expect(l.moved("f1", to: .fn, live: live) == l)
    }

    @Test func fullCountIgnoresDisabled() {
        let l = KeyLists(caps: ["x"], fn: Self.six, excluded: [])
        let live = Set(Self.six.dropFirst() + ["x"])
        #expect(!l.isFull(.fn, live: live))
        let m = l.moved("x", to: .fn, live: live)
        #expect(m.fn == Self.six + ["x"])
        #expect(m.caps.isEmpty)
    }

    @Test func movedAtIndexClamps() {
        let l = KeyLists(caps: ["x"], fn: ["a", "b"], excluded: [])
        #expect(l.moved("x", to: .fn, at: 1, live: nil).fn == ["a", "x", "b"])
        #expect(l.moved("x", to: .fn, at: -3, live: nil).fn == ["x", "a", "b"])
        #expect(l.moved("x", to: .fn, at: 99, live: nil).fn == ["a", "b", "x"])
        #expect(l.moved("x", to: .fn, at: 1, live: nil).caps.isEmpty)
    }

    @Test func movedAtIndexWithinSameList() {
        let l = KeyLists(caps: [], fn: ["a", "x", "b", "c"], excluded: [])
        #expect(l.moved("x", to: .fn, at: 2).fn == ["a", "b", "x", "c"])
    }

    @Test func movedAtIndexInFullListSameListAllowedOtherRefused() {
        let full = KeyLists(caps: ["y"], fn: ["f1", "f2", "f3", "f4", "f5", "x"], excluded: [])
        let live = Set(full.known)
        #expect(full.moved("x", to: .fn, at: 0, live: live).fn == ["x", "f1", "f2", "f3", "f4", "f5"])
        #expect(full.moved("y", to: .fn, at: 0, live: live) == full)
    }

    @Test func movedAtVisibleIndexSkipsHidden() {
        let l = KeyLists(caps: [], fn: ["a", "h", "b"], excluded: ["x"])
        let live: Set<SourceID> = ["a", "b", "x"]
        #expect(l.moved("x", to: .fn, at: 1, live: live).fn == ["a", "h", "x", "b"])
        #expect(l.moved("x", to: .fn, at: 2, live: live).fn == ["a", "h", "b", "x"])
        #expect(l.moved("x", to: .fn, at: 0, live: live).fn == ["x", "a", "h", "b"])
    }

    @Test func movedAtVisibleIndexNoVisibleAppendsToEnd() {
        let l = KeyLists(caps: [], fn: ["h1", "h2"], excluded: ["x"])
        #expect(l.moved("x", to: .fn, at: 0, live: ["x"]).fn == ["h1", "h2", "x"])
    }

    @Test func movedToExcludedAtLargeIndexAppends() {
        let l = KeyLists(caps: ["x"], fn: [], excluded: ["e1", "e2"])
        #expect(l.moved("x", to: .excluded, at: 99, live: ["x", "e1", "e2"]).excluded == ["e1", "e2", "x"])
    }

    @Test func movedUnknownIdIsInserted() {
        let l = KeyLists(caps: [], fn: ["a"], excluded: [])
        #expect(l.moved("new", to: .fn, at: 0).fn == ["new", "a"])
    }

    @Test func reconciledNewForeignIntoFullFnGoesExcluded() {
        let fns = (0..<6).map { foreign("f\($0)", $0) }
        let base = KeyLists(caps: ["abc"], fn: fns.map(\.id), excluded: [])
        let newOne = foreign("new", 7)
        let r = base.reconciled(with: [en("abc")] + fns + [newOne])
        #expect(r.lists.fn == fns.map(\.id))
        #expect(r.lists.excluded == ["new"])
        #expect(r.added == ["new"])
    }

    @Test func reconciledNewBaseIntoFullCapsGoesExcluded() {
        let caps = (0..<6).map { en("e\($0)") }
        let base = KeyLists(caps: caps.map(\.id), fn: [], excluded: [])
        let r = base.reconciled(with: caps + [en("e6")])
        #expect(r.lists.caps == caps.map(\.id))
        #expect(r.lists.excluded == ["e6"])
        #expect(r.added == ["e6"])
    }

    @Test func reconciledNotFullKeepsOldRule() {
        let base = KeyLists(caps: ["abc"], fn: ["k"], excluded: [])
        let r = base.reconciled(with: [en("abc"), foreign("k", 0), foreign("j", 1), en("us"), src("none", [])])
        #expect(r.lists.caps == ["abc", "us"])
        #expect(r.lists.fn == ["k", "j"])
        #expect(r.lists.excluded == ["none"])
        #expect(r.added == ["j", "us"])
    }

    @Test func reconciledTwoNewWithFiveFillsThenExcludes() {
        let fns = (0..<5).map { foreign("f\($0)", $0) }
        let base = KeyLists(caps: [], fn: fns.map(\.id), excluded: [])
        let r = base.reconciled(with: fns + [foreign("n1", 6), foreign("n2", 7)])
        #expect(r.lists.fn == fns.map(\.id) + ["n1"])
        #expect(r.lists.excluded == ["n2"])
        #expect(r.added == ["n1", "n2"])
    }

    @Test func reconciledKeepsDisabledSlotAndRestoresIt() {
        let a = foreign("a", 0), h = foreign("h", 1), b = foreign("b", 2)
        let base = KeyLists(caps: [], fn: ["a", "h", "b"], excluded: [])
        let off = base.reconciled(with: [a, b])
        #expect(off.lists.fn == ["a", "h", "b"])
        #expect(off.added.isEmpty)
        let back = off.lists.reconciled(with: [a, h, b])
        #expect(back.lists.fn == ["a", "h", "b"])
        #expect(back.added.isEmpty)
    }

    @Test func reconciledReenabledOverflowPushesLastLiveToExcluded() {
        let ids = ["a", "h", "b", "c", "d", "e", "f"]
        let all = ids.enumerated().map { foreign($0.element, $0.offset) }
        let base = KeyLists(caps: [], fn: ids, excluded: ["z"])
        let r = base.reconciled(with: all + [src("z", [])])
        #expect(r.lists.fn == ["a", "h", "b", "c", "d", "e"])
        #expect(r.lists.excluded == ["z", "f"])
        #expect(r.added == ["f"])
    }

    @Test func migratedCapsForeignAtSix() {
        let fns = (0..<8).map { foreign("f\($0)", $0) }
        let l = KeyLists.migrated(sources: [en("abc")] + fns, legacyCapsSourceID: nil, legacyFnModeKeys: nil)
        #expect(l.fn == Array(fns.prefix(6).map(\.id)))
        #expect(l.excluded == ["f6", "f7"])
        #expect(l.caps == ["abc"])
    }

    @Test func migratedLegacyCapsPathAlsoCaps() {
        let fns = (0..<8).map { foreign("f\($0)", $0) }
        let l = KeyLists.migrated(sources: [en("abc")] + fns, legacyCapsSourceID: "f0", legacyFnModeKeys: nil)
        #expect(l.caps == ["f0"])
        #expect(l.fn.count == 6)
        #expect(l.fn == ["abc", "f1", "f2", "f3", "f4", "f5"])
        #expect(l.excluded == ["f6", "f7"])
    }

    @Test func migratedCapsOverflowBeforeFnOverflow() {
        let caps = (0..<7).map { en("e\($0)") }
        let fns = (0..<7).map { foreign("f\($0)", $0) }
        let l = KeyLists.migrated(sources: caps + fns + [src("none", [])], legacyCapsSourceID: nil, legacyFnModeKeys: nil)
        #expect(l.caps.count == 6 && l.fn.count == 6)
        #expect(l.excluded == ["none", "e6", "f6"])
    }

    @Test func normalizedDoesNotCap() {
        let seven = (0..<7).map { "f\($0)" }
        #expect(KeyLists(caps: [], fn: seven, excluded: []).normalized().fn == seven)
    }

    @Test func storedSevenWithOneDisabledStaysAndReconcileAddsNothing() {
        let ids = ["a", "h", "b", "c", "d", "e", "f"]
        let stored = KeyLists(caps: [], fn: ids, excluded: [])
        guard case .valid(let decoded) = KeyLists.decoded(stored.encoded()) else {
            Issue.record("decode failed"); return
        }
        #expect(decoded.fn == ids)
        let live = ids.enumerated().filter { $0.element != "h" }.map { foreign($0.element, $0.offset) }
        let r = decoded.reconciled(with: live)
        #expect(sameLists(r.lists, decoded))
        #expect(r.added.isEmpty)
    }

    @Test func storedSevenAllLiveOverflowsOnReconcile() {
        let ids = (0..<7).map { "f\($0)" }
        let stored = KeyLists(caps: [], fn: ids, excluded: [])
        guard case .valid(let decoded) = KeyLists.decoded(stored.encoded()) else {
            Issue.record("decode failed"); return
        }
        #expect(decoded.fn == ids)
        let r = decoded.reconciled(with: ids.enumerated().map { foreign($0.element, $0.offset) })
        #expect(r.lists.fn == Array(ids.prefix(6)))
        #expect(r.lists.excluded == ["f6"])
        #expect(r.added == ["f6"])
    }
}
