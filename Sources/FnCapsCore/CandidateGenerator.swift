import Foundation

/// 04.4 D-01~D-06: 도움말 「FnCaps 권장」이 보일 후보를 추천 순서대로 만든다.
/// 순수 로직이다(SwiftUI·AppKit을 import하지 않는다). 횟수는 전부 실제 엔진
/// (`PressReach` = `ListSwitcher` BFS)으로 잰다(D-23, 04.2). 손으로 쓴 숫자가 없다.
///
/// - D-01: 켜 둔 모든 언어가 최대 2번 누름 안에 가고 불가가 0인 배치만 후보로 둔다.
///   2번째는 고정 진입 언어(04.3) 때문에 같은 키를 두 번 누르는 순환이다(D-05 확인).
/// - D-02: 정렬은 지정 단축키 수 → 최대 누름 수 → 모양 A → 1번 비율 순서다.
/// - D-03·D-04: 최대 3개. 3개를 넘으면 「최대 1번」 후보 하나를 마지막 칸에 남긴다.
/// - D-06: 모양 A의 Caps 진입은 중심 언어, fn 진입은 fn 목록 첫 언어다.
public enum CandidateGenerator {
    /// D-04: 후보는 최대 3개다. 언어 2개면 후보가 하나뿐이라 하나만 나온다.
    public static let maxCandidates = 3

    /// 동률에서는 Caps [영어](모양 B, macOS 기본 Caps와 같음)를 남긴다.
    /// 04.4 UAT U-3(2026-11-14 사용자 확정): macOS 기본 Caps(영어 ↔ 직전 언어)를 살린다. D-02 마지막 규칙과 같다.
    public static let shapeAFirstOnTie = false

    /// `foreign`은 [중심] + 나머지 순서다(`GuidanceLayout.foreignOrder` 결과).
    /// 후보가 없으면 빈 배열을 돌려준다(폴백은 `GuidanceLayout`이 한다).
    public static func generate(
        english: SourceID?, foreign: [SourceID], sources: [SourceInfo], languageCount: Int
    ) -> [GuidancePlan] {
        guard let center = foreign.first else { return [] }
        // UAT U-4(2026-11-14 사용자 확정): 영어계 소스가 있으면 n개 국어별 고정 표를 쓴다.
        if let english {
            let fixed = table(english: english, foreign: foreign, sources: sources,
                              languageCount: languageCount)
            if !fixed.isEmpty { return fixed }
        }
        let maxPerKey = KeyLists.maxPerKey
        var found: [Measured] = []

        // 모양 A (D-05·D-06): Caps [중심, 영어], fn은 나머지 접두 k개, 남는 것은 지정 단축키.
        // fn이 비는 경우는 만들지 않는다(연구 A2 — 그 경우 모양 B와 같다).
        if let english, foreign.count >= 2 {
            let caps = [center, english]
            let pool = Array(foreign.dropFirst())
            for k in 1...min(pool.count, maxPerKey) {
                let fn = Array(pool.prefix(k))
                let assigned = Array(pool.dropFirst(k))
                guard assigned.count <= maxPerKey else { continue }
                append(caps: caps, fn: fn, assigned: assigned, center: center, shapeA: true,
                       sources: sources, languageCount: languageCount, into: &found)
            }
        }

        // 모양 B: Caps [영어](영어계 소스가 없으면 [중심]), fn은 나머지 접두 k개(k ≥ 0),
        // 남는 것은 지정 단축키. D-02의 「기본 모델(Caps [영어] 하나 + fn 순환)」 모양이다.
        let caps = english.map { [$0] } ?? [center]
        let pool = english != nil ? foreign : Array(foreign.dropFirst())
        for k in 0...min(pool.count, maxPerKey) {
            let fn = Array(pool.prefix(k))
            let assigned = Array(pool.dropFirst(k))
            guard assigned.count <= maxPerKey else { continue }
            append(caps: caps, fn: fn, assigned: assigned, center: center, shapeA: false,
                   sources: sources, languageCount: languageCount, into: &found)
        }

        // T-04.4-01·02: 상한을 넘는 배치와 키가 죽는 배치는 append가 이미 걸렀다.
        let survivors = dominantOnly(found)
        let merged = mergeTies(survivors)
        let ordered = merged.sorted(by: ranks)
        return cut(ordered).map(\.plan)
    }

    // MARK: - n개 국어별 표 (UAT U-4)

    /// 중심 c, 나머지 o1, o2, …(foreignOrder 순서).
    /// - 2개: ① Caps [c, 영] (fn 비움) ② Caps [영] + fn [c]
    /// - 3개: ① Caps [영] + fn [c, o1] 다음 언어 ② Caps [c, 영] 진입 c + fn [c, o1] 진입 c(복제,
    ///   두 키 모두 중심 언어에서 시작한다 — UAT U-6)
    /// - 4개 이상: ① Caps [c, 영] 진입 c + fn [o1, o2] 진입 o1 + 지정 나머지
    ///   ② Caps [영] + fn [c, o1] 다음 언어 + 지정 나머지 ③ Caps [영] + fn [c] + 지정 나머지
    /// 한 키 상한(maxPerKey)을 넘거나 키가 죽는 후보는 뺀다. 횟수는 PressReach로 잰다.
    static func table(
        english: SourceID, foreign: [SourceID], sources: [SourceInfo], languageCount: Int
    ) -> [GuidancePlan] {
        guard let c = foreign.first else { return [] }
        let o = Array(foreign.dropFirst())
        let next = EntryLanguage.next
        typealias Row = (CandidateKind, [SourceID], [SourceID], [SourceID], EntryChoices)
        var rows: [Row] = []
        switch o.count {
        case 0:
            rows = [
                (.capsOnly, [c, english], [], [], EntryChoices(caps: .source(c), fn: next)),
                (.macOSCaps, [english], [c], [], EntryChoices(caps: next, fn: next)),
            ]
        case 1:
            rows = [
                (.macOSCaps, [english], [c, o[0]], [], EntryChoices(caps: next, fn: next)),
                (.duplicate, [c, english], [c, o[0]], [],
                 EntryChoices(caps: .source(c), fn: .source(c))),
            ]
        default:
            let rest1 = Array(o.dropFirst(2))
            rows = [
                (rest1.isEmpty ? .cycles : .cyclesShortcuts, [c, english], [o[0], o[1]], rest1,
                 EntryChoices(caps: .source(c), fn: .source(o[0]))),
                (.macOSShortcuts, [english], [c, o[0]], Array(o.dropFirst()),
                 EntryChoices(caps: next, fn: next)),
                (.fast, [english], [c], o, EntryChoices(caps: next, fn: next)),
            ]
        }
        let maxPerKey = KeyLists.maxPerKey
        return rows.compactMap { kind, caps, fn, assigned, entry in
            guard caps.count <= maxPerKey, fn.count <= maxPerKey,
                  assigned.count <= maxPerKey else { return nil }
            let layout = KeyLayout(
                caps: caps, fn: fn, assigned: assigned, sources: sources, entry: entry)
            guard let measured = PressReach.measure(layout), measured.unreachable == 0
            else { return nil }
            return GuidancePlan(
                caps: caps, fn: fn, assigned: assigned, entry: entry,
                maxPresses: measured.maxPresses, onePressPercent: measured.onePressPercent,
                languageCount: languageCount, kind: kind)
        }
    }

    // MARK: - 후보 한 개

    private struct Measured {
        var plan: GuidancePlan
        /// 모양 A(Caps [중심, 영어])인지. 동률과 정렬에 쓴다(D-05, 연구 A1).
        var shapeA: Bool
    }

    private struct MetricKey: Hashable {
        var assignedCount: Int
        var maxPresses: Int
        var onePressPercent: Int
    }

    private static func append(
        caps: [SourceID], fn: [SourceID], assigned: [SourceID], center: SourceID,
        shapeA: Bool, sources: [SourceInfo], languageCount: Int, into found: inout [Measured]
    ) {
        // D-06: 모양 A의 Caps 진입은 중심 언어, fn 진입은 fn 목록 첫 언어다(2개 이상일 때).
        let entry = EntryChoices(
            caps: shapeA ? .source(center) : .next,
            fn: fn.count >= 2 ? .source(fn[0]) : .next)
        let layout = KeyLayout(
            caps: caps, fn: fn, assigned: assigned, sources: sources, entry: entry)
        guard let measured = PressReach.measure(layout) else { return }
        // D-01: 최대 2번을 넘거나 키가 죽는 배치는 후보가 아니다.
        guard measured.maxPresses <= 2, measured.unreachable == 0 else { return }
        found.append(Measured(
            plan: GuidancePlan(
                caps: caps, fn: fn, assigned: assigned, entry: entry,
                maxPresses: measured.maxPresses, onePressPercent: measured.onePressPercent,
                languageCount: languageCount),
            shapeA: shapeA))
    }

    // MARK: - 지배 제거·동률 합치기

    /// 지정 수 ≤, 최대 ≤, 1번 비율 ≥이고 셋 중 하나라도 엄격히 나으면 이긴다.
    /// 1번 비율을 넣어야 D-05 ②(최대 2·단축키 1)가 ①(최대 2·단축키 0)에 지지 않는다.
    private static func dominates(_ winner: Measured, _ loser: Measured) -> Bool {
        let a = winner.plan
        let b = loser.plan
        let notWorse = a.assigned.count <= b.assigned.count
            && a.maxPresses <= b.maxPresses
            && a.onePressPercent >= b.onePressPercent
        let strictlyBetter = a.assigned.count < b.assigned.count
            || a.maxPresses < b.maxPresses
            || a.onePressPercent > b.onePressPercent
        return notWorse && strictlyBetter
    }

    private static func dominantOnly(_ candidates: [Measured]) -> [Measured] {
        candidates.enumerated().compactMap { index, candidate in
            let beaten = candidates.enumerated().contains { otherIndex, other in
                otherIndex != index && dominates(other, candidate)
            }
            return beaten ? nil : candidate
        }
    }

    /// 세 지표가 모두 같으면 `shapeAFirstOnTie`에 따라 모양 A(또는 B)를 남긴다.
    /// 같은 모양끼리 동률이면 먼저 열거된 것을 남긴다(연구 Pitfall 2).
    private static func mergeTies(_ candidates: [Measured]) -> [Measured] {
        var groups: [[Measured]] = []
        var keys: [MetricKey] = []
        for candidate in candidates {
            let key = MetricKey(
                assignedCount: candidate.plan.assigned.count,
                maxPresses: candidate.plan.maxPresses,
                onePressPercent: candidate.plan.onePressPercent)
            if let index = keys.firstIndex(of: key) {
                groups[index].append(candidate)
            } else {
                keys.append(key)
                groups.append([candidate])
            }
        }
        return groups.compactMap { group in
            if shapeAFirstOnTie, let shapeA = group.first(where: \.shapeA) { return shapeA }
            if !shapeAFirstOnTie, let shapeB = group.first(where: { !$0.shapeA }) { return shapeB }
            return group.first
        }
    }

    // MARK: - 정렬·컷

    /// D-02: 지정 단축키 적은 순 → 최대 누름 수 작은 순 → 모양 A 먼저 → 1번 비율 큰 순.
    private static func ranks(_ a: Measured, before b: Measured) -> Bool {
        if a.plan.assigned.count != b.plan.assigned.count {
            return a.plan.assigned.count < b.plan.assigned.count
        }
        if a.plan.maxPresses != b.plan.maxPresses {
            return a.plan.maxPresses < b.plan.maxPresses
        }
        if a.shapeA != b.shapeA {
            return shapeAFirstOnTie ? a.shapeA : b.shapeA
        }
        if a.plan.onePressPercent != b.plan.onePressPercent {
            return a.plan.onePressPercent > b.plan.onePressPercent
        }
        return false
    }

    /// D-03·D-04: 3개를 넘으면 「최대 1번 중 지정이 가장 적은」 후보를 마지막 칸에 예약하고
    /// 나머지 순서 앞 2개를 쓴다. 최대 1번 후보가 없으면 앞 3개다.
    private static func cut(_ ordered: [Measured]) -> [Measured] {
        guard ordered.count > maxCandidates else { return ordered }
        var rest = ordered
        let reserved = rest.firstIndex(where: { $0.plan.maxPresses == 1 }).map { rest.remove(at: $0) }
        var result = Array(rest.prefix(maxCandidates - 1))
        if let reserved { result.append(reserved) }
        return result
    }
}
