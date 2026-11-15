import Foundation

// D-09~D-11, 04.4-04: 권장 후보 하나를 「키와 언어」 설정에 한 번에 적용하는 순수 계산.
// SwiftUI·AppKit을 import하지 않는다. 저장·엔진 반영은 AppModel.editLists 한 번이 맡는다(D-09 원자 적용).
//
// - D-09: 후보의 caps·fn·assigned 목록과 두 키의 진입 언어를 그대로 옮긴다.
// - D-10: 새 assigned에 남는 소스의 예전 조합키는 그대로 둔다. 조합키가 없는 소스에 기본 조합키를
//   넣지 않는다(PROJECT D-12, 키 철학).
// - D-11: 후보에 없는 켜진 소스는 「사용 안 함」으로 보낸다. 이미 「사용 안 함」이던 소스는 옮길 것이 없다.

/// 확인 창(04.4-06)이 그릴 두 값.
public struct CandidatePreview: Equatable, Sendable {
    /// D-11: 지금 엔진 목록(caps·fn·assigned)에 있고 켜져 있지만 후보에는 없는 소스 수.
    /// 이미 「사용 안 함」이던 소스와 꺼진 소스는 세지 않는다.
    public let unusedCount: Int
    /// D-10: 후보 assigned 중 조합키가 없어 사용자가 직접 정해야 하는 소스(후보 순서).
    public let emptyChordIDs: [SourceID]

    public init(unusedCount: Int, emptyChordIDs: [SourceID]) {
        self.unusedCount = unusedCount
        self.emptyChordIDs = emptyChordIDs
    }
}

extension KeyLists {
    /// 후보를 이 목록에 적용한 결과. 한 번의 호출로 네 목록·진입 언어가 바뀐다(D-09).
    /// 각 목록은 `maxPerKey`로 자르고(T-04.4-06) 마지막에 `normalized()`를 거친다 —
    /// 목록 안 중복 제거, assigned 밖 조합키 삭제, 목록 밖 진입 언어의 `.next` 정리까지 한 번에 끝난다.
    /// 조합키는 `chords`를 그대로 넘긴다(D-10: 남는 소스의 예전 조합키 유지, 새 소스에 자동 입력 없음).
    public func applying(_ plan: GuidancePlan, live: Set<SourceID>) -> KeyLists {
        var next = self
        let planned = Self.plannedLists(plan, live: live)
        next.caps = planned.caps
        next.fn = planned.fn
        next.assigned = planned.assigned
        next.entry = plan.entry

        let keep = Set(next.caps).union(next.fn).union(next.assigned)
        // 옮길 후보: 기존 「사용 안 함」, 지금 세 목록의 소스, 그리고 목록에 자리가 없던 켜진 소스.
        // Set이라 순서가 없으므로 마지막 묶음만 ID 순으로 정렬해 결과를 결정적으로 만든다.
        var pool: [SourceID] = excluded + caps + fn + assigned
        pool.append(contentsOf: live.subtracting(known).sorted())
        var seen = Set<SourceID>()
        next.excluded = pool.filter { !keep.contains($0) && seen.insert($0).inserted }

        return next.normalized()
    }

    /// 후보가 실제로 만드는 세 목록. `applying`과 `candidatePreview`가 같은 값을 쓴다(WR-03, WR-04).
    /// 확인 창이 열려 있는 동안 꺼진 소스는 거르고(WR-03), 그 뒤 `maxPerKey`로 자른다(WR-04).
    static func plannedLists(_ plan: GuidancePlan, live: Set<SourceID>)
        -> (caps: [SourceID], fn: [SourceID], assigned: [SourceID])
    {
        func fit(_ ids: [SourceID]) -> [SourceID] {
            Array(ids.filter(live.contains).prefix(maxPerKey))
        }
        return (fit(plan.caps), fit(plan.fn), fit(plan.assigned))
    }

    /// 확인 창이 보일 값. 부작용 없는 계산이다.
    public func candidatePreview(_ plan: GuidancePlan, live: Set<SourceID>) -> CandidatePreview {
        let current = Set(caps).union(fn).union(assigned).intersection(live)
        let planned = Self.plannedLists(plan, live: live)
        let kept = Set(planned.caps).union(planned.fn).union(planned.assigned)
        return CandidatePreview(
            unusedCount: current.subtracting(kept).count,
            emptyChordIDs: planned.assigned.filter { chords[$0] == nil })
    }
}
