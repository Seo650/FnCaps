import Foundation
import Testing
@testable import FnCapsCore

@Suite struct KeyListsMigrationTests {
    static let us = makeSource("com.apple.keylayout.US", ["en"])
    static let none = makeSource("x.nolang", [])
    static let all = [Fx.abc, Fx.ko2, Fx.ja, Fx.zh]

    @Test func thisMacActualValues() {
        let l = KeyLists.migrated(
            sources: Self.all, legacyCapsSourceID: nil, legacyFnModeKeys: ["ko", "ja", "zh-Hans", "en"])
        #expect(l.caps == [Fx.abc.id])
        #expect(l.fn == [Fx.ko2.id, Fx.ja.id, Fx.zh.id])
        #expect(l.excluded == [])
    }

    @Test func missingModesFollowCatalogOrder() {
        let l = KeyLists.migrated(sources: Self.all, legacyCapsSourceID: nil, legacyFnModeKeys: ["ja", "ko"])
        #expect(l.fn == [Fx.ja.id, Fx.ko2.id, Fx.zh.id])
    }

    @Test func legacyCapsSource() {
        let l = KeyLists.migrated(sources: Self.all, legacyCapsSourceID: Fx.ja.id, legacyFnModeKeys: nil)
        #expect(l.caps == [Fx.ja.id])
        #expect(l.fn.contains(Fx.abc.id))
        #expect(!l.fn.contains(Fx.ja.id))
    }

    @Test func unknownLegacyCapsFallsBackToDefault() {
        let a = KeyLists.migrated(sources: Self.all, legacyCapsSourceID: "gone", legacyFnModeKeys: nil)
        #expect(a == KeyLists.migrated(sources: Self.all, legacyCapsSourceID: nil, legacyFnModeKeys: nil))
    }

    /// 04.5 UAT: 새 설치는 fn 끝에 영어를 하나 더 둬 macOS 🌐 순환과 같은 모양이 된다.
    @Test func initialDuplicatesEnglishAtEndOfFn() {
        let l = KeyLists.initial(for: [Fx.abc, Fx.ko2, Fx.ja])
        #expect(l.caps == [Fx.abc.id])
        #expect(l.fn == [Fx.ko2.id, Fx.ja.id, Fx.abc.id])
    }

    /// 05-11 UAT B5: 새 설치(옛 설정 없음)는 initial을 쓴다. 권장 1과 겹치지 않는다.
    @Test func firstWithoutLegacyIsInitial() {
        let srcs = [Fx.abc, Fx.ko2, Fx.ja]
        let l = KeyLists.first(sources: srcs, legacyCapsSourceID: nil, legacyFnModeKeys: nil)
        #expect(l == KeyLists.initial(for: srcs))
        #expect(l.fn == [Fx.ko2.id, Fx.ja.id, Fx.abc.id])
    }

    @Test func firstWithLegacyIsMigrated() {
        let srcs = [Fx.abc, Fx.ko2, Fx.ja]
        let l = KeyLists.first(sources: srcs, legacyCapsSourceID: Fx.abc.id, legacyFnModeKeys: nil)
        #expect(l == KeyLists.migrated(sources: srcs, legacyCapsSourceID: Fx.abc.id, legacyFnModeKeys: nil))
    }

    @Test func initialWithoutForeignDoesNotDuplicate() {
        let l = KeyLists.initial(for: [Fx.abc])
        #expect(l.fn == [])
    }

    @Test func twoEnglishSourcesBothInCaps() {
        let l = KeyLists.initial(for: [Fx.abc, Self.us, Fx.ko2])
        #expect(l.caps == [Fx.abc.id, Self.us.id])
    }

    @Test func noLanguageIsExcluded() {
        let l = KeyLists.initial(for: [Fx.abc, Self.none])
        #expect(l.excluded == [Self.none.id])
    }

    /// T-04-62: 지정 목록·조합 키가 없던 옛 저장값이 깨짐이 아니라 그대로 읽힌다
    /// (04-RESEARCH-SHORTCUTS §6-2 실험: 합성 디코더는 기본값이 있어도 keyNotFound로 실패한다).
    @Test func oldJSONWithoutAssignedStillReads() {
        let old = Data(#"{"caps":["E"],"fn":["K","J"],"excluded":["U"],"names":{"E":"ABC"}}"#.utf8)
        guard case .valid(let l) = KeyLists.decoded(old) else {
            Issue.record("옛 JSON이 .valid로 읽히지 않는다")
            return
        }
        #expect(l.caps == ["E"])
        #expect(l.fn == ["K", "J"])
        #expect(l.excluded == ["U"])
        #expect(l.names == ["E": "ABC"])
        #expect(l.assigned == [])
        #expect(l.chords == [:])
    }

    @Test func migratedAndInitialStartWithEmptyAssigned() {
        let l = KeyLists.migrated(
            sources: Self.all, legacyCapsSourceID: nil, legacyFnModeKeys: nil)
        #expect(l.assigned == [])
        #expect(l.chords == [:])
        let i = KeyLists.initial(for: Self.all)
        #expect(i.assigned == [])
        #expect(i.chords == [:])
    }
}
