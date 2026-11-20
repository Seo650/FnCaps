import Foundation
import Testing
@testable import FnCapsCore

/// 중요 업데이트 표시 파싱·판정(D-15, D-16, D-19). 네트워크·화면은 부르지 않는다.
@Suite struct ImportantNoticeTests {
    /// 저장소 뿌리. `Tests/FnCapsCoreTests/<이 파일>`에서 세 단계 위다(LocalizationParityTests와 같다).
    static var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    /// 06-01이 만든 형식 견본. 공개 저장소에는 packaging이 없으므로 없으면 건너뛴다.
    static var sampleURL: URL {
        repoRoot.appendingPathComponent("packaging/release-notes/examples/important.md")
    }

    static var sampleExists: Bool {
        FileManager.default.fileExists(atPath: sampleURL.path)
    }

    // MARK: 견본 파일

    @Test(.enabled(if: ImportantNoticeTests.sampleExists))
    func sampleFileParses() throws {
        let text = try String(contentsOf: Self.sampleURL, encoding: .utf8)
        let notice = try #require(ImportantNotice.parse(text))
        #expect(notice.below == "1.2.3")
        #expect(!notice.english.isEmpty)
        #expect(Set(notice.localized.keys) == Set(ImportantNotice.languages))
        #expect(notice.localized["ko"] != nil)
    }

    // MARK: parse 실패

    @Test func missingMarkerIsNil() {
        #expect(ImportantNotice.parse("Some release notes.\n\nNothing important here.") == nil)
    }

    @Test func headerWithoutCommentIsNil() {
        let body = "## Important\n\nFixed a bug.\n\n- Nothing else changes."
        #expect(ImportantNotice.parse(body) == nil)
    }

    @Test func missingClosingLineIsNil() {
        let body = "## Important\n\nFixed a bug.\n\n<!-- fncaps:important below=1.2.3\nko: 고쳤습니다."
        #expect(ImportantNotice.parse(body) == nil)
    }

    @Test func unreadableBelowIsNil() {
        let body = "## Important\n\nFixed a bug.\n\n<!-- fncaps:important below=abc\nko: 고쳤습니다.\n-->"
        #expect(ImportantNotice.parse(body) == nil)
    }

    @Test func emptyEnglishIsNil() {
        let body = "## Important\n\n\n\n<!-- fncaps:important below=1.2.3\nko: 고쳤습니다.\n-->"
        #expect(ImportantNotice.parse(body) == nil)
    }

    // MARK: parse 성공

    @Test func crlfParsesLikeLf() throws {
        let body = """
        ## Important

        Fixed a bug.

        <!-- fncaps:important below=1.2.3
        ko: 고쳤습니다.
        ja: 修正しました。
        -->
        """
        let lf = try #require(ImportantNotice.parse(body))
        let crlf = try #require(ImportantNotice.parse(body.replacingOccurrences(of: "\n", with: "\r\n")))
        #expect(lf == crlf)
    }

    @Test func duplicateAndUnknownCodesAreHandled() throws {
        let body = """
        ## Important

        Fixed a bug.

        <!-- fncaps:important below=1.2.3
        ko: 첫 줄
        ko: 둘째 줄
        pt: ignorado
        de:ohne Abstand
        ja: 修正しました。
        -->
        """
        let notice = try #require(ImportantNotice.parse(body))
        #expect(notice.localized["ko"] == "첫 줄")
        #expect(notice.localized["pt"] == nil)
        #expect(notice.localized["de"] == nil)
        #expect(notice.localized["ja"] == "修正しました。")
    }

    @Test func englishLinesJoinWithSingleSpace() throws {
        let body = """
        ## Important

        Fixed a bug.
        Another line here.

        <!-- fncaps:important below=1.2.3
        ko: 고쳤습니다.
        -->
        """
        let notice = try #require(ImportantNotice.parse(body))
        #expect(notice.english == "Fixed a bug. Another line here.")
    }

    // MARK: text

    @Test func textFallsBackToEnglish() throws {
        let body = """
        ## Important

        Fixed a bug.

        <!-- fncaps:important below=1.2.3
        ko: 고쳤습니다.
        -->
        """
        let notice = try #require(ImportantNotice.parse(body))
        #expect(notice.text(language: "ko") == "고쳤습니다.")
        #expect(notice.text(language: "en") == "Fixed a bug.")
        #expect(notice.text(language: "fr") == "Fixed a bug.")
    }

    @Test func emptyLanguageLineFallsBackToEnglish() throws {
        let body = "## Important\n\nFixed a bug.\n\n<!-- fncaps:important below=1.2.3\nko: \u{202E}\u{2066}\n-->"
        let notice = try #require(ImportantNotice.parse(body))
        #expect(notice.localized["ko"] == nil)
        #expect(notice.text(language: "ko") == "Fixed a bug.")
    }

    // MARK: clean

    @Test func cleanRemovesControlsAndDirectionals() {
        let dirty = "\u{202E}abc\u{2066}\tdef\u{0007}  "
        #expect(ImportantNotice.clean(dirty) == "abcdef")
    }

    @Test func cleanCapsLength() {
        #expect(ImportantNotice.clean(String(repeating: "a", count: 4500)).count == 4000)
        #expect(ImportantNotice.clean(String(repeating: "가", count: 4000)).count == 4000)
    }

    // MARK: offer

    @Test func offerAppliesOnlyBelowMarker() throws {
        let body = """
        ## Important

        Fixed a bug.

        <!-- fncaps:important below=1.2.3
        ko: 고쳤습니다.
        -->
        """
        let offered = ImportantNotice.offer(body: body, latest: "1.2.3", currentVersion: "1.2.2", language: "ko")
        #expect(offered == ImportantOffer(version: "1.2.3", text: "고쳤습니다."))
        #expect(ImportantNotice.offer(body: body, latest: "1.2.3", currentVersion: "1.2.3", language: "ko") == nil)
        #expect(ImportantNotice.offer(body: nil, latest: "1.2.3", currentVersion: "1.0", language: "ko") == nil)
        #expect(ImportantNotice.offer(body: body, latest: "1.2.3", currentVersion: "dev", language: "ko") == nil)
    }

    // MARK: activatesOnShow

    @Test func activationWindowIsFirstMinute() {
        let launched = Date(timeIntervalSince1970: 1_000_000)
        #expect(ImportantNotice.launchActivationWindow == 60)
        #expect(ImportantNotice.activatesOnShow(launchedAt: launched, now: launched))
        #expect(ImportantNotice.activatesOnShow(launchedAt: launched, now: launched.addingTimeInterval(59)))
        #expect(!ImportantNotice.activatesOnShow(launchedAt: launched, now: launched.addingTimeInterval(60)))
        #expect(!ImportantNotice.activatesOnShow(launchedAt: launched, now: launched.addingTimeInterval(3600)))
        #expect(!ImportantNotice.activatesOnShow(launchedAt: launched, now: launched.addingTimeInterval(-1)))
    }
}
