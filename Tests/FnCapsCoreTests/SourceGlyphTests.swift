import Testing
@testable import FnCapsCore

@Suite struct SourceGlyphTests {
    private func g(_ id: String, _ languages: [String], _ name: String = "") -> String {
        SourceGlyph.text(id: id, languages: languages, name: name)
    }

    @Test func abc() {
        #expect(g("com.apple.keylayout.ABC", ["en"], "ABC") == "A")
    }

    @Test func koreanAndJapanese() {
        #expect(g("com.apple.inputmethod.Korean.2SetKorean", ["ko"]) == "한")
        #expect(g("com.apple.inputmethod.Kotoeri.RomajiTyping.Japanese", ["ja"]) == "あ")
        #expect(g("com.apple.inputmethod.Kotoeri.RomajiTyping.Japanese.Katakana", ["ja"]) == "ア")
    }

    @Test func chineseByID() {
        #expect(g("com.apple.inputmethod.SCIM.ITABC", ["zh-Hans"]) == "拼")
        #expect(g("com.apple.inputmethod.TCIM.Zhuyin", ["zh-Hant"]) == "注")
        #expect(g("com.apple.inputmethod.TCIM.Cangjie", ["zh-Hant"]) == "倉")
        #expect(g("com.apple.inputmethod.SCIM.Wubi", ["zh-Hans"]) == "五")
    }

    @Test func layoutsByID() {
        #expect(g("com.apple.keylayout.UnicodeHexInput", ["en"]) == "U+")
        #expect(g("com.apple.keylayout.Dvorak", ["en"]) == "Dv")
    }

    @Test func chineseByLanguageOnly() {
        #expect(g("x.zh1", ["zh-Hans"]) == "简")
        #expect(g("x.zh2", ["zh-Hant"]) == "繁")
    }

    @Test func otherScriptsByLanguage() {
        #expect(g("x.vi", ["vi"]) == "Vi")
        #expect(g("x.hi", ["hi"]) == "हि")
        #expect(g("x.ar", ["ar"]) == "ع")
        #expect(g("x.he", ["he"]) == "א")
        #expect(g("x.ru", ["ru"]) == "РУ")
        #expect(g("x.el", ["el"]) == "Ω")
        #expect(g("x.th", ["th"]) == "ก")
    }

    @Test func regionTailFallsBackToLanguagePart() {
        #expect(g("x.ko", ["ko-KR"]) == "한")
        #expect(g("x.en", ["en-US"]) == "A")
    }

    @Test func latinTwoLetters() {
        #expect(g("com.apple.keylayout.German", ["de"]) == "DE")
        #expect(g("com.apple.keylayout.French", ["fr"]) == "FR")
    }

    /// 「키와 언어」 타일 배지 글자를 macOS 메뉴 막대 입력 메뉴 아이콘과 맞춘다(D-12~D-14).
    /// 근거: 04.1-UAT.md UAT-A (사용자 스크린숏, 2026-11-12).
    @Test func representativeSourcesMatchMenuBar() {
        // uk·ru는 키릴 대문자 두 글자, fr·es·de는 라틴 대문자 두 글자.
        #expect(g("com.apple.keylayout.ABC", ["en"]) == "A")
        #expect(g("com.apple.inputmethod.Korean.2SetKorean", ["ko"]) == "한")
        #expect(g("com.apple.inputmethod.Kotoeri.RomajiTyping.Japanese", ["ja"]) == "あ")
        #expect(g("com.apple.inputmethod.SCIM.ITABC", ["zh-Hans"]) == "拼")
        #expect(g("com.apple.inputmethod.TCIM.Zhuyin", ["zh-Hant"]) == "注")
        #expect(g("com.apple.keylayout.Ukrainian", ["uk"]) == "УК")
        #expect(g("com.apple.keylayout.Russian", ["ru"]) == "РУ")
        #expect(g("com.apple.keylayout.French", ["fr"]) == "FR")
        #expect(g("com.apple.keylayout.Spanish", ["es"]) == "ES")
        #expect(g("com.apple.keylayout.German", ["de"]) == "DE")
    }

    /// 같은 언어의 다른 배열은 대표 소스와 같은 글자다(언어 표로 묶인다).
    @Test func sameLanguageLayoutsShareGlyph() {
        #expect(g("com.apple.keylayout.Ukrainian-PC", ["uk"]) == "УК")
        #expect(g("com.apple.keylayout.RussianWin", ["ru"]) == "РУ")
        #expect(g("com.apple.keylayout.French-PC", ["fr"]) == "FR")
        #expect(g("com.apple.keylayout.Spanish-ISO", ["es"]) == "ES")
    }

    /// ABC-AZERTY·ABC-QWERTZ는 언어가 fr·de라 ABC의 `A`가 번지지 않는다(RESEARCH Pitfall 6).
    @Test func abcVariantsFollowTheirOwnLanguage() {
        #expect(g("com.apple.keylayout.ABC-AZERTY", ["fr"]) == "FR")
        #expect(g("com.apple.keylayout.ABC-QWERTZ", ["de"]) == "DE")
    }

    @Test func nameThenBullet() {
        #expect(g("x.unknown", [], "Zebra") == "Z")
        #expect(g("x.unknown", [], "") == "•")
    }

    @Test func atMostTwoGraphemes() {
        let samples = [
            g("com.apple.keylayout.ABC", ["en"]), g("x.hi", ["hi"]), g("x.de", ["deu"]),
            g("x.u", [], "👩‍👩‍👧Family"), g("x.y", [], ""),
        ]
        for s in samples { #expect((1...2).contains(s.count)) }
    }
}
