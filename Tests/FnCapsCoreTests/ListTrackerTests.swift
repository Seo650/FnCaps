import Foundation
import Testing
@testable import FnCapsCore

@Suite struct ListTrackerTests {
    private let layout = ListFx.layout(caps: ["E"], fn: ["K", "J"], rule: .nextAfterLast)

    @Test func observeUpdatesPreviousAndLastPerList() {
        var t = ListTracker()
        t.seed(current: "K", history: [], layout: layout)
        #expect(t.current == "K")
        #expect(t.previous == nil)
        #expect(t.lastFn == "K")
        let r = t.observe(selected: "E", layout: layout, inFlight: false)
        #expect(r)
        #expect(t.previous == "K")
        #expect(t.current == "E")
        #expect(t.lastCaps == "E")
        #expect(t.lastFn == "K")
        #expect(t.last(for: .caps) == "E")
        #expect(t.last(for: .fn) == "K")
    }

    @Test func inFlightIgnored() {
        var t = ListTracker()
        t.seed(current: "K", history: [], layout: layout)
        let before = t
        let r = t.observe(selected: "J", layout: layout, inFlight: true)
        #expect(r == false)
        #expect(t == before)
    }

    @Test func sameSourceIsNotAChange() {
        var t = ListTracker()
        t.seed(current: "K", history: [], layout: layout)
        let r = t.observe(selected: "K", layout: layout, inFlight: false)
        #expect(r == false)
        #expect(t.previous == nil)
    }

    @Test func unlistedSourceKeepsState() {
        var t = ListTracker()
        t.seed(current: "K", history: [], layout: layout)
        t.observe(selected: "E", layout: layout, inFlight: false)
        let before = t
        let r = t.observe(selected: "Z", layout: layout, inFlight: false)
        #expect(r == false)
        #expect(t == before)
    }

    @Test func seedReplaysHistoryOldestFirst() {
        var t = ListTracker()
        // 최신순: J, E, K -> 오래된 K부터 반영, 마지막에 current J
        t.seed(current: "J", history: ["J", "E", "K"], layout: layout)
        #expect(t.current == "J")
        #expect(t.previous == "E")
        #expect(t.lastCaps == "E")
        #expect(t.lastFn == "J")
    }

    @Test func seedClearsOldState() {
        var t = ListTracker()
        t.seed(current: "K", history: [], layout: layout)
        t.observe(selected: "E", layout: layout, inFlight: false)
        t.seed(current: "J", history: [], layout: layout)
        #expect(t.previous == nil)
        #expect(t.lastCaps == nil)
        #expect(t.lastFn == "J")
    }

    @Test func reconcileDropsRemovedSources() {
        var t = ListFx.tracker(current: "K", previous: "E", lastCaps: "E", lastFn: "K")
        let shrunk = ListFx.layout(caps: ["E"], fn: ["J"], rule: .nextAfterLast)
        t.reconcile(layout: shrunk)
        #expect(t.lastFn == nil)
        #expect(t.lastCaps == "E")
        // lastCaps는 Caps 목록에 있어야 남는다
        let moved = ListFx.layout(caps: [], fn: ["E", "J"], rule: .nextAfterLast)
        t.reconcile(layout: moved)
        #expect(t.lastCaps == nil)
    }
}
