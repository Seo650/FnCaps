import Foundation
import Testing
@testable import FnCapsCore

// 합계 시험 (D-11, D-23): PressReach(제품 코드)로 도달 가능 상태를 BFS해
// 최대 누름 수와 1번에 가는 비율을 RESEARCH §2 표와 맞춘다.
// 전이 표(오라클)와 다른 방식으로 이식 오류를 잡는다. 기대 숫자는 옛 시험 그대로다(회귀).

@Suite struct ListSwitcherMetricTests {
    private static let names = [
        "two_C2", "two_C1F1", "three_1_2", "three_2_1", "four_1_3", "four_2_2", "four_3_1",
    ]

    @Test func nextRuleTable() {
        let maxes = [1, 1, 1, 1, 2, 2, 2]
        let pcts = [100, 100, 100, 100, 67, 67, 67]
        for (i, name) in Self.names.enumerated() {
            let cfg = ListFx.config(name)
            let r = PressReach.measure(ListFx.layout(caps: cfg.caps, fn: cfg.fn, rule: .nextAfterLast))!
            #expect(r.maxPresses == maxes[i], "\(name) next max")
            #expect(r.onePressPercent == pcts[i], "\(name) next pct")
        }
    }

    @Test func lastRuleTable() {
        let maxes = [1, 1, 2, 2, 3, 2, 3]
        let pcts = [100, 100, 83, 83, 56, 67, 56]
        for (i, name) in Self.names.enumerated() {
            let cfg = ListFx.config(name)
            let r = PressReach.measure(ListFx.layout(caps: cfg.caps, fn: cfg.fn, rule: .last))!
            #expect(r.maxPresses == maxes[i], "\(name) last max")
            #expect(r.onePressPercent == pcts[i], "\(name) last pct")
        }
    }
}
