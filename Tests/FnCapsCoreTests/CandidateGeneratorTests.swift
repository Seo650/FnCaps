import Foundation
import Testing
@testable import FnCapsCore

// 04.4 D-01~D-06: 후보 생성기 시험. 4개 언어(D-05)와 5개 언어(D-04)의 후보와 순서를 고정한다.
// 최대 누름 수·1번 비율은 손값이 아니라 `PressReach.measure` 결과와 비교한다(D-23).
// 진입 언어를 `.next`로 재면 D-05 순서가 틀어지므로 후보의 `entry`(D-06)를 그대로 넣어 잰다.

private enum CFx {
    static let en = makeSource("com.apple.keylayout.ABC", ["en"])
    static let ko = makeSource("com.apple.inputmethod.Korean.2SetKorean", ["ko"])
    static let ja = makeSource("com.apple.inputmethod.Kotoeri.RomajiTyping.Japanese", ["ja"])
    static let zh = makeSource("com.apple.inputmethod.SCIM.ITABC", ["zh-Hans"])
    static let ru = makeSource("com.apple.keylayout.Russian", ["ru"])

    static func generate(
        _ sources: [SourceInfo], english: SourceID?, foreign: [SourceID]
    ) -> [GuidancePlan] {
        CandidateGenerator.generate(
            english: english, foreign: foreign, sources: sources,
            languageCount: (english == nil ? 0 : 1) + foreign.count)
    }
}

@Suite struct CandidateGeneratorTests {
    /// D-01: 모든 목록은 한 키 상한 안이고, 횟수는 `PressReach` 값과 같고, 불가는 0이다.
    private static func check(_ candidates: [GuidancePlan], sources: [SourceInfo]) throws {
        for plan in candidates {
            #expect(plan.caps.count <= KeyLists.maxPerKey)
            #expect(plan.fn.count <= KeyLists.maxPerKey)
            #expect(plan.assigned.count <= KeyLists.maxPerKey)
            let layout = KeyLayout(
                caps: plan.caps, fn: plan.fn, assigned: plan.assigned,
                sources: sources, entry: plan.entry)
            let measured = try #require(PressReach.measure(layout))
            #expect(plan.maxPresses == measured.maxPresses)
            #expect(plan.onePressPercent == measured.onePressPercent)
            #expect(measured.maxPresses <= 2)
            #expect(measured.unreachable == 0)
        }
    }

    /// UAT U-4: 2개 국어 ① Caps 하나에 두 언어(fn 비움) ② macOS Caps + fn [중심].
    @Test func twoLanguagesTable() throws {
        let sources = [CFx.en, CFx.ko]
        let candidates = CFx.generate(sources, english: CFx.en.id, foreign: [CFx.ko.id])
        try Self.check(candidates, sources: sources)
        #expect(candidates.map(\.kind) == [.capsOnly, .macOSCaps])
        #expect(candidates[0].caps == [CFx.ko.id, CFx.en.id])
        #expect(candidates[0].fn.isEmpty)
        #expect(candidates[0].maxPresses == 1)
        #expect(candidates[1].caps == [CFx.en.id])
        #expect(candidates[1].fn == [CFx.ko.id])
        #expect(candidates[1].entry == EntryChoices(caps: .next, fn: .next))
        #expect(candidates[1].maxPresses == 1)
    }

    /// UAT U-4: 3개 국어 ① macOS Caps + fn [중심, 일] 다음 언어 ② 중심 언어 복제.
    @Test func threeLanguagesTwoCandidates() throws {
        let sources = [CFx.en, CFx.ko, CFx.ja]
        let candidates = CFx.generate(
            sources, english: CFx.en.id, foreign: [CFx.ko.id, CFx.ja.id])
        try Self.check(candidates, sources: sources)
        #expect(candidates.count == 2)

        // ① fn 2칸 다음 언어: 지금 안 쓰는 쪽으로 가서 모든 언어가 1번이다.
        #expect(candidates[0].kind == .macOSCaps)
        #expect(candidates[0].caps == [CFx.en.id])
        #expect(candidates[0].fn == [CFx.ko.id, CFx.ja.id])
        #expect(candidates[0].entry.fn == .next)
        #expect(candidates[0].assigned.isEmpty)
        #expect(candidates[0].maxPresses == 1)

        // ② Caps [중심, 영어] 진입 중심 + fn [중심, 일] 진입 중심(UAT U-6).
        #expect(candidates[1].kind == .duplicate)
        #expect(candidates[1].caps == [CFx.ko.id, CFx.en.id])
        #expect(candidates[1].entry.caps == .source(CFx.ko.id))
        #expect(candidates[1].fn == [CFx.ko.id, CFx.ja.id])
        #expect(candidates[1].entry.fn == .source(CFx.ko.id))
        #expect(candidates[1].maxPresses == 2)
    }

    /// D-05: 4개 언어(A·한·日·中, 중심 한)의 세 후보와 순서.
    @Test func d05FourLanguageOrder() throws {
        let sources = [CFx.en, CFx.ko, CFx.ja, CFx.zh]
        let candidates = CFx.generate(
            sources, english: CFx.en.id,
            foreign: [CFx.ko.id, CFx.ja.id, CFx.zh.id])
        try Self.check(candidates, sources: sources)
        #expect(candidates.count == 3)
        #expect(candidates.map(\.maxPresses) == [2, 2, 1])
        #expect(candidates.map(\.assigned.count) == [0, 1, 2])

        // ① Caps [한, A] 진입 한 + fn [日, 中] 진입 日.
        #expect(candidates[0].caps == [CFx.ko.id, CFx.en.id])
        #expect(candidates[0].entry.caps == .source(CFx.ko.id))
        #expect(candidates[0].fn == [CFx.ja.id, CFx.zh.id])
        #expect(candidates[0].entry.fn == .source(CFx.ja.id))
        #expect(candidates[0].assigned.isEmpty)
        // ② Caps [A] + fn [한, 日] 진입 한 + 지정 [中]. 동률이면 macOS 기본 Caps 쪽(UAT U-3).
        #expect(candidates[1].caps == [CFx.en.id])
        #expect(candidates[1].fn == [CFx.ko.id, CFx.ja.id])
        #expect(candidates[1].entry.fn == .next)
        #expect(candidates[1].assigned == [CFx.zh.id])
        // ③ Caps [A] + fn [한] + 지정 [日, 中].
        #expect(candidates[2].caps == [CFx.en.id])
        #expect(candidates[2].fn == [CFx.ko.id])
        #expect(candidates[2].assigned == [CFx.ja.id, CFx.zh.id])
    }

    /// D-04: 5개 언어(영어 + 4)의 첫 후보와 나머지.
    @Test func d04FiveLanguageOrder() throws {
        let sources = [CFx.en, CFx.ko, CFx.ja, CFx.zh, CFx.ru]
        let candidates = CFx.generate(
            sources, english: CFx.en.id,
            foreign: [CFx.ko.id, CFx.ja.id, CFx.zh.id, CFx.ru.id])
        try Self.check(candidates, sources: sources)
        #expect(candidates.count == 3)

        #expect(candidates[0].caps == [CFx.ko.id, CFx.en.id])
        #expect(candidates[0].fn == [CFx.ja.id, CFx.zh.id])
        #expect(candidates[0].assigned == [CFx.ru.id])

        #expect(candidates[1].caps == [CFx.en.id])
        #expect(candidates[1].fn == [CFx.ko.id, CFx.ja.id])
        #expect(candidates[1].assigned == [CFx.zh.id, CFx.ru.id])

        #expect(candidates[2].caps == [CFx.en.id])
        #expect(candidates[2].fn == [CFx.ko.id])
        #expect(candidates[2].assigned == [CFx.ja.id, CFx.zh.id, CFx.ru.id])
        #expect(candidates[2].maxPresses == 1)
    }

    @Test func noEnglishTwoLanguages() throws {
        let sources = [CFx.ko, CFx.ja]
        let candidates = CFx.generate(sources, english: nil, foreign: [CFx.ko.id, CFx.ja.id])
        try Self.check(candidates, sources: sources)
        #expect(candidates.count == 1)
        #expect(candidates[0].caps == [CFx.ko.id])
        #expect(candidates[0].fn == [CFx.ja.id])
        #expect(candidates[0].maxPresses == 1)
    }

    @Test func noEnglishThreeLanguages() throws {
        let sources = [CFx.ko, CFx.ja, CFx.zh]
        let candidates = CFx.generate(
            sources, english: nil, foreign: [CFx.ko.id, CFx.ja.id, CFx.zh.id])
        try Self.check(candidates, sources: sources)
        #expect(candidates.count == 2)
        #expect(candidates[0].caps == [CFx.ko.id])
        #expect(candidates[0].fn == [CFx.ja.id, CFx.zh.id])
        #expect(candidates[0].entry.fn == .source(CFx.ja.id))
        #expect(candidates[0].maxPresses == 2)
        #expect(candidates[1].caps == [CFx.ko.id])
        #expect(candidates[1].fn == [CFx.ja.id])
        #expect(candidates[1].assigned == [CFx.zh.id])
        #expect(candidates[1].maxPresses == 1)
    }

    /// D-12 「사용 중」 판정: caps·fn은 순서까지, 지정은 집합, 진입은 목록이 2개 이상일 때만 본다.
    @Test func matchesComparesListsAndEffectiveEntry() throws {
        let sources = [CFx.en, CFx.ko, CFx.ja, CFx.zh]
        let candidates = CFx.generate(
            sources, english: CFx.en.id,
            foreign: [CFx.ko.id, CFx.ja.id, CFx.zh.id])
        let first = try #require(candidates.first)

        #expect(first.matches(
            caps: first.caps, fn: first.fn, assigned: [], entry: first.entry))
        // Caps 진입이 다르면 사용 중이 아니다.
        #expect(!first.matches(
            caps: first.caps, fn: first.fn, assigned: [],
            entry: EntryChoices(caps: .next, fn: .source(CFx.ja.id))))

        // 지정 목록은 순서만 달라도 같은 후보다(UAT B1).
        let third = try #require(candidates.last)
        #expect(third.matches(
            caps: third.caps, fn: third.fn,
            assigned: Array(third.assigned.reversed()), entry: third.entry))

        // fn 목록이 1개면 fn 진입은 비교하지 않는다.
        let pair = try #require(CFx.generate(
            [CFx.en, CFx.ko], english: CFx.en.id, foreign: [CFx.ko.id]).last)
        #expect(pair.matches(
            caps: pair.caps, fn: pair.fn, assigned: [],
            entry: EntryChoices(caps: .next, fn: .last)))
    }
}
