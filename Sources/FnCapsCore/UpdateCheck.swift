import Foundation

/// 점으로 나눈 숫자 버전(최대 3자리). 앞의 v/V는 떼고, `-`나 `+` 뒤(사전 릴리스·빌드 표기)는 비교에서 뺀다.
public struct AppVersion: Comparable, Sendable {
    public let parts: [Int]

    public init?(_ text: String) {
        var s = Substring(text.trimmingCharacters(in: .whitespaces))
        if let first = s.first, first == "v" || first == "V" { s = s.dropFirst() }
        if let cut = s.firstIndex(where: { $0 == "-" || $0 == "+" }) { s = s[..<cut] }
        let pieces = s.split(separator: ".", omittingEmptySubsequences: false)
        guard !s.isEmpty, pieces.count <= 3 else { return nil }
        var numbers: [Int] = []
        for p in pieces {
            guard !p.isEmpty, p.allSatisfy({ $0.isASCII && $0.isNumber }), let n = Int(p) else { return nil }
            numbers.append(n)
        }
        while numbers.count < 3 { numbers.append(0) }
        parts = numbers
    }

    public static func < (lhs: AppVersion, rhs: AppVersion) -> Bool { lhs.parts.lexicographicallyPrecedes(rhs.parts) }
}

/// GitHub `releases/latest` 응답 가운데 쓰는 필드(N5).
/// `assets`는 앱 안 업데이트(D-08)용이다. `releases/tag` 응답에는 없으므로 옵셔널로 둔다.
struct GitHubRelease: Decodable {
    let tag_name: String
    let html_url: String
    let draft: Bool?
    let prerelease: Bool?
    let assets: [Asset]?
    /// 릴리스 노트 본문. 중요 업데이트 표시를 여기서 읽는다(D-15).
    let body: String?

    struct Asset: Decodable {
        let name: String
        let browser_download_url: String
        let size: Int
    }
}

public enum UpdateOutcome: Equatable, Sendable {
    case upToDate(latest: String)
    case available(version: String, url: URL)
    /// 404. 문서에 「릴리스 없음 = 404」라는 문장은 없다(N5). 저장소가 없을 때도 404다.
    case noRelease
    /// 403·429. 인증 없는 한도(시간당 60회) 초과 또는 User-Agent 거부(N4, N6).
    case rateLimited
    case failed
}

/// 업데이트 확인 판정(D-38). 네트워크 호출은 주입한 fetch로만 한다. 내려받기·교체는 하지 않는다.
public enum UpdateCheck {
    /// 자동 확인 주기: 하루 1번(FINAL-REVIEW M8).
    public static let interval: TimeInterval = 86_400

    public static func request(owner: String, repo: String, appVersion: String) -> URLRequest {
        let api = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/releases/latest")
            ?? URL(string: "https://api.github.com/")!
        var r = URLRequest(url: api, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        r.httpMethod = "GET"
        r.httpShouldHandleCookies = false
        r.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        r.setValue("2026-03-10", forHTTPHeaderField: "X-GitHub-Api-Version")
        r.setValue("FnCaps/\(sanitized(appVersion))", forHTTPHeaderField: "User-Agent")
        return r
    }

    public static func evaluate(currentVersion: String, status: Int, data: Data,
                                owner: String, repo: String) -> UpdateOutcome {
        switch status {
        case 200: break
        case 404: return .noRelease
        case 403, 429: return .rateLimited
        default: return .failed
        }
        guard let release = try? JSONDecoder().decode(GitHubRelease.self, from: data),
              let latest = AppVersion(release.tag_name),
              let current = AppVersion(currentVersion) else { return .failed }
        let shown = stripPrefix(release.tag_name)
        guard latest > current else { return .upToDate(latest: shown) }
        return .available(version: shown, url: safeReleaseURL(release.html_url, owner: owner, repo: repo))
    }

    /// `releases/latest` 본문에서 태그와 자산 목록을 꺼낸다(D-08).
    /// 본문이 JSON이 아니면 nil. `assets` 키가 없으면 빈 배열이고,
    /// 주소가 URL로 만들어지지 않는 자산은 목록에서 뺀다.
    public static func parseRelease(_ data: Data) -> ReleaseInfo? {
        guard let release = try? JSONDecoder().decode(GitHubRelease.self, from: data) else { return nil }
        let assets: [ReleaseAsset] = (release.assets ?? []).compactMap { asset in
            guard let url = URL(string: asset.browser_download_url) else { return nil }
            return ReleaseAsset(name: asset.name, url: url, size: asset.size)
        }
        return ReleaseInfo(tag: release.tag_name, assets: assets)
    }

    /// https://github.com/<owner>/<repo>/releases/ 아래일 때만 그 주소를, 아니면 고정 주소를 쓴다(T-04-34).
    public static func safeReleaseURL(_ text: String?, owner: String, repo: String) -> URL {
        let fallback = URL(string: "https://github.com/\(owner)/\(repo)/releases/latest")
            ?? URL(string: "https://github.com/")!
        guard let text, let url = URL(string: text),
              let c = URLComponents(url: url, resolvingAgainstBaseURL: false),
              c.scheme?.lowercased() == "https",
              c.host?.lowercased() == "github.com",
              c.user == nil, c.password == nil, c.port == nil else { return fallback }
        let segments = c.path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard segments.count >= 5, segments[0].isEmpty,
              segments[1].lowercased() == owner.lowercased(),
              segments[2].lowercased() == repo.lowercased(),
              segments[3] == "releases",
              !segments.dropFirst(4).contains(where: { $0 == ".." || $0 == "." }) else { return fallback }
        return url
    }

    /// 자동 확인을 할 때인지. 꺼져 있으면 항상 아니다. 시계가 되돌아가 마지막 확인이 미래면 지금 한다.
    public static func isDue(lastChecked: Date?, now: Date, autoEnabled: Bool) -> Bool {
        guard autoEnabled else { return false }
        guard let lastChecked else { return true }
        if lastChecked > now { return true }
        return now.timeIntervalSince(lastChecked) >= interval
    }

    /// 다음 자동 확인까지 남은 초. 0이면 바로 확인한다(D-11, Sparkle scheduleNextUpdateCheck와 같은 계산).
    /// 마지막 확인이 없거나 시계가 되돌아가 미래면 0이다. isDue와 같은 판정을 유지한다.
    public static func nextCheckDelay(lastChecked: Date?, now: Date) -> TimeInterval {
        guard let lastChecked, lastChecked <= now else { return 0 }
        return max(0, interval - now.timeIntervalSince(lastChecked))
    }

    /// 확인 결과와 릴리스 노트 본문을 함께 돌려준다(D-15: 중요 표시를 본문에서 읽는다).
    public struct CheckResult: Equatable, Sendable {
        public let outcome: UpdateOutcome
        /// 상태 200일 때만 응답의 `body`가 들어간다. 그 밖에는 nil.
        public let releaseBody: String?

        public init(outcome: UpdateOutcome, releaseBody: String?) {
            self.outcome = outcome
            self.releaseBody = releaseBody
        }
    }

    public static func run(owner: String, repo: String, appVersion: String,
                           fetch: (URLRequest) async throws -> (Data, URLResponse)) async -> UpdateOutcome {
        await check(owner: owner, repo: repo, appVersion: appVersion, fetch: fetch).outcome
    }

    /// `run`과 같은 판정을 하면서, 200 응답의 본문도 같은 디코딩에서 꺼낸다.
    public static func check(owner: String, repo: String, appVersion: String,
                             fetch: (URLRequest) async throws -> (Data, URLResponse)) async -> CheckResult {
        let req = request(owner: owner, repo: repo, appVersion: appVersion)
        guard let (data, response) = try? await fetch(req),
              let http = response as? HTTPURLResponse else {
            return CheckResult(outcome: .failed, releaseBody: nil)
        }
        let outcome = evaluate(currentVersion: appVersion, status: http.statusCode, data: data,
                               owner: owner, repo: repo)
        // 본문은 200일 때만 의미가 있다(404·403·그 밖의 상태에는 릴리스가 없다).
        let releaseBody = http.statusCode == 200
            ? (try? JSONDecoder().decode(GitHubRelease.self, from: data))?.body
            : nil
        return CheckResult(outcome: outcome, releaseBody: releaseBody)
    }

    static func stripPrefix(_ tag: String) -> String {
        if let first = tag.first, first == "v" || first == "V" { return String(tag.dropFirst()) }
        return tag
    }

    /// User-Agent에 넣을 버전 문자열. 줄바꿈·공백 같은 헤더 주입 문자를 뺀다.
    static func sanitized(_ version: String) -> String {
        let allowed = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-+_")
        return String(version.filter { allowed.contains($0) })
    }
}
