import Testing
@testable import FnCapsCore

func makeSource(_ id: String, _ languages: [String], bundleID: String? = nil) -> SourceInfo {
    SourceInfo(
        id: id, localizedName: id, languages: languages,
        type: "TISTypeKeyboardInputMode", bundleID: bundleID, inputModeID: nil,
        isSelectCapable: true, isEnabled: true)
}

enum Fx {
    static let abc = makeSource("com.apple.keylayout.ABC", ["en", "acf", "af", "zu"])
    static let ko2 = makeSource("com.apple.inputmethod.Korean.2SetKorean", ["ko"])
    static let ja = makeSource("com.apple.inputmethod.Kotoeri.RomajiTyping.Japanese", ["ja"])
    static let gureum = makeSource(
        "org.youknowone.inputmethod.Gureum.han2", ["ko"],
        bundleID: "org.youknowone.inputmethod.Gureum")
    static let zh = makeSource("com.apple.inputmethod.SCIM.ITABC", ["zh-Hans"])
}

@Suite struct SourceClassifierTests {
    @Test func englishByFirstLanguage() {
        #expect(SourceClassifier.role(of: Fx.abc) == .base)
        #expect(SourceClassifier.role(of: makeSource("a", ["en-GB"])) == .base)
        #expect(SourceClassifier.role(of: makeSource("a", ["en_US"])) == .base)
        #expect(SourceClassifier.role(of: makeSource("a", ["EN"])) == .base)
    }

    @Test func foreignSources() {
        #expect(SourceClassifier.role(of: Fx.ko2) == .foreign)
        #expect(SourceClassifier.role(of: Fx.ja) == .foreign)
        #expect(SourceClassifier.role(of: Fx.gureum) == .foreign)
    }

    @Test func firstElementOnly() {
        #expect(SourceClassifier.role(of: makeSource("fr", ["fr", "en"])) == .foreign)
    }

    @Test func emptyLanguagesUnclassified() {
        #expect(SourceClassifier.role(of: makeSource("x", [])) == .unclassified)
        #expect(SourceClassifier.role(of: makeSource("x", [""])) == .unclassified)
    }

    @Test func modeKeys() {
        #expect(SourceClassifier.modeKey(of: makeSource("a", ["ko"])) == "ko")
        #expect(SourceClassifier.modeKey(of: makeSource("a", ["zh-Hans"])) == "zh-Hans")
        #expect(SourceClassifier.modeKey(of: makeSource("a", ["zh_Hant"])) == "zh-Hant")
        #expect(SourceClassifier.modeKey(of: makeSource("a", ["vi"])) == "vi")
        #expect(SourceClassifier.modeKey(of: makeSource("a", ["pt-BR"])) == "pt")
        #expect(SourceClassifier.primaryLanguage(of: makeSource("a", ["zh-Hans"])) == "zh")
    }

    @Test func classifyGroupsKoreanAndGureumIntoOneMode() {
        let c = SourceClassifier.classify([Fx.abc, Fx.ko2, Fx.ja, Fx.gureum])
        #expect(c.base == [Fx.abc.id])
        #expect(c.foreign == [Fx.ko2.id, Fx.ja.id, Fx.gureum.id])
        #expect(c.modes == [
            LanguageMode(key: "ko", sources: [Fx.ko2.id, Fx.gureum.id]),
            LanguageMode(key: "ja", sources: [Fx.ja.id]),
        ])
        #expect(c.modeKey(of: Fx.gureum.id) == "ko")
        #expect(c.mode(forKey: "ja")?.sources == [Fx.ja.id])
        #expect(c.role(of: "unknown.id") == nil)
        #expect(c.role(of: Fx.abc.id) == .base)
        #expect(c.contains(Fx.ja.id))
        #expect(!c.contains("unknown.id"))
    }

    @Test func defaultClassificationTreatsAllEnglishAsBase() {
        let us = makeSource("com.apple.keylayout.US", ["en"])
        let c = SourceClassifier.classify([Fx.abc, us, Fx.ko2, Fx.ja])
        #expect(c.base == [Fx.abc.id, us.id])
        #expect(c.modes.map(\.key) == ["ko", "ja"])
    }
}
