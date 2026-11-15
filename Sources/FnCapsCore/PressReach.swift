import Foundation

/// D-23, D-24: 화면이 보일 「최대 누름 수」와 「1번에 가는 비율」을 실제 전환 규칙으로 계산한다.
/// 옛 `ListSwitcherMetricTests`의 BFS를 제품 코드로 올린 것이다. 손으로 쓴 숫자를 없애기 위해
/// `ListSwitcher.decide`·`decideAssigned`와 `ListTracker.observe`를 그대로 쓴다.
///
/// 화면 계산 전용이다. 탭 콜백 경로에서 부르지 않는다(T-04.2-05: 상태 수는 대상 수의 다항식이지만
/// 콜백의 마이크로초 예산을 지키기 위해 호출처는 도움말 화면 하나뿐이다, 04.2-06).
public enum PressReach {
    public struct Result: Equatable, Sendable {
        /// 도달한 전환의 최대 누름 수(도달한 것이 없으면 0).
        public let maxPresses: Int
        /// 1번에 도달한 비율(%). 분모는 도달 + 불가.
        public let onePressPercent: Int
        /// 끝까지 가지 못한 (상태, 목표) 쌍의 수.
        public let unreachable: Int

        public init(maxPresses: Int, onePressPercent: Int, unreachable: Int) {
            self.maxPresses = maxPresses
            self.onePressPercent = onePressPercent
            self.unreachable = unreachable
        }
    }

    /// 추적기의 값과 같은 모양. `cur`는 항상 있다.
    private struct State: Hashable {
        var cur: SourceID
        var prev: SourceID?
        var lastCaps: SourceID?
        var lastFn: SourceID?
        var lastAssigned: SourceID?
    }

    private static func tracker(_ s: State) -> ListTracker {
        var t = ListTracker()
        t.setForTesting(current: s.cur, previous: s.prev,
                        lastCaps: s.lastCaps, lastFn: s.lastFn, lastAssigned: s.lastAssigned)
        return t
    }

    private static func snapshot(_ t: ListTracker, fallback: State) -> State {
        State(cur: t.current ?? fallback.cur, prev: t.previous,
              lastCaps: t.lastCaps, lastFn: t.lastFn, lastAssigned: t.last(in: .assigned))
    }

    private static func press(_ s: State, _ key: TriggerKey, _ layout: KeyLayout) -> State {
        let t = tracker(s)
        guard case .switchTo(let target) =
            ListSwitcher.decide(key, current: s.cur, layout: layout, tracker: t) else { return s }
        var next = t
        next.observe(selected: target, layout: layout, inFlight: false)
        return snapshot(next, fallback: s)
    }

    private static func pressAssigned(
        _ s: State, _ target: SourceID, _ layout: KeyLayout
    ) -> State {
        guard case .switchTo(let id) =
            ListSwitcher.decideAssigned(target, current: s.cur, layout: layout) else { return s }
        var t = tracker(s)
        t.observe(selected: id, layout: layout, inFlight: false)
        return snapshot(t, fallback: s)
    }

    /// 대상 = caps·fn·assigned 목록 소스의 순서 유지 합집합(중복 제거).
    private static func targets(_ layout: KeyLayout) -> [SourceID] {
        var seen = Set<SourceID>()
        var out: [SourceID] = []
        for list in SourceList.engineLists {
            for id in layout.sources(in: list) where seen.insert(id).inserted { out.append(id) }
        }
        return out
    }

    /// 누를 수 있는 키 한 번: caps, fn, 그리고 지정 목록 소스마다 그 소스로 가는 지정 단축키.
    private static func pressOnce(
        _ s: State, _ layout: KeyLayout, _ assigned: [SourceID]
    ) -> [State] {
        var out = [press(s, .caps, layout), press(s, .fn, layout)]
        for id in assigned { out.append(pressAssigned(s, id, layout)) }
        return out
    }

    public static func measure(_ layout: KeyLayout) -> Result? {
        let langs = targets(layout)
        guard langs.count >= 2 else { return nil }

        // key-list-sim.py reach()와 옛 시험의 시작 상태: 목록별 last는 그 소스가 목록에 있으면
        // 그 소스, 아니면 그 목록 첫 소스(빈 목록이면 nil). prev는 없다.
        let caps = layout.sources(in: .caps)
        let fn = layout.sources(in: .fn)
        let assigned = layout.sources(in: .assigned)
        let start: [State] = langs.map { c in
            State(cur: c, prev: nil,
                  lastCaps: caps.contains(c) ? c : caps.first,
                  lastFn: fn.contains(c) ? c : fn.first,
                  lastAssigned: assigned.contains(c) ? c : assigned.first)
        }

        // 1단계: 시작 상태에서 도달 가능한 상태 전부.
        var seen = Set(start)
        var queue = start
        var i = 0
        while i < queue.count {
            let x = queue[i]
            i += 1
            for y in pressOnce(x, layout, assigned) where !seen.contains(y) {
                seen.insert(y)
                queue.append(y)
            }
        }

        // 2단계: 직전 소스가 있는 상태마다 목표별 최단 거리. 지금 소스는 세지 않는다.
        var counts: [Int: Int] = [:]
        var unreachable = 0
        for s in seen where s.prev != nil {
            var dist: [State: Int] = [s: 0]
            var best: [SourceID: Int] = [s.cur: 0]
            var q = [s]
            var j = 0
            while j < q.count {
                let x = q[j]
                j += 1
                for y in pressOnce(x, layout, assigned) where dist[y] == nil {
                    dist[y] = dist[x]! + 1
                    if best[y.cur] == nil { best[y.cur] = dist[y]! }
                    q.append(y)
                }
            }
            for t in langs where t != s.cur {
                if let d = best[t] { counts[d, default: 0] += 1 } else { unreachable += 1 }
            }
        }

        let total = counts.values.reduce(0, +) + unreachable
        let ones = counts[1] ?? 0
        let pct = total == 0 ? 0 : Int((Double(ones) / Double(total) * 100).rounded())
        return Result(maxPresses: counts.keys.max() ?? 0,
                      onePressPercent: pct, unreachable: unreachable)
    }
}
