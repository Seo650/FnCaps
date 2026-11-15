import Foundation
import Testing
@testable import FnCapsCore

// D-24, D-23: 옛 합계 시험의 BFS를 제품 함수 PressReach로 올린 뒤의 시험.
// ListFx(E·K·J·Z)에 R(ru)·V(vi)를 더해 지정 단축키 배치까지 센다.
// 기대 값은 key-list-sim.py press_lists()로 계산한 값이다.

@Suite struct PressReachTests {
    private static let R = makeSource("R", ["ru"])
    private static let V = makeSource("V", ["vi"])
    private static let all: [SourceInfo] = ListFx.all + [R, V]

    private static func measure(
        caps: [String], fn: [String], assigned: [String] = [], rule: OutsideRule
    ) -> PressReach.Result? {
        PressReach.measure(
            KeyLayout(caps: caps, fn: fn, assigned: assigned, sources: all, rule: rule))
    }

    private static func measure(
        caps: [String], fn: [String], assigned: [String] = [], entry: EntryChoices
    ) -> PressReach.Result? {
        PressReach.measure(
            KeyLayout(caps: caps, fn: fn, assigned: assigned, sources: all, entry: entry))
    }

    private static let names = [
        "two_C2", "two_C1F1", "three_1_2", "three_2_1", "four_1_3", "four_2_2", "four_3_1",
    ]

    @Test func nextRuleTable() {
        let maxes = [1, 1, 1, 1, 2, 2, 2]
        let pcts = [100, 100, 100, 100, 67, 67, 67]
        for (i, name) in Self.names.enumerated() {
            let cfg = ListFx.config(name)
            let r = Self.measure(caps: cfg.caps, fn: cfg.fn, rule: .nextAfterLast)
            #expect(r?.maxPresses == maxes[i], "\(name) next max")
            #expect(r?.onePressPercent == pcts[i], "\(name) next pct")
            #expect(r?.unreachable == 0, "\(name) next unreachable")
        }
    }

    @Test func lastRuleTable() {
        let maxes = [1, 1, 2, 2, 3, 2, 3]
        let pcts = [100, 100, 83, 83, 56, 67, 56]
        for (i, name) in Self.names.enumerated() {
            let cfg = ListFx.config(name)
            let r = Self.measure(caps: cfg.caps, fn: cfg.fn, rule: .last)
            #expect(r?.maxPresses == maxes[i], "\(name) last max")
            #expect(r?.onePressPercent == pcts[i], "\(name) last pct")
            #expect(r?.unreachable == 0, "\(name) last unreachable")
        }
    }

    /// 지정 단축키가 나머지 언어를 모두 한 번에 덮으면 규칙과 무관하게 최대 1번이다.
    @Test func assignedAllInOnePress() {
        let next = Self.measure(caps: ["E"], fn: ["K"], assigned: ["J", "Z"], rule: .nextAfterLast)
        let last = Self.measure(caps: ["E"], fn: ["K"], assigned: ["J", "Z"], rule: .last)
        #expect(next?.maxPresses == 1)
        #expect(next?.onePressPercent == 100)
        #expect(last?.maxPresses == 1)
        #expect(last?.onePressPercent == 100)
    }

    /// 지정 단축키를 하나만 쓰면 fn 순환 몫이 남아 2번이 필요하다.
    @Test func assignedPartialReach() {
        let next = Self.measure(caps: ["E"], fn: ["K", "J"], assigned: ["Z"], rule: .nextAfterLast)
        let last = Self.measure(caps: ["E"], fn: ["K", "J"], assigned: ["Z"], rule: .last)
        #expect(next?.maxPresses == 2)
        #expect(next?.onePressPercent == 86)
        #expect(last?.maxPresses == 2)
        #expect(last?.onePressPercent == 81)
    }

    @Test func fiveLanguages() {
        let cycle = Self.measure(caps: ["E"], fn: ["K", "J", "Z", "R"], rule: .nextAfterLast)
        let cycleLast = Self.measure(caps: ["E"], fn: ["K", "J", "Z", "R"], rule: .last)
        #expect(cycle?.maxPresses == 3)
        #expect(cycleLast?.maxPresses == 4)
        let split = Self.measure(
            caps: ["E"], fn: ["K", "J"], assigned: ["Z", "R"], rule: .nextAfterLast)
        let splitLast = Self.measure(
            caps: ["E"], fn: ["K", "J"], assigned: ["Z", "R"], rule: .last)
        #expect(split?.maxPresses == 2)
        #expect(splitLast?.maxPresses == 2)
    }

    /// 04.3: caps [E,K] 진입 K + fn [J,Z] 진입 J. 이 구성에서는 진입 언어가 최대 누름 수와
    /// 1번 비율을 바꾸지 않는다(둘 다 값을 그대로 고정한다).
    /// 기대 값은 key-list-sim.py press()를 규칙 딕셔너리 {'C':'K','F':'J'}·{'C':'next','F':'next'}로
    /// 돌린 reach() 계산값이다: entry (최대 2, 67%, 불가 0), next (최대 2, 67%, 불가 0).
    @Test func entryLanguageKeepsPressReach() {
        let entry = Self.measure(caps: ["E", "K"], fn: ["J", "Z"],
                                 entry: EntryChoices(caps: .source("K"), fn: .source("J")))
        let next = Self.measure(caps: ["E", "K"], fn: ["J", "Z"],
                                entry: EntryChoices(caps: .next, fn: .next))
        #expect(entry?.maxPresses == 2)
        #expect(entry?.onePressPercent == 67)
        #expect(entry?.unreachable == 0)
        #expect(next?.maxPresses == 2)
        #expect(next?.onePressPercent == 67)
        #expect(next?.unreachable == 0)
    }

    /// 04.3 WR-01: 진입 언어가 결과를 실제로 바꾸는 구성. caps [E,K,J] 진입 K + fn [Z].
    /// key-list-sim.py reach()에 {'C':'K','F':'next'}를 넣으면 (최대 3, 63%, 불가 0),
    /// .next/.next면 (최대 2, 67%, 불가 0)이다. PressReach가 진입 값을 무시하면 실패한다.
    @Test func entryLanguageChangesPressReach() {
        let entry = Self.measure(caps: ["E", "K", "J"], fn: ["Z"],
                                 entry: EntryChoices(caps: .source("K"), fn: .next))
        let next = Self.measure(caps: ["E", "K", "J"], fn: ["Z"],
                                entry: EntryChoices(caps: .next, fn: .next))
        #expect(entry?.maxPresses == 3)
        #expect(entry?.onePressPercent == 63)
        #expect(entry?.unreachable == 0)
        #expect(next?.maxPresses == 2)
        #expect(next?.onePressPercent == 67)
        #expect(next?.unreachable == 0)
    }

    @Test func fewerThanTwoSourcesIsNil() {
        #expect(Self.measure(caps: ["E"], fn: [], rule: .nextAfterLast) == nil)
        #expect(Self.measure(caps: [], fn: [], assigned: [], rule: .nextAfterLast) == nil)
    }
}
