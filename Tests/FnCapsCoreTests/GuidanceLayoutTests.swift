import Foundation
import Testing
@testable import FnCapsCore

// D-21~D-28, 04.4 D-01~D-06: 언어 수, 중심 언어(D-27), 후보 목록(D-02·D-04·D-05),
// 지금 배치(D-12 「사용 중」) 계산 시험.
// 숫자는 PressReach(=ListSwitcher BFS) 계산값이므로 손으로 쓴 값이 아니다.

private enum GFx {
    static let en = makeSource("com.apple.keylayout.ABC", ["en"])
    static let ko2 = makeSource("com.apple.inputmethod.Korean.2SetKorean", ["ko"])
    static let ko3 = makeSource("org.youknowone.inputmethod.Gureum.han2", ["ko"])
    static let ja = makeSource("com.apple.inputmethod.Kotoeri.RomajiTyping.Japanese", ["ja"])
    static let zh = makeSource("com.apple.inputmethod.SCIM.ITABC", ["zh-Hans"])
    static let ru = makeSource("com.apple.keylayout.Russian", ["ru"])

    static func input(
        sources: [SourceInfo], caps: [String], fn: [String], assigned: [String] = [],
        entry: EntryChoices = EntryChoices(), system: String? = nil
    ) -> GuidanceInput {
        GuidanceInput(sources: sources, caps: caps, fn: fn, assigned: assigned,
                      entry: entry, systemLanguage: system)
    }

    /// 켜짐·선택 가능 여부를 정하는 시험용 소스(D-48).
    static func source(
        _ id: String, _ languages: [String], enabled: Bool = true, selectable: Bool = true
    ) -> SourceInfo {
        SourceInfo(
            id: id, localizedName: id, languages: languages, type: "TISTypeKeyboardLayout",
            bundleID: nil, inputModeID: nil, isSelectCapable: selectable, isEnabled: enabled)
    }
}

@Suite struct GuidanceLayoutTests {
    private static func ready(_ input: GuidanceInput) -> GuidanceLayout.Ready? {
        if case .ready(let ready) = GuidanceLayout.make(input) { return ready }
        return nil
    }

    @Test func singleWhenFewerThanTwoLanguages() {
        #expect(GuidanceLayout.make(GFx.input(sources: [GFx.en], caps: [GFx.en.id], fn: [])) == .single)
        #expect(GuidanceLayout.make(GFx.input(sources: [GFx.ko2], caps: [], fn: [GFx.ko2.id])) == .single)
    }

    @Test func sameLanguageSourcesCountOnce() throws {
        let r = try #require(Self.ready(GFx.input(
            sources: [GFx.en, GFx.ko2, GFx.ko3], caps: [GFx.en.id], fn: [GFx.ko2.id])))
        #expect(r.languageCount == 2)
        #expect(r.english == GFx.en.id)
    }

    @Test func centerFollowsSystemLanguage() throws {
        let sources = [GFx.en, GFx.ko2, GFx.ja]
        let jaSystem = try #require(Self.ready(GFx.input(
            sources: sources, caps: [GFx.en.id], fn: [GFx.ko2.id, GFx.ja.id], system: "ja-JP")))
        #expect(jaSystem.center == GFx.ja.id)

        let enSystem = try #require(Self.ready(GFx.input(
            sources: sources, caps: [GFx.en.id], fn: [GFx.ko2.id, GFx.ja.id], system: "en-US")))
        #expect(enSystem.center == GFx.ko2.id)

        let noFn = try #require(Self.ready(GFx.input(
            sources: sources, caps: [GFx.en.id], fn: [], system: "en-US")))
        #expect(noFn.center == GFx.ko2.id)
    }

    @Test func candidatesForTwoAndThreeLanguages() throws {
        let two = try #require(Self.ready(GFx.input(
            sources: [GFx.en, GFx.ko2], caps: [GFx.en.id], fn: [GFx.ko2.id])))
        #expect(two.candidates.count == 2)
        #expect(two.candidates[0].caps == [GFx.ko2.id, GFx.en.id])
        #expect(two.candidates[0].fn.isEmpty)
        #expect(two.candidates[0].maxPresses == 1)

        // 3개 언어(UAT U-4): ① Caps [영어] + fn [중심, 일] 다음 언어 ② 중심 언어 복제.
        let three = try #require(Self.ready(GFx.input(
            sources: [GFx.en, GFx.ko2, GFx.ja], caps: [GFx.en.id],
            fn: [GFx.ko2.id, GFx.ja.id], system: "en-US")))
        #expect(three.candidates.count == 2)
        #expect(three.candidates[0].caps == [GFx.en.id])
        #expect(three.candidates[0].fn == [GFx.ko2.id, GFx.ja.id])
        #expect(three.candidates[0].assigned.isEmpty)
        #expect(three.candidates[0].maxPresses == 1)
        #expect(three.candidates[1].caps == [GFx.ko2.id, GFx.en.id])
        #expect(three.candidates[1].fn == [GFx.ko2.id, GFx.ja.id])
        #expect(three.candidates[1].assigned.isEmpty)
        #expect(three.candidates[1].maxPresses == 2)

        // 사용자의 진입 언어 선택은 후보 목록을 바꾸지 않는다(D-14).
        let threeLast = try #require(Self.ready(GFx.input(
            sources: [GFx.en, GFx.ko2, GFx.ja], caps: [GFx.en.id],
            fn: [GFx.ko2.id, GFx.ja.id], entry: .both(.last), system: "en-US")))
        #expect(threeLast.candidates == three.candidates)
    }

    @Test func candidatesForFourAndFiveLanguages() throws {
        let four = try #require(Self.ready(GFx.input(
            sources: [GFx.en, GFx.ko2, GFx.ja, GFx.zh], caps: [GFx.en.id],
            fn: [GFx.ko2.id, GFx.ja.id, GFx.zh.id], system: "en-US")))
        #expect(four.candidates.count == 3)
        #expect(four.candidates[0].caps == [GFx.ko2.id, GFx.en.id])
        #expect(four.candidates[0].fn == [GFx.ja.id, GFx.zh.id])
        #expect(four.candidates[0].assigned.isEmpty)
        #expect(four.candidates[0].maxPresses == 2)
        #expect(four.candidates[1].caps == [GFx.en.id])
        #expect(four.candidates[1].fn == [GFx.ko2.id, GFx.ja.id])
        #expect(four.candidates[1].assigned == [GFx.zh.id])
        #expect(four.candidates[1].maxPresses == 2)
        #expect(four.candidates[2].caps == [GFx.en.id])
        #expect(four.candidates[2].fn == [GFx.ko2.id])
        #expect(four.candidates[2].assigned == [GFx.ja.id, GFx.zh.id])
        #expect(four.candidates[2].maxPresses == 1)

        let five = try #require(Self.ready(GFx.input(
            sources: [GFx.en, GFx.ko2, GFx.ja, GFx.zh, GFx.ru], caps: [GFx.en.id],
            fn: [GFx.ko2.id, GFx.ja.id, GFx.zh.id, GFx.ru.id], system: "en-US")))
        #expect(five.candidates.count == 3)
        #expect(five.candidates[0].caps == [GFx.ko2.id, GFx.en.id])
        #expect(five.candidates[0].fn == [GFx.ja.id, GFx.zh.id])
        #expect(five.candidates[0].assigned == [GFx.ru.id])
        #expect(five.candidates[1].caps == [GFx.en.id])
        #expect(five.candidates[1].fn == [GFx.ko2.id, GFx.ja.id])
        #expect(five.candidates[1].assigned == [GFx.zh.id, GFx.ru.id])
        #expect(five.candidates[2].caps == [GFx.en.id])
        #expect(five.candidates[2].fn == [GFx.ko2.id])
        #expect(five.candidates[2].assigned == [GFx.ja.id, GFx.zh.id, GFx.ru.id])
        #expect(five.candidates[2].maxPresses == 1)
    }

    @Test func inUseFollowsUserLists() throws {
        let sources = [GFx.en, GFx.ko2, GFx.ja, GFx.zh]
        let loose = try #require(Self.ready(GFx.input(
            sources: sources, caps: [GFx.en.id],
            fn: [GFx.ko2.id, GFx.ja.id, GFx.zh.id], system: "en-US")))
        #expect(loose.inUse == [false, false, false])

        let exact = try #require(Self.ready(GFx.input(
            sources: sources, caps: [GFx.en.id], fn: [GFx.ko2.id],
            assigned: [GFx.ja.id, GFx.zh.id], system: "en-US")))
        #expect(exact.inUse == [false, false, true])

        // 지정 목록 순서가 달라도 같은 후보다(UAT B1).
        let reordered = try #require(Self.ready(GFx.input(
            sources: sources, caps: [GFx.en.id], fn: [GFx.ko2.id],
            assigned: [GFx.zh.id, GFx.ja.id], system: "en-US")))
        #expect(reordered.inUse == [false, false, true])
    }

    @Test func noEnglishUsesCenterInCapsSlot() throws {
        let r = try #require(Self.ready(GFx.input(
            sources: [GFx.ko2, GFx.ja], caps: [GFx.ko2.id], fn: [GFx.ko2.id, GFx.ja.id],
            system: "ko-KR")))
        #expect(r.languageCount == 2)
        #expect(r.english == nil)
        #expect(r.center == GFx.ko2.id)
        #expect(r.candidates.count == 1)
        #expect(r.candidates[0].caps == [GFx.ko2.id])
        #expect(r.candidates[0].fn == [GFx.ja.id])
        #expect(r.candidates[0].maxPresses == 1)
    }

    @Test func foreignOrderStartsWithCenter() throws {
        let withEnglish = try #require(Self.ready(GFx.input(
            sources: [GFx.en, GFx.ko2, GFx.ja], caps: [GFx.en.id], fn: [GFx.ko2.id, GFx.ja.id])))
        #expect(withEnglish.foreignOrder.first == withEnglish.center)

        let noEnglish = try #require(Self.ready(GFx.input(
            sources: [GFx.ko2, GFx.ja], caps: [GFx.ko2.id], fn: [GFx.ko2.id, GFx.ja.id])))
        #expect(noEnglish.english == nil)
    }

    // MARK: - D-48

    @Test func macOSGlobeListsEnabledSources() throws {
        let disabledKo = GFx.source("org.example.disabled.ko", ["ko"], enabled: false)
        let notSelectableKo = GFx.source("org.example.hidden.ko", ["ko"], selectable: false)
        let r = try #require(Self.ready(GFx.input(
            sources: [GFx.en, disabledKo, GFx.ko2, notSelectableKo, GFx.ja],
            caps: [GFx.en.id], fn: [GFx.ko2.id, GFx.ja.id], system: "ko-KR")))
        #expect(r.macOSGlobe == [GFx.en.id, GFx.ko2.id, GFx.ja.id])
        #expect(r.languageCount == 3)

        let many = try #require(Self.ready(GFx.input(
            sources: [GFx.en, GFx.ko2, GFx.ja, GFx.zh, GFx.ru,
                      GFx.source("org.example.x1", ["x-1"]), GFx.source("org.example.x2", ["x-2"])],
            caps: [GFx.en.id], fn: [GFx.ko2.id], system: "ko-KR")))
        #expect(many.macOSGlobe == [GFx.en.id, GFx.ko2.id, GFx.ja.id, GFx.zh.id, GFx.ru.id,
                                    "org.example.x1"])
    }

    // MARK: - D-14

    /// A2: 후보는 사용자의 특정 언어 진입을 쓰지 않는다(생성기가 D-06 진입을 스스로 넣는다).
    @Test func specificEntryDoesNotChangeCandidates() throws {
        let plain = try #require(Self.ready(GFx.input(
            sources: [GFx.en, GFx.ko2, GFx.ja, GFx.zh], caps: [GFx.en.id],
            fn: [GFx.ko2.id, GFx.ja.id, GFx.zh.id], system: "ko-KR")))
        let specific = try #require(Self.ready(GFx.input(
            sources: [GFx.en, GFx.ko2, GFx.ja, GFx.zh], caps: [GFx.en.id],
            fn: [GFx.ko2.id, GFx.ja.id, GFx.zh.id],
            entry: EntryChoices(caps: .source(GFx.en.id), fn: .source(GFx.ko2.id)),
            system: "ko-KR")))

        #expect(specific.candidates == plain.candidates)
        #expect(specific.inUse == plain.inUse)
    }

    /// 04.3 WR-01(wave 2 검토): 3개 언어에서도 후보 목록은 사용자 진입과 상관없이 같다.
    @Test func specificEntryDoesNotChangeThreeLanguageCandidates() throws {
        let plain = try #require(Self.ready(GFx.input(
            sources: [GFx.en, GFx.ko2, GFx.ja], caps: [GFx.en.id],
            fn: [GFx.ko2.id, GFx.ja.id], system: "ko-KR")))
        let specific = try #require(Self.ready(GFx.input(
            sources: [GFx.en, GFx.ko2, GFx.ja], caps: [GFx.en.id],
            fn: [GFx.ko2.id, GFx.ja.id],
            entry: EntryChoices(caps: .source(GFx.en.id), fn: .source(GFx.ko2.id)),
            system: "ko-KR")))

        #expect(plain.candidates[0].fn == [GFx.ko2.id, GFx.ja.id])
        #expect(plain.candidates[0].assigned.isEmpty)
        #expect(specific.candidates == plain.candidates)
        // 권장 1의 fn 진입이 「다음 언어」라 진입이 같은 쪽만 「사용 중」이다(UAT U-4).
        #expect(plain.inUse[0] == true)
        #expect(specific.inUse[0] == false)
    }

    // MARK: - UAT U-4: n개 국어별 표

    @Test func tableForTwoLanguages() throws {
        let r = try #require(Self.ready(GFx.input(
            sources: [GFx.en, GFx.ko2], caps: [GFx.en.id], fn: [GFx.ko2.id])))
        #expect(r.candidates.map(\.kind) == [.capsOnly, .macOSCaps])
        #expect(r.candidates[0].caps == [GFx.ko2.id, GFx.en.id])
        #expect(r.candidates[0].fn.isEmpty)
        #expect(r.candidates[0].maxPresses == 1)
        #expect(r.candidates[1].caps == [GFx.en.id])
        #expect(r.candidates[1].fn == [GFx.ko2.id])
    }

    /// 3개 국어: ① macOS Caps + fn 2칸 다음 언어(모두 1번) ② 중심 언어 복제(옛 D-52).
    /// 복제 배치의 Caps는 직전 언어와 상관없이 늘 중심 언어로 간다.
    @Test func tableForThreeLanguagesWithDuplicate() throws {
        let input = GFx.input(
            sources: [GFx.en, GFx.ko2, GFx.ja], caps: [GFx.en.id],
            fn: [GFx.ko2.id, GFx.ja.id], system: "ko-KR")
        let r = try #require(Self.ready(input))
        #expect(r.candidates.map(\.kind) == [.macOSCaps, .duplicate])
        #expect(r.candidates[0].fn == [GFx.ko2.id, GFx.ja.id])
        #expect(r.candidates[0].entry.fn == .next)
        #expect(r.candidates[0].maxPresses == 1)
        #expect(r.candidates[0].onePressPercent == 100)

        let dup = r.candidates[1]
        #expect(dup.caps == [GFx.ko2.id, GFx.en.id])
        #expect(dup.fn == [GFx.ko2.id, GFx.ja.id])
        let dupLayout = KeyLayout(
            caps: dup.caps, fn: dup.fn, assigned: dup.assigned,
            sources: input.sources, entry: dup.entry)
        for previous in r.foreignOrder {
            var tracker = ListTracker()
            tracker.setForTesting(current: GFx.en.id, previous: previous,
                                  lastCaps: GFx.en.id, lastFn: previous)
            #expect(ListSwitcher.decide(.caps, current: GFx.en.id, layout: dupLayout,
                                        tracker: tracker) == .switchTo(r.center))
        }
    }

    @Test func noEnglishStillHasCandidatesAndSingleStaysSingle() throws {
        let noEnglish = try #require(Self.ready(GFx.input(
            sources: [GFx.ko2, GFx.ja], caps: [GFx.ko2.id], fn: [GFx.ko2.id, GFx.ja.id])))
        #expect(!noEnglish.candidates.isEmpty)
        #expect(GuidanceLayout.make(GFx.input(
            sources: [GFx.en], caps: [GFx.en.id], fn: [])) == .single)
    }
}
