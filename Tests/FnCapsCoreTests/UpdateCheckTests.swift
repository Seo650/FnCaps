import Foundation
import Testing
@testable import FnCapsCore

/// 네트워크는 부르지 않는다. fetch는 고정 응답을 돌려주는 클로저다.
@Suite struct UpdateCheckTests {
    private let owner = "seo650"
    private let repo = "FnCaps"
    private let fallback = URL(string: "https://github.com/seo650/FnCaps/releases/latest")!

    private func body(tag: String, url: String) -> Data {
        Data("{\"tag_name\":\"\(tag)\",\"html_url\":\"\(url)\",\"draft\":false,\"prerelease\":false}".utf8)
    }

    private func eval(current: String = "1.0", status: Int = 200, data: Data) -> UpdateOutcome {
        UpdateCheck.evaluate(currentVersion: current, status: status, data: data, owner: owner, repo: repo)
    }

    // MARK: AppVersion

    @Test func versionComparesNumerically() {
        #expect(AppVersion("1.2.3")! < AppVersion("1.10.0")!)
    }

    @Test func versionStripsPrefixAndPadsZeros() {
        #expect(AppVersion("v1.2") == AppVersion("1.2.0"))
        #expect(AppVersion("V2.0") != nil)
        #expect(AppVersion("V2.0") == AppVersion("2"))
    }

    @Test func versionIgnoresPrereleaseSuffix() {
        #expect(AppVersion("1.2.3-beta.1") == AppVersion("1.2.3"))
        #expect(AppVersion("1.2.3+build.7") == AppVersion("1.2.3"))
    }

    @Test func versionRejectsGarbage() {
        #expect(AppVersion("abc") == nil)
        #expect(AppVersion("") == nil)
        #expect(AppVersion("v") == nil)
        #expect(AppVersion("1..2") == nil)
        #expect(AppVersion("1.2.3.4") == nil)
    }

    // MARK: evaluate

    @Test func newerTagIsAvailable() {
        let url = "https://github.com/seo650/FnCaps/releases/tag/v1.1"
        #expect(eval(data: body(tag: "v1.1", url: url)) == .available(version: "1.1", url: URL(string: url)!))
    }

    @Test func sameTagIsUpToDate() {
        let url = "https://github.com/seo650/FnCaps/releases/tag/v1.0"
        #expect(eval(data: body(tag: "v1.0", url: url)) == .upToDate(latest: "1.0"))
    }

    @Test func lowerTagIsUpToDate() {
        let url = "https://github.com/seo650/FnCaps/releases/tag/v0.9"
        #expect(eval(data: body(tag: "v0.9", url: url)) == .upToDate(latest: "0.9"))
    }

    @Test func notFoundIsNoRelease() {
        #expect(eval(status: 404, data: Data()) == .noRelease)
    }

    @Test func forbiddenAndTooManyAreRateLimited() {
        #expect(eval(status: 403, data: Data()) == .rateLimited)
        #expect(eval(status: 429, data: Data()) == .rateLimited)
    }

    @Test func otherStatusIsFailed() {
        #expect(eval(status: 500, data: Data()) == .failed)
        #expect(eval(status: 301, data: Data()) == .failed)
    }

    @Test func brokenJSONIsFailed() {
        #expect(eval(data: Data("{not json".utf8)) == .failed)
        #expect(eval(data: Data("{}".utf8)) == .failed)
    }

    @Test func unparsableTagOrCurrentIsFailed() {
        let url = "https://github.com/seo650/FnCaps/releases/tag/x"
        #expect(eval(data: body(tag: "nightly", url: url)) == .failed)
        #expect(eval(current: "dev", data: body(tag: "v1.1", url: url)) == .failed)
    }

    // MARK: safeReleaseURL

    @Test func untrustedReleaseURLFallsBack() {
        for bad in ["https://evil.example/seo650/FnCaps/releases/tag/v1.1",
                    "http://github.com/seo650/FnCaps/releases/tag/v1.1",
                    "https://github.com/other/FnCaps/releases/tag/v1.1",
                    "https://github.com/seo650/FnCaps/issues/1",
                    "https://github.com/seo650/FnCaps/releases/../../evil/x",
                    "https://user@github.com/seo650/FnCaps/releases/tag/v1.1",
                    "not a url"] {
            #expect(UpdateCheck.safeReleaseURL(bad, owner: owner, repo: repo) == fallback)
        }
        #expect(UpdateCheck.safeReleaseURL(nil, owner: owner, repo: repo) == fallback)
    }

    @Test func availableWithForeignURLUsesFallback() {
        #expect(eval(data: body(tag: "v1.1", url: "https://evil.example/x")) == .available(version: "1.1", url: fallback))
    }

    @Test func ownerRepoMatchIgnoresCase() {
        let url = "https://GitHub.com/SEO650/fncaps/releases/tag/v1.1"
        #expect(UpdateCheck.safeReleaseURL(url, owner: owner, repo: repo) == URL(string: url)!)
    }

    // MARK: request

    @Test func requestHasRequiredHeaders() {
        let r = UpdateCheck.request(owner: owner, repo: repo, appVersion: "1.0")
        #expect(r.url?.absoluteString == "https://api.github.com/repos/seo650/FnCaps/releases/latest")
        #expect(r.httpMethod == "GET")
        #expect(r.value(forHTTPHeaderField: "Accept") == "application/vnd.github+json")
        #expect(r.value(forHTTPHeaderField: "X-GitHub-Api-Version") == "2026-03-10")
        #expect(r.value(forHTTPHeaderField: "User-Agent") == "FnCaps/1.0")
        #expect(r.timeoutInterval == 10)
        #expect(r.httpShouldHandleCookies == false)
    }

    @Test func userAgentDropsUnsafeCharacters() {
        let r = UpdateCheck.request(owner: owner, repo: repo, appVersion: "1.0\r\nX-Evil: 1")
        let ua = r.value(forHTTPHeaderField: "User-Agent") ?? ""
        #expect(!ua.contains("\r") && !ua.contains("\n") && !ua.contains(" "))
        #expect(ua.hasPrefix("FnCaps/1.0"))
    }

    // MARK: isDue

    @Test func dueSchedule() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        #expect(UpdateCheck.interval == 86_400)
        #expect(UpdateCheck.isDue(lastChecked: nil, now: now, autoEnabled: true))
        #expect(!UpdateCheck.isDue(lastChecked: now.addingTimeInterval(-23 * 3600), now: now, autoEnabled: true))
        #expect(UpdateCheck.isDue(lastChecked: now.addingTimeInterval(-24 * 3600), now: now, autoEnabled: true))
        #expect(UpdateCheck.isDue(lastChecked: now.addingTimeInterval(3600), now: now, autoEnabled: true))
    }

    @Test func autoDisabledNeverDue() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        #expect(!UpdateCheck.isDue(lastChecked: nil, now: now, autoEnabled: false))
        #expect(!UpdateCheck.isDue(lastChecked: now.addingTimeInterval(-100 * 86_400), now: now, autoEnabled: false))
    }

    // MARK: run

    @Test func runUsesInjectedFetch() async {
        let url = "https://github.com/seo650/FnCaps/releases/tag/v1.1"
        let data = body(tag: "v1.1", url: url)
        let outcome = await UpdateCheck.run(owner: owner, repo: repo, appVersion: "1.0") { req in
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (data, resp)
        }
        #expect(outcome == .available(version: "1.1", url: URL(string: url)!))
    }

    @Test func runThrowingFetchIsFailed() async {
        struct Boom: Error {}
        let outcome = await UpdateCheck.run(owner: owner, repo: repo, appVersion: "1.0") { _ in throw Boom() }
        #expect(outcome == .failed)
    }

    @Test func runNonHTTPResponseIsFailed() async {
        let outcome = await UpdateCheck.run(owner: owner, repo: repo, appVersion: "1.0") { req in
            (Data(), URLResponse(url: req.url!, mimeType: nil, expectedContentLength: 0, textEncodingName: nil))
        }
        #expect(outcome == .failed)
    }
}
