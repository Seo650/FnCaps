import Foundation
import Testing
@testable import FnCapsCore

@Suite struct KeyLayoutTests {
    /// 복제(2026-11-11): 다른 목록 사이 중복은 목록마다 남는다. key(of:)·list(of:)는 첫 목록이다.
    @Test func duplicateAcrossListsKeptInEachList() {
        let l = ListFx.layout(caps: ["E"], fn: ["E", "K"], rule: .nextAfterLast)
        #expect(l.sources(for: .caps) == ["E"])
        #expect(l.sources(for: .fn) == ["E", "K"])
        #expect(l.lists(of: "E") == [.caps, .fn])
        #expect(l.key(of: "E") == .caps)
        #expect(l.key(of: "K") == .fn)
    }

    @Test func notEnabledIdsIgnoredAndDuplicatesRemoved() {
        let l = ListFx.layout(caps: ["E", "ghost", "E"], fn: ["K", "K", "J"], rule: .last)
        #expect(l.sources(for: .caps) == ["E"])
        #expect(l.sources(for: .fn) == ["K", "J"])
        #expect(l.isListed("E"))
        #expect(!l.isListed("ghost"))
        #expect(!l.isListed("Z"))
        #expect(l.key(of: "Z") == nil)
        #expect(l.entry(for: .caps) == .last && l.entry(for: .fn) == .last)
    }

    @Test func activeFlags() {
        #expect(KeyLayout.empty.hasActiveList == false)
        let capsOnly = ListFx.layout(caps: ["E"], fn: [], rule: .nextAfterLast)
        #expect(capsOnly.capsListActive)
        #expect(!capsOnly.fnListActive)
        #expect(capsOnly.hasActiveList)
        let fnOnly = ListFx.layout(caps: [], fn: ["K"], rule: .nextAfterLast)
        #expect(!fnOnly.capsListActive)
        #expect(fnOnly.fnListActive)
        #expect(fnOnly.hasActiveList)
    }

    @Test func preservesListOrder() {
        let l = ListFx.layout(caps: ["K", "E"], fn: ["Z", "J"], rule: .nextAfterLast)
        #expect(l.sources(for: .caps) == ["K", "E"])
        #expect(l.sources(for: .fn) == ["Z", "J"])
    }

    @Test func outsideRuleDecoding() {
        #expect(OutsideRule.decoded("next") == .nextAfterLast)
        #expect(OutsideRule.decoded("last") == .last)
        #expect(OutsideRule.decoded("nonsense") == .nextAfterLast)
        #expect(OutsideRule.decoded(nil) == .nextAfterLast)
        #expect(OutsideRule.defaultsKey == "outsideRule")
    }
}
