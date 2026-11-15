import Foundation
import Testing
@testable import FnCapsCore

// 걸음 시험 (D-06~D-10, D-25): 누름을 한 번씩 따라가며 사용자가 확인한 흐름과 경계를 본다.

private final class Walk {
    var layout: KeyLayout
    var tracker = ListTracker()

    init(layout: KeyLayout, current: SourceID) {
        self.layout = layout
        tracker.seed(current: current, history: [], layout: layout)
    }

    /// 판단 뒤 .switchTo면 도착을 사용자 선택으로 반영한다.
    @discardableResult
    func press(_ key: TriggerKey) -> Decision {
        let d = ListSwitcher.decide(key, current: tracker.current!, layout: layout, tracker: tracker)
        if case .switchTo(let t) = d {
            tracker.observe(selected: t, layout: layout, inFlight: false)
        }
        return d
    }
}

private enum S {
    static let abc = makeSource("com.apple.keylayout.ABC", ["en"])
    static let us = makeSource("com.apple.keylayout.US", ["en"])
    static let ko2 = makeSource("com.apple.inputmethod.Korean.2SetKorean", ["ko"])
    static let gureum = makeSource("org.youknowone.inputmethod.Gureum.han2", ["ko"])
    static let ja = makeSource("com.apple.inputmethod.Kotoeri.RomajiTyping.Japanese", ["ja"])
    static let x = makeSource("com.example.excluded", ["fr"])
    static let all = [abc, us, ko2, gureum, ja, x]

    static func layout(caps: [SourceInfo], fn: [SourceInfo], rule: OutsideRule = .nextAfterLast) -> KeyLayout {
        KeyLayout(caps: caps.map(\.id), fn: fn.map(\.id), sources: all, rule: rule)
    }
}

@Suite struct ListSwitcherWalkTests {
    @Test func defaultFlowKoreanCapsEnglishFnJapanese() {
        let w = Walk(layout: S.layout(caps: [S.abc], fn: [S.ko2, S.ja]), current: S.ko2.id)
        #expect(w.press(.caps) == .switchTo(S.abc.id))
        #expect(w.press(.fn) == .switchTo(S.ja.id))
        #expect(w.press(.caps) == .switchTo(S.abc.id))
        #expect(w.press(.caps) == .switchTo(S.ja.id))   // 목록 1개: 직전
    }

    @Test func fourLanguagesTwoPlusTwo() {
        let ids = ["E", "K", "J", "Z"]
        let t = ListFx.tracker(current: "J", previous: "K", lastCaps: "K", lastFn: "J")
        let next = ListFx.layout(caps: ["E", "K"], fn: ["J", "Z"], rule: .nextAfterLast)
        let last = ListFx.layout(caps: ["E", "K"], fn: ["J", "Z"], rule: .last)
        #expect(ids.count == 4)
        #expect(ListSwitcher.decide(.caps, current: "J", layout: next, tracker: t) == .switchTo("E"))
        #expect(ListSwitcher.decide(.caps, current: "J", layout: last, tracker: t) == .switchTo("K"))
        #expect(ListSwitcher.decide(.fn, current: "J", layout: next, tracker: t) == .switchTo("Z"))
        #expect(ListSwitcher.decide(.fn, current: "J", layout: last, tracker: t) == .switchTo("Z"))
    }

    @Test func twoEnglishSourcesInCapsCycleInOrder() {
        // D-25: 한 칸은 입력 소스 하나다.
        let w = Walk(layout: S.layout(caps: [S.abc, S.us], fn: [S.ko2, S.ja]), current: S.abc.id)
        #expect(w.press(.caps) == .switchTo(S.us.id))
        #expect(w.press(.caps) == .switchTo(S.abc.id))
    }

    @Test func twoKoreanSourcesInFnCycleInOrder() {
        let w = Walk(layout: S.layout(caps: [S.abc], fn: [S.ko2, S.gureum, S.ja]), current: S.ko2.id)
        #expect(w.press(.fn) == .switchTo(S.gureum.id))
        #expect(w.press(.fn) == .switchTo(S.ja.id))
        #expect(w.press(.fn) == .switchTo(S.ko2.id))
    }

    @Test func excludedSourceNeverReachedAndKeepsPrevious() {
        let layout = S.layout(caps: [S.abc], fn: [S.ko2, S.ja])
        let w = Walk(layout: layout, current: S.ja.id)
        w.press(.caps)   // ABC, previous = ja
        let before = w.tracker
        let r = w.tracker.observe(selected: S.x.id, layout: layout, inFlight: false)
        #expect(r == false)
        #expect(w.tracker == before)
        // 제외된 소스에서 눌러도 결과가 그 소스가 되지 않는다
        let d = ListSwitcher.decide(.caps, current: S.x.id, layout: layout, tracker: w.tracker)
        #expect(d == .switchTo(S.abc.id))
        let f = ListSwitcher.decide(.fn, current: S.x.id, layout: layout, tracker: w.tracker)
        #expect(f != .switchTo(S.x.id))
    }

    @Test func sameLanguageInBothListsIsPerSource() {
        let w = Walk(layout: S.layout(caps: [S.abc], fn: [S.us]), current: S.us.id)
        #expect(w.press(.caps) == .switchTo(S.abc.id))
        #expect(w.press(.fn) == .switchTo(S.us.id))
        #expect(w.press(.caps) == .switchTo(S.abc.id))
    }

    @Test func disabledSourceDroppedFromList() {
        let layout = KeyLayout(
            caps: [S.abc.id, "disabled.source"], fn: [S.ko2.id], sources: S.all, rule: .nextAfterLast)
        #expect(layout.sources(for: .caps) == [S.abc.id])
        #expect(layout.sources(for: .fn) == [S.ko2.id])
    }

    @Test func singleItemNoPreviousFallsBackToOtherListOrNoMove() {
        let layout = S.layout(caps: [S.abc], fn: [S.ko2, S.ja])
        // 다른 목록의 마지막
        let t1 = ListFx.tracker(current: S.abc.id, previous: nil, lastCaps: S.abc.id, lastFn: S.ja.id)
        #expect(ListSwitcher.decide(.caps, current: S.abc.id, layout: layout, tracker: t1) == .switchTo(S.ja.id))
        // 그것도 없으면 그 목록의 첫 소스
        let t2 = ListFx.tracker(current: S.abc.id, previous: nil, lastCaps: S.abc.id, lastFn: nil)
        #expect(ListSwitcher.decide(.caps, current: S.abc.id, layout: layout, tracker: t2) == .switchTo(S.ko2.id))
        // 다른 목록이 비면 움직이지 않는다
        let only = S.layout(caps: [S.abc], fn: [])
        #expect(ListSwitcher.decide(.caps, current: S.abc.id, layout: only, tracker: t2) == .noop)
    }

    @Test func emptyListsAreSafe() {
        let onlyFn = S.layout(caps: [], fn: [S.ko2])
        let t = ListFx.tracker(current: S.ko2.id, previous: nil, lastCaps: nil, lastFn: S.ko2.id)
        #expect(ListSwitcher.decide(.caps, current: S.ko2.id, layout: onlyFn, tracker: t) == .noop)
        #expect(ListSwitcher.decide(.fn, current: S.ko2.id, layout: onlyFn, tracker: t) == .passThrough)
        let none = KeyLayout.empty
        #expect(ListSwitcher.decide(.fn, current: "a", layout: none, tracker: ListTracker()) == .passThrough)
        #expect(ListSwitcher.decide(.caps, current: "a", layout: none, tracker: ListTracker()) == .noop)
    }

    @Test func outsideRuleLastReturnsToLastUsed() {
        let layout = S.layout(caps: [S.abc], fn: [S.ko2, S.ja, S.gureum], rule: .last)
        let w = Walk(layout: layout, current: S.ja.id)
        w.press(.caps)   // ABC
        #expect(w.press(.fn) == .switchTo(S.ja.id))
    }
}
