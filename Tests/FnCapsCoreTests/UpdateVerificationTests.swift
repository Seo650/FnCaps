import Foundation
import Testing
@testable import FnCapsCore

/// 앱 안 업데이트(D-08)가 받는 자산·체크섬·압축·버전 규칙을 권한 없이 시험한다.
/// 네트워크는 부르지 않는다. 파일 시스템 접근은 sha256Hex 시험의 임시 파일 하나뿐이다.
@Suite struct UpdateVerificationTests {
    private let owner = "Seo650"
    private let repo = "FnCaps"
    private let tag = "v0.9.0"
    private let zipName = "FnCaps-0.9.0.zip"
    private let zipURLText = "https://github.com/Seo650/FnCaps/releases/download/v0.9.0/FnCaps-0.9.0.zip"
    private let sumsURLText = "https://github.com/Seo650/FnCaps/releases/download/v0.9.0/SHA256SUMS"

    private func asset(_ name: String, _ url: String, size: Int = 1024) -> ReleaseAsset {
        ReleaseAsset(name: name, url: URL(string: url) ?? URL(string: "https://github.com/")!, size: size)
    }

    private func release(_ assets: [ReleaseAsset], tag: String? = nil) -> ReleaseInfo {
        ReleaseInfo(tag: tag ?? self.tag, assets: assets)
    }

    private func pick(_ info: ReleaseInfo) -> (zip: ReleaseAsset, sums: ReleaseAsset)? {
        UpdateVerification.pickAssets(info, owner: owner, repo: repo)
    }

    // MARK: 자산 이름 상수(D-08)

    @Test func assetNamesMatchReleaseScript() {
        #expect(UpdateAssets.appName == "FnCaps.app")
        #expect(UpdateAssets.checksumName == "SHA256SUMS")
        #expect(UpdateAssets.zipName(version: "0.9.0") == "FnCaps-0.9.0.zip")
        #expect(UpdateAssets.receiptFileName == "ready")
        #expect(UpdateAssets.workspacePrefix == "fncaps-update-")
        #expect(UpdateAssets.maxZipBytes == 100 * 1024 * 1024)
        #expect(UpdateAssets.maxUnpackedBytes == 200 * 1024 * 1024)
        #expect(UpdateAssets.maxEntries == 5000)
    }

    // MARK: assetURL (T-05-01)

    @Test func assetURLAcceptsReleaseDownloadURL() {
        let url = UpdateVerification.assetURL(zipURLText, owner: owner, repo: repo, tag: tag, name: zipName)
        #expect(url == URL(string: zipURLText))
    }

    @Test func assetURLComparesOwnerAndRepoWithoutCase() {
        let text = "https://github.com/seo650/fncaps/releases/download/v0.9.0/FnCaps-0.9.0.zip"
        #expect(UpdateVerification.assetURL(text, owner: owner, repo: repo, tag: tag, name: zipName) != nil)
    }

    @Test func assetURLRejectsOtherSchemeHostAndAuthority() {
        let bad = [
            "http://github.com/Seo650/FnCaps/releases/download/v0.9.0/FnCaps-0.9.0.zip",
            "https://evil.example/Seo650/FnCaps/releases/download/v0.9.0/FnCaps-0.9.0.zip",
            "https://github.com:443/Seo650/FnCaps/releases/download/v0.9.0/FnCaps-0.9.0.zip",
            "https://user:pass@github.com/Seo650/FnCaps/releases/download/v0.9.0/FnCaps-0.9.0.zip",
            "https://github.com/Seo650/FnCaps/releases/download/v0.9.0/FnCaps-0.9.0.zip?x=1",
            "https://github.com/Seo650/FnCaps/releases/download/v0.9.0/FnCaps-0.9.0.zip#frag",
            "not a url"
        ]
        for text in bad {
            #expect(UpdateVerification.assetURL(text, owner: owner, repo: repo, tag: tag, name: zipName) == nil)
        }
    }

    @Test func assetURLRejectsPathTraversalAndSegmentCount() {
        let bad = [
            "https://github.com/Seo650/FnCaps/releases/download/v0.9.0/../FnCaps-0.9.0.zip",
            "https://github.com/Seo650/FnCaps/releases/download/v0.9.0/./FnCaps-0.9.0.zip",
            "https://github.com/Seo650/FnCaps/releases/download/v0.9.0/extra/FnCaps-0.9.0.zip",
            "https://github.com/Seo650/FnCaps/releases/download/FnCaps-0.9.0.zip",
            "https://github.com/Seo650/FnCaps/releases/download/v0.9.0/FnCaps-0.9.0.zip/"
        ]
        for text in bad {
            #expect(UpdateVerification.assetURL(text, owner: owner, repo: repo, tag: tag, name: zipName) == nil)
        }
    }

    @Test func assetURLRejectsTagAndNameMismatch() {
        #expect(UpdateVerification.assetURL(zipURLText, owner: owner, repo: repo, tag: "v1.0.0", name: zipName) == nil)
        #expect(UpdateVerification.assetURL(zipURLText, owner: owner, repo: repo, tag: tag, name: "FnCaps.zip") == nil)
        #expect(UpdateVerification.assetURL(zipURLText, owner: owner, repo: repo, tag: tag, name: "SHA256SUMS") == nil)
    }

    // MARK: pickAssets

    @Test func pickAssetsSelectsZipAndChecksum() throws {
        let zip = asset(zipName, zipURLText, size: 12_345)
        let sums = asset("SHA256SUMS", sumsURLText, size: 96)
        let picked = try #require(pick(release([sums, zip])))
        #expect(picked.zip == zip)
        #expect(picked.sums == sums)
    }

    @Test func pickAssetsRejectsDuplicateNames() {
        let zip = asset(zipName, zipURLText, size: 12_345)
        let sums = asset("SHA256SUMS", sumsURLText, size: 96)
        #expect(pick(release([zip, zip, sums])) == nil)
        #expect(pick(release([])) == nil)
    }

    @Test func pickAssetsRejectsMissingChecksumOrZip() {
        let zip = asset(zipName, zipURLText, size: 12_345)
        let sums = asset("SHA256SUMS", sumsURLText, size: 96)
        #expect(pick(release([zip])) == nil)
        #expect(pick(release([sums])) == nil)
        // 태그 버전과 자산 이름이 어긋나면 이름이 맞는 자산이 없다.
        #expect(pick(release([zip, sums], tag: "v1.0.0")) == nil)
    }

    @Test func pickAssetsRejectsZeroAndOversizeBytes() {
        let sums = asset("SHA256SUMS", sumsURLText, size: 96)
        #expect(pick(release([asset(zipName, zipURLText, size: 0), sums])) == nil)
        #expect(pick(release([asset(zipName, zipURLText, size: UpdateAssets.maxZipBytes + 1), sums])) == nil)
        #expect(pick(release([asset(zipName, zipURLText, size: 1),
                              asset("SHA256SUMS", sumsURLText, size: UpdateAssets.maxChecksumBytes + 1)])) == nil)
        // 체크섬 0바이트도 거부한다.
        #expect(pick(release([asset(zipName, zipURLText, size: 1),
                              asset("SHA256SUMS", sumsURLText, size: 0)])) == nil)
    }

    @Test func pickAssetsRejectsForeignAssetURL() {
        let zip = asset(zipName, "https://evil.example/Seo650/FnCaps/releases/download/v0.9.0/FnCaps-0.9.0.zip")
        let sums = asset("SHA256SUMS", sumsURLText, size: 96)
        #expect(pick(release([zip, sums])) == nil)
    }

    // MARK: isAllowedDownload

    @Test func allowedDownloadAcceptsOKFromAllowedHosts() {
        for host in UpdateAssets.allowedDownloadHosts {
            #expect(UpdateVerification.isAllowedDownload(finalURL: URL(string: "https://\(host)/release-asset"), status: 200))
        }
        #expect(UpdateVerification.isAllowedDownload(
            finalURL: URL(string: "https://Objects.GitHubUserContent.com/x?y=1"), status: 200))
        // github.com 자체는 최종 주소가 될 수 없다(다른 저장소의 releases/download 주소를 막는다).
        #expect(!UpdateVerification.isAllowedDownload(
            finalURL: URL(string: "https://github.com/other/repo/releases/download/v9/FnCaps-9.zip"), status: 200))
        #expect(!UpdateVerification.isAllowedDownload(
            finalURL: URL(string: "https://objects.githubusercontent.com:8443/x"), status: 200))
        #expect(!UpdateVerification.isAllowedDownload(
            finalURL: URL(string: "https://user@objects.githubusercontent.com/x"), status: 200))
    }

    @Test func allowedDownloadRequiresStatusAndHTTPS() {
        #expect(!UpdateVerification.isAllowedDownload(finalURL: URL(string: "https://objects.githubusercontent.com/x"), status: 302))
        #expect(!UpdateVerification.isAllowedDownload(finalURL: URL(string: "https://objects.githubusercontent.com/x"), status: 204))
        #expect(!UpdateVerification.isAllowedDownload(finalURL: URL(string: "https://objects.githubusercontent.com/x"), status: 0))
        #expect(!UpdateVerification.isAllowedDownload(finalURL: URL(string: "http://github.com/x"), status: 200))
    }

    @Test func allowedDownloadRejectsForeignHostAndNil() {
        #expect(!UpdateVerification.isAllowedDownload(finalURL: URL(string: "https://evil.example/x"), status: 200))
        #expect(!UpdateVerification.isAllowedDownload(finalURL: URL(string: "https://github.com.evil.example/x"), status: 200))
        #expect(!UpdateVerification.isAllowedDownload(finalURL: nil, status: 200))
    }

    // MARK: expectedChecksum (T-05-02)

    @Test func expectedChecksumReadsStandardTwoSpaceLine() {
        let hex = String(repeating: "a", count: 64)
        let text = "\(String(repeating: "b", count: 64))  other.zip\n\(hex)  \(zipName)\n"
        #expect(UpdateVerification.expectedChecksum(sumsText: text, fileName: zipName) == hex)
    }

    @Test func expectedChecksumAcceptsStarPrefixAndUppercaseHex() {
        let hex = String(repeating: "AB", count: 32)
        #expect(UpdateVerification.expectedChecksum(sumsText: "\(hex) *\(zipName)", fileName: zipName) == hex.lowercased())
    }

    @Test func expectedChecksumIgnoresOtherFiles() {
        let hex = String(repeating: "c", count: 64)
        let text = "\(String(repeating: "d", count: 64))  README.md\n\(hex)  \(zipName)"
        #expect(UpdateVerification.expectedChecksum(sumsText: text, fileName: zipName) == hex)
        // 대상 파일이 없으면 nil.
        #expect(UpdateVerification.expectedChecksum(sumsText: text, fileName: "FnCaps-1.0.0.zip") == nil)
    }

    @Test func expectedChecksumRejectsDuplicateAndEmpty() {
        let hex = String(repeating: "a", count: 64)
        #expect(UpdateVerification.expectedChecksum(sumsText: "", fileName: zipName) == nil)
        #expect(UpdateVerification.expectedChecksum(
            sumsText: "\(hex)  \(zipName)\n\(hex)  \(zipName)", fileName: zipName) == nil)
    }

    @Test func expectedChecksumRejectsMalformedHex() {
        let short = String(repeating: "a", count: 63)
        let long = String(repeating: "a", count: 65)
        let badChar = String(repeating: "g", count: 64)
        let noSeparator = String(repeating: "a", count: 64) + zipName
        for line in ["\(short)  \(zipName)", "\(long)  \(zipName)",
                     "\(badChar)  \(zipName)", noSeparator] {
            #expect(UpdateVerification.expectedChecksum(sumsText: line, fileName: zipName) == nil)
        }
    }

    // MARK: sha256Hex

    @Test func sha256MatchesKnownDigestOfABC() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("fncaps-sha256-\(UUID().uuidString)", isDirectory: false)
        try Data("abc".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(try UpdateVerification.sha256Hex(of: url)
                == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    // MARK: archiveNamesOK (T-05-03)

    @Test func archiveNamesAcceptAppPrefixedEntries() {
        #expect(UpdateVerification.archiveNamesOK(["FnCaps.app/"]))
        #expect(UpdateVerification.archiveNamesOK([
            "FnCaps.app/",
            "FnCaps.app/Contents/Info.plist",
            "FnCaps.app/Contents/MacOS/FnCaps"
        ]))
    }

    @Test func archiveNamesRejectEntriesOutsideTheAppBundle() {
        let bad: [[String]] = [
            ["__MACOSX/._FnCaps.app"],
            ["../evil"],
            ["/etc/x"],
            ["FnCaps.app/../x"],
            ["FnCaps.app/./x"],
            ["FnCaps.app/x\\y"],
            ["FnCaps.app/x\nInjected"],
            ["FnCaps.app"],
            ["FnCaps.app/x", "Other.app/y"],
            []
        ]
        for names in bad {
            #expect(!UpdateVerification.archiveNamesOK(names))
        }
    }

    @Test func archiveNamesRejectTooManyEntries() {
        let names = (0...UpdateAssets.maxEntries).map { "FnCaps.app/\($0)" }
        #expect(!UpdateVerification.archiveNamesOK(names))
        let atLimit = (0..<UpdateAssets.maxEntries).map { "FnCaps.app/\($0)" }
        #expect(UpdateVerification.archiveNamesOK(atLimit))
    }

    // MARK: archiveListingOK (T-05-03)

    private var listing: String {
        """
        Archive:  FnCaps-0.9.0.zip
        Zip file size: 123 bytes, number of entries: 2
        drwxr-xr-x  3.0 unx        0 bx        0 stor 26-Nov-15 10:00 FnCaps.app/
        -rw-r--r--  3.0 unx     1234 tx      567 defN 26-Nov-15 10:00 FnCaps.app/Contents/Info.plist
        2 files, 1234 bytes uncompressed, 567 bytes compressed:  54.1%
        """
    }

    @Test func archiveListingAcceptsRegularEntries() {
        #expect(UpdateVerification.archiveListingOK(listing, expectedEntries: 2))
    }

    @Test func archiveListingRejectsSymlinkEntries() {
        let symlink = listing.replacingOccurrences(of: "-rw-r--r--", with: "lrwxr-xr-x")
        #expect(!UpdateVerification.archiveListingOK(symlink, expectedEntries: 2))
    }

    @Test func archiveListingRejectsEntryCountMismatch() {
        #expect(!UpdateVerification.archiveListingOK(listing, expectedEntries: 3))
        #expect(!UpdateVerification.archiveListingOK(listing, expectedEntries: 1))
        #expect(!UpdateVerification.archiveListingOK("", expectedEntries: 0))
    }

    @Test func archiveListingRejectsOversizedUncompressedTotal() {
        let big = listing.replacingOccurrences(of: "     1234 tx", with: " 2000000000 tx")
        #expect(!UpdateVerification.archiveListingOK(big, expectedEntries: 2))
    }

    @Test func archiveListingRejectsAccumulatedOversize() {
        let huge = """
        Archive:  huge.zip
        Zip file size: 1 bytes, number of entries: 2
        -rw-r--r--  3.0 unx 150000000 tx 1 defN 26-Nov-15 10:00 FnCaps.app/a
        -rw-r--r--  3.0 unx 150000000 tx 1 defN 26-Nov-15 10:00 FnCaps.app/b
        2 files, 300000000 bytes uncompressed, 2 bytes compressed:  0.0%
        """
        #expect(!UpdateVerification.archiveListingOK(huge, expectedEntries: 2))
    }

    // MARK: acceptCandidate (T-05-04)

    @Test func candidateAcceptedWhenNewerWithMatchingIdentityAndVersion() {
        #expect(UpdateVerification.acceptCandidate(
            installedBundleID: "io.github.seo650.fncaps",
            candidateBundleID: "io.github.seo650.fncaps",
            candidateVersion: "0.9.0",
            releaseVersion: "v0.9.0",
            installedVersion: "0.8.0"))
    }

    @Test func candidateRejectedWhenNotNewer() {
        for candidate in ["0.8.0", "0.7.0", "dev", "1.0.0.0"] {
            #expect(!UpdateVerification.acceptCandidate(
                installedBundleID: "io.github.seo650.fncaps",
                candidateBundleID: "io.github.seo650.fncaps",
                candidateVersion: candidate,
                releaseVersion: "v\(candidate)",
                installedVersion: "0.8.0"))
        }
    }

    @Test func candidateRejectedOnIdentityOrVersionMismatch() {
        #expect(!UpdateVerification.acceptCandidate(
            installedBundleID: "io.github.seo650.fncaps",
            candidateBundleID: "com.evil.app",
            candidateVersion: "0.9.0",
            releaseVersion: "v0.9.0",
            installedVersion: "0.8.0"))
        #expect(!UpdateVerification.acceptCandidate(
            installedBundleID: "io.github.seo650.fncaps",
            candidateBundleID: nil,
            candidateVersion: "0.9.0",
            releaseVersion: "v0.9.0",
            installedVersion: "0.8.0"))
        #expect(!UpdateVerification.acceptCandidate(
            installedBundleID: "io.github.seo650.fncaps",
            candidateBundleID: "io.github.seo650.fncaps",
            candidateVersion: nil,
            releaseVersion: "v0.9.0",
            installedVersion: "0.8.0"))
        // 번들 버전이 릴리스 태그와 다르면 거부한다.
        #expect(!UpdateVerification.acceptCandidate(
            installedBundleID: "io.github.seo650.fncaps",
            candidateBundleID: "io.github.seo650.fncaps",
            candidateVersion: "0.9.1",
            releaseVersion: "v0.9.0",
            installedVersion: "0.8.0"))
    }

    // MARK: 설치 위치와 임시 폴더 (T-05-05)

    @Test func installLocationAcceptsApplicationsOnly() {
        #expect(UpdateVerification.installLocationOK(bundlePath: "/Applications/FnCaps.app"))
        #expect(UpdateVerification.installLocationOK(bundlePath: "/Applications/x/FnCaps.app"))
        #expect(!UpdateVerification.installLocationOK(
            bundlePath: "/private/var/folders/x/AppTranslocation/ABC/d/FnCaps.app"))
        #expect(!UpdateVerification.installLocationOK(bundlePath: "/Applications/FnCaps"))
        #expect(!UpdateVerification.installLocationOK(bundlePath: ""))
    }

    @Test func workspaceMustBeDirectChildOfTempRoot() {
        let temp = "/var/folders/x/T"
        #expect(UpdateVerification.isWorkspaceSafe("/var/folders/x/T/fncaps-update-ABC", tempRoot: temp))
        #expect(UpdateVerification.isWorkspaceSafe("/var/folders/x/T/fncaps-update-ABC/", tempRoot: temp + "/"))
        #expect(!UpdateVerification.isWorkspaceSafe("/var/folders/x/T/other-dir", tempRoot: temp))
        #expect(!UpdateVerification.isWorkspaceSafe("/var/folders/x/T/fncaps-update-ABC/../escape", tempRoot: temp))
        #expect(!UpdateVerification.isWorkspaceSafe("/var/folders/x/T/sub/fncaps-update-ABC", tempRoot: temp))
        #expect(!UpdateVerification.isWorkspaceSafe("/tmp/fncaps-update-ABC", tempRoot: temp))
        #expect(!UpdateVerification.isWorkspaceSafe("fncaps-update-ABC", tempRoot: temp))
    }

    @Test func helperArgumentsMustPointAtWorkspaceApp() {
        let temp = "/var/folders/x/T"
        let workspace = "/var/folders/x/T/fncaps-update-ABC"
        #expect(UpdateVerification.isHelperArgumentsSafe(
            workspace: workspace, candidate: workspace + "/FnCaps.app", tempRoot: temp))
        #expect(!UpdateVerification.isHelperArgumentsSafe(
            workspace: workspace, candidate: "/Applications/FnCaps.app", tempRoot: temp))
        #expect(!UpdateVerification.isHelperArgumentsSafe(
            workspace: workspace, candidate: workspace + "/../FnCaps.app", tempRoot: temp))
        #expect(!UpdateVerification.isHelperArgumentsSafe(
            workspace: workspace, candidate: workspace + "/Other.app", tempRoot: temp))
        #expect(!UpdateVerification.isHelperArgumentsSafe(
            workspace: "/Applications/x", candidate: "/Applications/x/FnCaps.app", tempRoot: temp))
    }

    @Test func receiptPathMustLiveInWorkspace() {
        let temp = "/var/folders/x/T"
        let workspace = "/var/folders/x/T/fncaps-update-ABC"
        #expect(UpdateVerification.isReceiptPathSafe(workspace + "/ready", tempRoot: temp))
        #expect(!UpdateVerification.isReceiptPathSafe(workspace + "/other", tempRoot: temp))
        #expect(!UpdateVerification.isReceiptPathSafe("/var/folders/x/T/ready", tempRoot: temp))
        #expect(!UpdateVerification.isReceiptPathSafe("/tmp/fncaps-update-ABC/ready", tempRoot: temp))
        #expect(!UpdateVerification.isReceiptPathSafe(workspace + "/../ready", tempRoot: temp))
    }

    // MARK: parseRelease

    @Test func parseReleaseReadsTagAndAssets() throws {
        let json = """
        {"tag_name":"v0.9.0","html_url":"https://github.com/Seo650/FnCaps/releases/tag/v0.9.0","draft":false,"prerelease":false,\
        "assets":[{"name":"FnCaps-0.9.0.zip","browser_download_url":"\(zipURLText)","size":123},\
        {"name":"SHA256SUMS","browser_download_url":"\(sumsURLText)","size":96}]}
        """
        let info = try #require(UpdateCheck.parseRelease(Data(json.utf8)))
        #expect(info.tag == "v0.9.0")
        #expect(info.assets.count == 2)
        #expect(info.assets[0].name == "FnCaps-0.9.0.zip")
        #expect(info.assets[0].size == 123)
        #expect(info.assets[1].url == URL(string: sumsURLText))
    }

    @Test func parseReleaseWithoutAssetsIsEmpty() throws {
        let json = """
        {"tag_name":"v0.9.0","html_url":"https://github.com/Seo650/FnCaps/releases/tag/v0.9.0"}
        """
        let info = try #require(UpdateCheck.parseRelease(Data(json.utf8)))
        #expect(info.tag == "v0.9.0")
        #expect(info.assets.isEmpty)
    }

    @Test func parseReleaseRejectsBrokenJSON() {
        #expect(UpdateCheck.parseRelease(Data("{not json".utf8)) == nil)
        #expect(UpdateCheck.parseRelease(Data("{}".utf8)) == nil)
        #expect(UpdateCheck.parseRelease(Data()) == nil)
    }

    @Test func parseReleaseDropsUnparsableAssetURLs() throws {
        let json = """
        {"tag_name":"v0.9.0","html_url":"https://github.com/Seo650/FnCaps/releases/tag/v0.9.0",\
        "assets":[{"name":"broken","browser_download_url":"","size":1},\
        {"name":"FnCaps-0.9.0.zip","browser_download_url":"\(zipURLText)","size":123}]}
        """
        let info = try #require(UpdateCheck.parseRelease(Data(json.utf8)))
        #expect(info.assets.count == 1)
        #expect(info.assets[0].name == "FnCaps-0.9.0.zip")
    }

    @Test func parseReleaseFeedsPickAssets() throws {
        let json = """
        {"tag_name":"v0.9.0","html_url":"https://github.com/Seo650/FnCaps/releases/tag/v0.9.0",\
        "assets":[{"name":"FnCaps-0.9.0.zip","browser_download_url":"\(zipURLText)","size":123},\
        {"name":"SHA256SUMS","browser_download_url":"\(sumsURLText)","size":96}]}
        """
        let info = try #require(UpdateCheck.parseRelease(Data(json.utf8)))
        let picked = try #require(pick(info))
        #expect(picked.zip.name == zipName)
        #expect(picked.sums.name == UpdateAssets.checksumName)
    }
}
