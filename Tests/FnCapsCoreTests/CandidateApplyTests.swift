import Foundation
import Testing
@testable import FnCapsCore

// D-09~D-11, 04.4-04: 권장 후보를 「키와 언어」 설정에 한 번에 적용하는 순수 계산을 시험한다.
//
// 규칙 셋:
// - D-09: caps·fn·assigned 목록과 두 키의 진입 언어가 후보 값이 된다(원자 적용은 AppModel의 몫).
// - D-10: 새 assigned에 남는 소스의 예전 조합키는 그대로, 조합키 없는 소스에는 아무것도 넣지 않는다.
// - D-11: 후보에 없는(그리고 켜져 있는) 소스만 「사용 안 함」으로 간다. 이미 「사용 안 함」이던 소스는
//   확인 창의 「N개」에 세지 않는다.

private enum CFx {
    static let e = "com.apple.keylayout.ABC"
    static let ko = "com.apple.inputmethod.Korean.2SetKorean"
    // 같은 언어(한국어)의 두 번째 배열: 후보에 없으면 「사용 안 함」으로 간다.
    static let ko2 = "com.apple.inputmethod.Korean.3SetKorean"
    static let ja = "com.apple.inputmethod.Kotoeri.RomajiTyping.Japanese"
    static let zh = "com.apple.inputmethod.SCIM.ITABC"

    static func plan(
        caps: [SourceID], fn: [SourceID], assigned: [SourceID] = [],
        entry: EntryChoices = EntryChoices()
    ) -> GuidancePlan {
        GuidancePlan(
            caps: caps, fn: fn, assigned: assigned, entry: entry,
            maxPresses: 1, onePressPercent: 100, languageCount: 3)
    }

    static let chordC = KeyChord(keyCode: 38, modifiers: 0x40000)
}

@Suite struct CandidateApplyTests {
    // MARK: - D-09: 목록과 진입 언어가 후보 값이 된다

    @Test func applyingCopiesListsAndEntry() {
        let live: Set<SourceID> = [CFx.e, CFx.ko, CFx.ja, CFx.zh]
        let base = KeyLists(caps: [CFx.e], fn: [CFx.ko, CFx.ja, CFx.zh], excluded: [])
        let plan = CFx.plan(
            caps: [CFx.ko, CFx.e], fn: [CFx.ja, CFx.zh],
            entry: EntryChoices(caps: .source(CFx.ko), fn: .source(CFx.ja)))

        let result = base.applying(plan, live: live)

        #expect(result.caps == [CFx.ko, CFx.e])
        #expect(result.fn == [CFx.ja, CFx.zh])
        #expect(result.assigned == [])
        #expect(result.entry == EntryChoices(caps: .source(CFx.ko), fn: .source(CFx.ja)))
        #expect(result.excluded == [])
    }

    // MARK: - D-11: 후보에 없는 소스만 「사용 안 함」

    @Test func unusedCandidateSourceGoesToExcluded() {
        let live: Set<SourceID> = [CFx.e, CFx.ko, CFx.ko2, CFx.ja]
        let base = KeyLists(caps: [CFx.e], fn: [CFx.ko, CFx.ko2, CFx.ja], excluded: [])
        let plan = CFx.plan(caps: [CFx.e], fn: [CFx.ko, CFx.ja])

        let result = base.applying(plan, live: live)
        let preview = base.candidatePreview(plan, live: live)

        #expect(result.excluded == [CFx.ko2])
        #expect(preview.unusedCount == 1)
    }

    @Test func alreadyExcludedSourceIsNotCounted() {
        let live: Set<SourceID> = [CFx.e, CFx.ko, CFx.ko2, CFx.ja]
        let base = KeyLists(
            caps: [CFx.e], fn: [CFx.ko, CFx.ja], excluded: [CFx.ko2])
        let plan = CFx.plan(caps: [CFx.e], fn: [CFx.ko, CFx.ja])

        let result = base.applying(plan, live: live)

        #expect(result.excluded == [CFx.ko2])
        #expect(base.candidatePreview(plan, live: live).unusedCount == 0)
    }

    /// 시스템에서 끈(켜져 있지 않은) 소스는 확인 창 개수에 세지 않지만, 목록에는 남기지 않는다.
    @Test func disabledSourceIsNotCountedButLeavesLists() {
        let live: Set<SourceID> = [CFx.e, CFx.ja]
        let base = KeyLists(
            caps: [CFx.e, CFx.ko], fn: [CFx.ja], excluded: [])
        let plan = CFx.plan(caps: [CFx.e], fn: [CFx.ja])

        let result = base.applying(plan, live: live)

        #expect(result.caps == [CFx.e])
        #expect(result.excluded == [CFx.ko])
        #expect(base.candidatePreview(plan, live: live).unusedCount == 0)
    }

    // MARK: - D-10: 조합키는 그대로, 새로 넣지 않는다

    @Test func keepsExistingChordAndLeavesOthersEmpty() {
        let live: Set<SourceID> = [CFx.e, CFx.ja, CFx.zh]
        let base = KeyLists(
            caps: [CFx.e], fn: [CFx.ja], assigned: [CFx.zh], excluded: [],
            chords: [CFx.zh: CFx.chordC])
        let plan = CFx.plan(caps: [CFx.e], fn: [], assigned: [CFx.ja, CFx.zh])

        let result = base.applying(plan, live: live)
        let preview = base.candidatePreview(plan, live: live)

        #expect(result.chords[CFx.zh] == CFx.chordC)
        #expect(result.chords[CFx.ja] == nil)
        #expect(preview.emptyChordIDs == [CFx.ja])
    }

    @Test func chordOfSourceLeavingAssignedIsDropped() {
        let live: Set<SourceID> = [CFx.e, CFx.ja, CFx.zh]
        let base = KeyLists(
            caps: [CFx.e], fn: [CFx.zh], assigned: [CFx.ja], excluded: [],
            chords: [CFx.ja: CFx.chordC])
        let plan = CFx.plan(caps: [CFx.e], fn: [], assigned: [])

        let result = base.applying(plan, live: live)

        #expect(result.assigned == [])
        #expect(result.chords.isEmpty)
        #expect(base.candidatePreview(plan, live: live).emptyChordIDs.isEmpty)
    }

    // MARK: - T-04.4-06: 상한(D-30)

    @Test func applyingCapsListsAtMaxPerKey() {
        let ids = ["a", "b", "c", "d", "e", "f", "g"]
        let live = Set<SourceID>(ids)
        let base = KeyLists(caps: [ids[0]], fn: [], excluded: [])
        let plan = GuidancePlan(
            caps: ids, fn: ids, assigned: ids, entry: EntryChoices(),
            maxPresses: 1, languageCount: 7)

        let result = base.applying(plan, live: live)

        #expect(result.caps.count == KeyLists.maxPerKey)
        #expect(result.fn.count == KeyLists.maxPerKey)
        #expect(result.assigned.count == KeyLists.maxPerKey)
        #expect(result.caps == Array(ids.prefix(KeyLists.maxPerKey)))
    }

    // MARK: - 진입 언어는 목록 밖으로 나가면 .next(D-08)

    @Test func entryPointingOutsideCandidateListFallsBackToNext() {
        let live: Set<SourceID> = [CFx.e, CFx.ko, CFx.ja]
        let base = KeyLists(caps: [CFx.e], fn: [CFx.ko, CFx.ja], excluded: [])
        let plan = CFx.plan(
            caps: [CFx.e], fn: [CFx.ko, CFx.ja],
            entry: EntryChoices(caps: .source(CFx.ko), fn: .next))

        let result = base.applying(plan, live: live)

        #expect(result.entry.caps == .next)
        #expect(result.entry.fn == .next)
    }

    // MARK: - 멱등

    @Test func applyingTwiceEqualsOnce() {
        let live: Set<SourceID> = [CFx.e, CFx.ko, CFx.ko2, CFx.ja, CFx.zh]
        let base = KeyLists(
            caps: [CFx.e], fn: [CFx.ko, CFx.ko2, CFx.ja], assigned: [CFx.zh],
            excluded: [], chords: [CFx.zh: CFx.chordC])
        let plan = CFx.plan(
            caps: [CFx.ko, CFx.e], fn: [CFx.ja], assigned: [CFx.zh],
            entry: EntryChoices(caps: .source(CFx.ko), fn: .source(CFx.ja)))

        let once = base.applying(plan, live: live)
        let twice = once.applying(plan, live: live)

        #expect(twice == once)
    }

    // MARK: - WR-03: 확인 창이 열린 사이 꺼진 소스는 목록에 넣지 않는다

    @Test func staleSourceInPlanIsNotApplied() {
        // ja는 계획에 있지만 이제 켜져 있지 않다.
        let live: Set<SourceID> = [CFx.e, CFx.ko]
        let base = KeyLists(caps: [CFx.e], fn: [CFx.ko], excluded: [])
        let plan = CFx.plan(caps: [CFx.e], fn: [CFx.ko, CFx.ja], assigned: [CFx.ja])

        let result = base.applying(plan, live: live)
        let preview = base.candidatePreview(plan, live: live)

        #expect(result.fn == [CFx.ko])
        #expect(result.assigned == [])
        #expect(preview.emptyChordIDs.isEmpty)
    }

    @Test func staleSourceDoesNotTakeSlotTowardMax() {
        let six = ["a", "b", "c", "d", "e", "f"]
        let live = Set<SourceID>(six)
        let ids = ["dead"] + six  // 7개 중 맨 앞이 꺼진 소스
        let base = KeyLists(caps: [six[0]], fn: [], excluded: [])
        let plan = GuidancePlan(
            caps: ids, fn: [], assigned: [], entry: EntryChoices(),
            maxPresses: 1, languageCount: 6)

        let result = base.applying(plan, live: live)

        #expect(result.caps == six)
    }

    // MARK: - WR-04: 확인 창의 「사용 안 함」 수는 실제 결과와 같다

    @Test func previewCountsSourcesDroppedByTruncation() {
        let ids = ["a", "b", "c", "d", "e", "f", "g"]
        let live = Set<SourceID>(ids)
        let base = KeyLists(caps: ids, fn: [], excluded: [])
        let plan = GuidancePlan(
            caps: ids, fn: [], assigned: [], entry: EntryChoices(),
            maxPresses: 1, languageCount: 7)

        let result = base.applying(plan, live: live)
        let preview = base.candidatePreview(plan, live: live)

        #expect(result.caps.count == KeyLists.maxPerKey)
        #expect(preview.unusedCount == ids.count - KeyLists.maxPerKey)
        #expect(Set(result.excluded) == Set(ids.suffix(ids.count - KeyLists.maxPerKey)))
    }
}
