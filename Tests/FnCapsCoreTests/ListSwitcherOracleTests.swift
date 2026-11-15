import Foundation
import Testing
@testable import FnCapsCore

// 오라클 전이 표 (D-11, D-12, D-13).
// 아래 `rows`는 key-list-sim.py의 press()에서 gen-oracle.py가 만든 출력을 그대로 붙인 것이다. 손으로 고치지 않는다.
// 생성 스크립트는 개발 저장소에만 있다(공개 저장소에는 없음).
// 열: (구성, 규칙, cur, prev, lastCaps, lastFn, 키, 기대 도착). 글자 E/K/J/Z는 영어/한/일/중 소스 하나씩이다.

/// 오라클·합계·걸음 시험이 같이 쓰는 구성 도구. 소스 ID는 글자 그대로다.
enum ListFx {
    static let E = makeSource("E", ["en"])
    static let K = makeSource("K", ["ko"])
    static let J = makeSource("J", ["ja"])
    static let Z = makeSource("Z", ["zh-Hans"])
    static let all: [SourceInfo] = [E, K, J, Z]

    /// 구성 이름 -> (Caps 목록, fn 목록)
    static let configs: [(name: String, caps: [String], fn: [String])] = [
        (name: "two_C2", caps: ["E", "K"], fn: []),
        (name: "two_C1F1", caps: ["E"], fn: ["K"]),
        (name: "three_1_2", caps: ["E"], fn: ["K", "J"]),
        (name: "three_2_1", caps: ["K", "E"], fn: ["J"]),
        (name: "four_1_3", caps: ["E"], fn: ["K", "J", "Z"]),
        (name: "four_2_2", caps: ["E", "K"], fn: ["J", "Z"]),
        (name: "four_3_1", caps: ["E", "K", "J"], fn: ["Z"]),
    ]

    static func config(_ name: String) -> (caps: [String], fn: [String]) {
        let c = configs.first { $0.name == name }!
        return (c.caps, c.fn)
    }

    static func layout(caps: [String], fn: [String], rule: OutsideRule) -> KeyLayout {
        KeyLayout(caps: caps, fn: fn, sources: all, rule: rule)
    }

    static func rule(_ raw: String) -> OutsideRule { raw == "next" ? .nextAfterLast : .last }

    static func opt(_ s: String) -> SourceID? { s == "None" ? nil : s }

    static func tracker(
        current: SourceID?, previous: SourceID?, lastCaps: SourceID?, lastFn: SourceID?
    ) -> ListTracker {
        var t = ListTracker()
        t.setForTesting(current: current, previous: previous, lastCaps: lastCaps, lastFn: lastFn)
        return t
    }
}

private let rows: [(String, String, String, String, String, String, String, String)] = [
    ("two_C2","next","E","K","E","None","C","K"),
    ("two_C2","next","E","K","E","None","F","E"),
    ("two_C2","next","K","E","K","None","C","E"),
    ("two_C2","next","K","E","K","None","F","K"),
    ("two_C2","last","E","K","E","None","C","K"),
    ("two_C2","last","E","K","E","None","F","E"),
    ("two_C2","last","K","E","K","None","C","E"),
    ("two_C2","last","K","E","K","None","F","K"),
    ("two_C1F1","next","E","K","E","K","C","K"),
    ("two_C1F1","next","E","K","E","K","F","K"),
    ("two_C1F1","next","K","E","E","K","C","E"),
    ("two_C1F1","next","K","E","E","K","F","E"),
    ("two_C1F1","last","E","K","E","K","C","K"),
    ("two_C1F1","last","E","K","E","K","F","K"),
    ("two_C1F1","last","K","E","E","K","C","E"),
    ("two_C1F1","last","K","E","E","K","F","E"),
    ("three_1_2","next","E","J","E","J","C","J"),
    ("three_1_2","next","E","J","E","J","F","K"),
    ("three_1_2","next","E","K","E","K","C","K"),
    ("three_1_2","next","E","K","E","K","F","J"),
    ("three_1_2","next","J","E","E","J","C","E"),
    ("three_1_2","next","J","E","E","J","F","K"),
    ("three_1_2","next","J","K","E","J","C","E"),
    ("three_1_2","next","J","K","E","J","F","K"),
    ("three_1_2","next","K","E","E","K","C","E"),
    ("three_1_2","next","K","E","E","K","F","J"),
    ("three_1_2","next","K","J","E","K","C","E"),
    ("three_1_2","next","K","J","E","K","F","J"),
    ("three_1_2","last","E","J","E","J","C","J"),
    ("three_1_2","last","E","J","E","J","F","J"),
    ("three_1_2","last","E","K","E","K","C","K"),
    ("three_1_2","last","E","K","E","K","F","K"),
    ("three_1_2","last","J","E","E","J","C","E"),
    ("three_1_2","last","J","E","E","J","F","K"),
    ("three_1_2","last","J","K","E","J","C","E"),
    ("three_1_2","last","J","K","E","J","F","K"),
    ("three_1_2","last","K","E","E","K","C","E"),
    ("three_1_2","last","K","E","E","K","F","J"),
    ("three_1_2","last","K","J","E","K","C","E"),
    ("three_1_2","last","K","J","E","K","F","J"),
    ("three_2_1","next","E","J","E","J","C","K"),
    ("three_2_1","next","E","J","E","J","F","J"),
    ("three_2_1","next","E","K","E","J","C","K"),
    ("three_2_1","next","E","K","E","J","F","J"),
    ("three_2_1","next","J","E","E","J","C","K"),
    ("three_2_1","next","J","E","E","J","F","E"),
    ("three_2_1","next","J","K","K","J","C","E"),
    ("three_2_1","next","J","K","K","J","F","K"),
    ("three_2_1","next","K","E","K","J","C","E"),
    ("three_2_1","next","K","E","K","J","F","J"),
    ("three_2_1","next","K","J","K","J","C","E"),
    ("three_2_1","next","K","J","K","J","F","J"),
    ("three_2_1","last","E","J","E","J","C","K"),
    ("three_2_1","last","E","J","E","J","F","J"),
    ("three_2_1","last","E","K","E","J","C","K"),
    ("three_2_1","last","E","K","E","J","F","J"),
    ("three_2_1","last","J","E","E","J","C","E"),
    ("three_2_1","last","J","E","E","J","F","E"),
    ("three_2_1","last","J","K","K","J","C","K"),
    ("three_2_1","last","J","K","K","J","F","K"),
    ("three_2_1","last","K","E","K","J","C","E"),
    ("three_2_1","last","K","E","K","J","F","J"),
    ("three_2_1","last","K","J","K","J","C","E"),
    ("three_2_1","last","K","J","K","J","F","J"),
    ("four_1_3","next","E","J","E","J","C","J"),
    ("four_1_3","next","E","J","E","J","F","Z"),
    ("four_1_3","next","E","K","E","K","C","K"),
    ("four_1_3","next","E","K","E","K","F","J"),
    ("four_1_3","next","E","Z","E","Z","C","Z"),
    ("four_1_3","next","E","Z","E","Z","F","K"),
    ("four_1_3","next","J","E","E","J","C","E"),
    ("four_1_3","next","J","E","E","J","F","Z"),
    ("four_1_3","next","J","K","E","J","C","E"),
    ("four_1_3","next","J","K","E","J","F","Z"),
    ("four_1_3","next","K","E","E","K","C","E"),
    ("four_1_3","next","K","E","E","K","F","J"),
    ("four_1_3","next","K","Z","E","K","C","E"),
    ("four_1_3","next","K","Z","E","K","F","J"),
    ("four_1_3","next","Z","E","E","Z","C","E"),
    ("four_1_3","next","Z","E","E","Z","F","K"),
    ("four_1_3","next","Z","J","E","Z","C","E"),
    ("four_1_3","next","Z","J","E","Z","F","K"),
    ("four_1_3","last","E","J","E","J","C","J"),
    ("four_1_3","last","E","J","E","J","F","J"),
    ("four_1_3","last","E","K","E","K","C","K"),
    ("four_1_3","last","E","K","E","K","F","K"),
    ("four_1_3","last","E","Z","E","Z","C","Z"),
    ("four_1_3","last","E","Z","E","Z","F","Z"),
    ("four_1_3","last","J","E","E","J","C","E"),
    ("four_1_3","last","J","E","E","J","F","Z"),
    ("four_1_3","last","J","K","E","J","C","E"),
    ("four_1_3","last","J","K","E","J","F","Z"),
    ("four_1_3","last","K","E","E","K","C","E"),
    ("four_1_3","last","K","E","E","K","F","J"),
    ("four_1_3","last","K","Z","E","K","C","E"),
    ("four_1_3","last","K","Z","E","K","F","J"),
    ("four_1_3","last","Z","E","E","Z","C","E"),
    ("four_1_3","last","Z","E","E","Z","F","K"),
    ("four_1_3","last","Z","J","E","Z","C","E"),
    ("four_1_3","last","Z","J","E","Z","F","K"),
    ("four_2_2","next","E","J","E","J","C","K"),
    ("four_2_2","next","E","J","E","J","F","Z"),
    ("four_2_2","next","E","K","E","J","C","K"),
    ("four_2_2","next","E","K","E","J","F","Z"),
    ("four_2_2","next","E","K","E","Z","C","K"),
    ("four_2_2","next","E","K","E","Z","F","J"),
    ("four_2_2","next","E","Z","E","Z","C","K"),
    ("four_2_2","next","E","Z","E","Z","F","J"),
    ("four_2_2","next","J","E","E","J","C","K"),
    ("four_2_2","next","J","E","E","J","F","Z"),
    ("four_2_2","next","J","K","K","J","C","E"),
    ("four_2_2","next","J","K","K","J","F","Z"),
    ("four_2_2","next","J","Z","E","J","C","K"),
    ("four_2_2","next","J","Z","E","J","F","Z"),
    ("four_2_2","next","J","Z","K","J","C","E"),
    ("four_2_2","next","J","Z","K","J","F","Z"),
    ("four_2_2","next","K","E","K","J","C","E"),
    ("four_2_2","next","K","E","K","J","F","Z"),
    ("four_2_2","next","K","E","K","Z","C","E"),
    ("four_2_2","next","K","E","K","Z","F","J"),
    ("four_2_2","next","K","J","K","J","C","E"),
    ("four_2_2","next","K","J","K","J","F","Z"),
    ("four_2_2","next","K","Z","K","Z","C","E"),
    ("four_2_2","next","K","Z","K","Z","F","J"),
    ("four_2_2","next","Z","E","E","Z","C","K"),
    ("four_2_2","next","Z","E","E","Z","F","J"),
    ("four_2_2","next","Z","J","E","Z","C","K"),
    ("four_2_2","next","Z","J","E","Z","F","J"),
    ("four_2_2","next","Z","J","K","Z","C","E"),
    ("four_2_2","next","Z","J","K","Z","F","J"),
    ("four_2_2","next","Z","K","K","Z","C","E"),
    ("four_2_2","next","Z","K","K","Z","F","J"),
    ("four_2_2","last","E","J","E","J","C","K"),
    ("four_2_2","last","E","J","E","J","F","J"),
    ("four_2_2","last","E","K","E","J","C","K"),
    ("four_2_2","last","E","K","E","J","F","J"),
    ("four_2_2","last","E","K","E","Z","C","K"),
    ("four_2_2","last","E","K","E","Z","F","Z"),
    ("four_2_2","last","E","Z","E","Z","C","K"),
    ("four_2_2","last","E","Z","E","Z","F","Z"),
    ("four_2_2","last","J","E","E","J","C","E"),
    ("four_2_2","last","J","E","E","J","F","Z"),
    ("four_2_2","last","J","K","K","J","C","K"),
    ("four_2_2","last","J","K","K","J","F","Z"),
    ("four_2_2","last","J","Z","E","J","C","E"),
    ("four_2_2","last","J","Z","E","J","F","Z"),
    ("four_2_2","last","J","Z","K","J","C","K"),
    ("four_2_2","last","J","Z","K","J","F","Z"),
    ("four_2_2","last","K","E","K","J","C","E"),
    ("four_2_2","last","K","E","K","J","F","J"),
    ("four_2_2","last","K","E","K","Z","C","E"),
    ("four_2_2","last","K","E","K","Z","F","Z"),
    ("four_2_2","last","K","J","K","J","C","E"),
    ("four_2_2","last","K","J","K","J","F","J"),
    ("four_2_2","last","K","Z","K","Z","C","E"),
    ("four_2_2","last","K","Z","K","Z","F","Z"),
    ("four_2_2","last","Z","E","E","Z","C","E"),
    ("four_2_2","last","Z","E","E","Z","F","J"),
    ("four_2_2","last","Z","J","E","Z","C","E"),
    ("four_2_2","last","Z","J","E","Z","F","J"),
    ("four_2_2","last","Z","J","K","Z","C","K"),
    ("four_2_2","last","Z","J","K","Z","F","J"),
    ("four_2_2","last","Z","K","K","Z","C","K"),
    ("four_2_2","last","Z","K","K","Z","F","J"),
    ("four_3_1","next","E","J","E","Z","C","K"),
    ("four_3_1","next","E","J","E","Z","F","Z"),
    ("four_3_1","next","E","Z","E","Z","C","K"),
    ("four_3_1","next","E","Z","E","Z","F","Z"),
    ("four_3_1","next","J","K","J","Z","C","E"),
    ("four_3_1","next","J","K","J","Z","F","Z"),
    ("four_3_1","next","J","Z","J","Z","C","E"),
    ("four_3_1","next","J","Z","J","Z","F","Z"),
    ("four_3_1","next","K","E","K","Z","C","J"),
    ("four_3_1","next","K","E","K","Z","F","Z"),
    ("four_3_1","next","K","Z","K","Z","C","J"),
    ("four_3_1","next","K","Z","K","Z","F","Z"),
    ("four_3_1","next","Z","E","E","Z","C","K"),
    ("four_3_1","next","Z","E","E","Z","F","E"),
    ("four_3_1","next","Z","J","J","Z","C","E"),
    ("four_3_1","next","Z","J","J","Z","F","J"),
    ("four_3_1","next","Z","K","K","Z","C","J"),
    ("four_3_1","next","Z","K","K","Z","F","K"),
    ("four_3_1","last","E","J","E","Z","C","K"),
    ("four_3_1","last","E","J","E","Z","F","Z"),
    ("four_3_1","last","E","Z","E","Z","C","K"),
    ("four_3_1","last","E","Z","E","Z","F","Z"),
    ("four_3_1","last","J","K","J","Z","C","E"),
    ("four_3_1","last","J","K","J","Z","F","Z"),
    ("four_3_1","last","J","Z","J","Z","C","E"),
    ("four_3_1","last","J","Z","J","Z","F","Z"),
    ("four_3_1","last","K","E","K","Z","C","J"),
    ("four_3_1","last","K","E","K","Z","F","Z"),
    ("four_3_1","last","K","Z","K","Z","C","J"),
    ("four_3_1","last","K","Z","K","Z","F","Z"),
    ("four_3_1","last","Z","E","E","Z","C","E"),
    ("four_3_1","last","Z","E","E","Z","F","E"),
    ("four_3_1","last","Z","J","J","Z","C","J"),
    ("four_3_1","last","Z","J","J","Z","F","J"),
    ("four_3_1","last","Z","K","K","Z","C","K"),
    ("four_3_1","last","Z","K","K","Z","F","K"),
]

@Suite struct ListSwitcherOracleTests {
    @Test func rowCount() {
        #expect(rows.count == 200)
    }

    @Test func everyRowMatchesOracle() {
        for r in rows {
            let (name, ruleRaw, cur, prev, lc, lf, keyRaw, dest) = r
            let cfg = ListFx.config(name)
            let layout = ListFx.layout(caps: cfg.caps, fn: cfg.fn, rule: ListFx.rule(ruleRaw))
            let tracker = ListFx.tracker(
                current: ListFx.opt(cur), previous: ListFx.opt(prev),
                lastCaps: ListFx.opt(lc), lastFn: ListFx.opt(lf))
            let key: TriggerKey = keyRaw == "C" ? .caps : .fn
            let expected: Decision =
                dest == cur ? (key == .fn ? .passThrough : .noop) : .switchTo(dest)
            let got = ListSwitcher.decide(key, current: cur, layout: layout, tracker: tracker)
            #expect(got == expected, "\(r)")
        }
    }
}
