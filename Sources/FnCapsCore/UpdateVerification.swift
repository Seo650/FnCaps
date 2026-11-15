import Foundation
import CryptoKit

/// 앱 안 업데이트(D-08)가 받는 자산의 이름·한도·허용 호스트. `scripts/release.sh`가 같은 값을 쓴다.
public enum UpdateAssets {
    public static let appName = "FnCaps.app"
    public static let checksumName = "SHA256SUMS"
    /// 릴리스 자산 이름 규칙. 태그의 `v`를 뗀 버전을 쓴다(RESEARCH Pattern 1).
    public static func zipName(version: String) -> String { "FnCaps-\(version).zip" }
    /// 내려받기 한도(T-05-06). zip 100MB, 체크섬 100KB.
    public static let maxZipBytes = 100 * 1024 * 1024
    public static let maxChecksumBytes = 100 * 1024
    /// 풀린 압축의 총 크기와 항목 수 한도(T-05-03, T-05-06).
    public static let maxUnpackedBytes = 200 * 1024 * 1024
    public static let maxEntries = 5000
    /// 내려받기 응답의 최종 주소로 허용하는 호스트(RESEARCH Pattern 1).
    public static let allowedDownloadHosts: Set<String> = [
        "release-assets.githubusercontent.com",
        "objects.githubusercontent.com"
    ]
    /// 임시 폴더 바로 아래 만들어 쓰는 작업 폴더 접두사(T-05-05).
    public static let workspacePrefix = "fncaps-update-"
    /// 새 앱이 살아 있다는 표시로 쓰는 영수증 파일 이름.
    public static let receiptFileName = "ready"
}

/// 릴리스 자산 한 건. 이름·주소·크기는 GitHub 응답에서 온 신뢰하지 않는 입력이다.
public struct ReleaseAsset: Equatable, Sendable {
    public let name: String
    public let url: URL
    public let size: Int

    public init(name: String, url: URL, size: Int) {
        self.name = name
        self.url = url
        self.size = size
    }
}

/// `releases/latest` 응답 가운데 업데이터가 쓰는 값.
public struct ReleaseInfo: Equatable, Sendable {
    public let tag: String
    public let assets: [ReleaseAsset]

    public init(tag: String, assets: [ReleaseAsset]) {
        self.tag = tag
        self.assets = assets
    }
}

/// 업데이트 자산·체크섬·압축·버전의 판정(D-08). 순수 함수만 두고 권한 없이 시험한다.
/// 네트워크·프로세스는 이 파일에 없다. 파일을 읽는 곳은 `sha256Hex` 하나뿐이다.
public enum UpdateVerification {
    /// 릴리스 자산 주소가 `<owner>/<repo>/releases/download/<tag>/<name>`과 정확히 같은지 본다(T-05-01).
    /// https, github.com, user·password·port·query·fragment 없음, 경로 조각 7개를 모두 확인한다.
    public static func assetURL(_ text: String, owner: String, repo: String,
                                tag: String, name: String) -> URL? {
        guard let url = URL(string: text),
              let c = URLComponents(url: url, resolvingAgainstBaseURL: false),
              c.scheme?.lowercased() == "https",
              c.host?.lowercased() == "github.com",
              c.user == nil, c.password == nil, c.port == nil,
              c.query == nil, c.fragment == nil else { return nil }
        let segments = c.path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard segments.count == 7, segments[0].isEmpty,
              segments[1].lowercased() == owner.lowercased(),
              segments[2].lowercased() == repo.lowercased(),
              segments[3] == "releases",
              segments[4] == "download",
              segments[5] == tag,
              segments[6] == name else { return nil }
        return url
    }

    /// zip과 SHA256SUMS 자산을 각각 정확히 하나씩 고른다(T-05-06).
    /// 이름·크기 한도·주소를 모두 통과하지 못하면 nil이다.
    public static func pickAssets(_ info: ReleaseInfo, owner: String, repo: String)
        -> (zip: ReleaseAsset, sums: ReleaseAsset)? {
        let version = UpdateCheck.stripPrefix(info.tag)
        let zipName = UpdateAssets.zipName(version: version)
        let zips = info.assets.filter { $0.name == zipName }
        let sums = info.assets.filter { $0.name == UpdateAssets.checksumName }
        guard zips.count == 1, sums.count == 1,
              let zip = zips.first, let checksum = sums.first,
              (1...UpdateAssets.maxZipBytes).contains(zip.size),
              (1...UpdateAssets.maxChecksumBytes).contains(checksum.size),
              assetURL(zip.url.absoluteString, owner: owner, repo: repo, tag: info.tag, name: zip.name) != nil,
              assetURL(checksum.url.absoluteString, owner: owner, repo: repo,
                       tag: info.tag, name: checksum.name) != nil else { return nil }
        return (zip, checksum)
    }

    /// 내려받기 응답이 성공(200)이고 최종 주소가 https + 허용 호스트(GitHub 자산 저장소만, 포트·사용자 정보 없음)인지 본다(T-05-01, T-05-05).
    public static func isAllowedDownload(finalURL: URL?, status: Int) -> Bool {
        guard status == 200, let finalURL,
              let c = URLComponents(url: finalURL, resolvingAgainstBaseURL: false),
              c.scheme?.lowercased() == "https",
              c.port == nil, c.user == nil, c.password == nil,
              let host = c.host?.lowercased(),
              UpdateAssets.allowedDownloadHosts.contains(host) else { return false }
        return true
    }

    /// `SHA256SUMS`에서 대상 파일 줄을 정확히 하나 찾아 소문자 hex를 돌려준다(T-05-02).
    /// 형식은 `<64 hex><공백><공백 또는 별표><이름>`이다. 다른 파일 줄과 빈 줄은 무시한다.
    public static func expectedChecksum(sumsText: String, fileName: String) -> String? {
        let hexChars = Set("0123456789abcdefABCDEF")
        var matches: [String] = []
        for line in sumsText.components(separatedBy: .newlines) {
            let chars = Array(line)
            guard chars.count > 65 else { continue }
            let head = String(chars[0..<64])
            guard head.allSatisfy({ hexChars.contains($0) }), chars[64] == " " else { continue }
            var rest = String(chars[65...])
            if rest.hasPrefix("*") || rest.hasPrefix(" ") { rest.removeFirst() }
            guard rest == fileName else { continue }
            matches.append(head.lowercased())
        }
        return matches.count == 1 ? matches[0] : nil
    }

    /// 파일의 SHA256을 소문자 hex로 돌려준다. 구현은 CryptoKit에 맡긴다(T-05-02).
    public static func sha256Hex(of file: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let chunk = try handle.read(upToCount: 1024 * 1024) ?? Data()
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// 풀기 전에 미리 보는 압축 항목 이름이 안전한지 본다(T-05-03).
    /// 모두 `FnCaps.app/` 아래여야 하고, `..`·`.`·절대 경로·역슬래시·개행을 거부한다.
    public static func archiveNamesOK(_ names: [String]) -> Bool {
        guard (1...UpdateAssets.maxEntries).contains(names.count) else { return false }
        for name in names {
            guard !name.isEmpty,
                  !name.hasPrefix("/"),
                  !name.contains("\\"), !name.contains("\r"), !name.contains("\n") else { return false }
            guard name == "FnCaps.app/" || name.hasPrefix("FnCaps.app/") else { return false }
            let parts = name.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
            guard !parts.contains(where: { $0 == ".." || $0 == "." }) else { return false }
        }
        return true
    }

    /// `unzip -Z -l` 출력을 보고 항목 수·총 크기·심볼릭 링크 여부를 판정한다(T-05-03).
    /// 항목 줄은 첫 토큰이 10글자 모드 문자열이다. 모드 첫 글자가 `-` 또는 `d`여야 한다.
    public static func archiveListingOK(_ listing: String, expectedEntries: Int) -> Bool {
        guard (1...UpdateAssets.maxEntries).contains(expectedEntries) else { return false }
        let directoryModes = Set("dl-bcps")
        let permissionChars = Set("-rwxstST")
        var entries = 0
        var total = 0
        for line in listing.components(separatedBy: .newlines) {
            let tokens = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
            guard tokens.count >= 4, tokens[0].count == 10,
                  let mode = tokens[0].first, directoryModes.contains(mode),
                  tokens[0].dropFirst().allSatisfy({ permissionChars.contains($0) }),
                  let size = Int(tokens[3]), size >= 0 else { continue }
            guard mode == "-" || mode == "d" else { return false }
            entries += 1
            let (sum, overflow) = total.addingReportingOverflow(size)
            if overflow { return false }
            total = sum
        }
        guard entries == expectedEntries, total <= UpdateAssets.maxUnpackedBytes else { return false }
        return true
    }

    /// 새로 받은 앱이 이 앱의 정당한 다음 버전인지 본다(T-05-04).
    /// 번들 ID 동일, 번들 버전 == 릴리스 태그 버전, 설치본보다 새 버전일 때만 받는다.
    public static func acceptCandidate(installedBundleID: String, candidateBundleID: String?,
                                       candidateVersion: String?, releaseVersion: String,
                                       installedVersion: String) -> Bool {
        guard let candidateBundleID, candidateBundleID == installedBundleID,
              let candidateVersion,
              UpdateCheck.stripPrefix(candidateVersion) == UpdateCheck.stripPrefix(releaseVersion),
              let candidate = AppVersion(candidateVersion),
              let installed = AppVersion(installedVersion),
              candidate > installed else { return false }
        return true
    }

    /// 설치 경로가 `.app`이고 Translocation(검역된 임시 실행)이 아닌지 본다(T-05-05).
    public static func installLocationOK(bundlePath: String) -> Bool {
        guard !bundlePath.isEmpty,
              bundlePath.hasSuffix(".app"),
              !bundlePath.contains("/AppTranslocation/") else { return false }
        return true
    }

    /// 작업 폴더가 임시 폴더 바로 아래의 `fncaps-update-` 폴더인지 본다(T-05-05).
    /// 경로만 보고 표준화한다. 심볼릭 링크 해석은 호출하는 쪽이 `resolvingSymlinksInPath()`로 끝낸다.
    public static func isWorkspaceSafe(_ workspace: String, tempRoot: String) -> Bool {
        let path = (workspace as NSString).standardizingPath
        let root = (tempRoot as NSString).standardizingPath
        guard path.hasPrefix("/"), root.hasPrefix("/"), path != "/", root != "/",
              path != root else { return false }
        let parts = path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard !parts.isEmpty, !parts.contains(where: { $0 == ".." || $0 == "." }),
              let last = parts.last, last.hasPrefix(UpdateAssets.workspacePrefix) else { return false }
        let parent = "/" + parts.dropLast().joined(separator: "/")
        return parent == root
    }

    /// 도우미 프로세스에 넘기는 인자가 작업 폴더와 그 안의 `FnCaps.app`뿐인지 본다(T-05-05).
    public static func isHelperArgumentsSafe(workspace: String, candidate: String, tempRoot: String) -> Bool {
        guard isWorkspaceSafe(workspace, tempRoot: tempRoot) else { return false }
        let ws = (workspace as NSString).standardizingPath
        let path = (candidate as NSString).standardizingPath
        return path == ws + "/" + UpdateAssets.appName
    }

    /// 영수증 파일 경로가 작업 폴더 안의 고정 이름인지 본다(T-05-05).
    public static func isReceiptPathSafe(_ path: String, tempRoot: String) -> Bool {
        let standardized = (path as NSString).standardizingPath
        let parts = standardized.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard parts.last == UpdateAssets.receiptFileName else { return false }
        let parent = "/" + parts.dropLast().joined(separator: "/")
        return isWorkspaceSafe(parent, tempRoot: tempRoot)
    }
}
