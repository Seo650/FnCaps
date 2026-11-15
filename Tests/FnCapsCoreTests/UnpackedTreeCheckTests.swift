import Foundation
import Testing
@testable import FnCapsCore

/// 임시 폴더에 진짜 파일을 만들어 `lstat` 기반 검사를 본다(05 WR-05).
@Suite struct UnpackedTreeCheckTests {
    private func fixture(_ body: (URL) throws -> Void) throws -> String {
        let base = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("fncaps-treecheck-\(UUID().uuidString)", isDirectory: true)
        let root = base.appendingPathComponent("FnCaps.app", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try body(root)
        return root.path
    }

    private func cleanup(_ root: String) {
        try? FileManager.default.removeItem(atPath: (root as NSString).deletingLastPathComponent)
    }

    private func write(_ root: URL, _ relative: String, bytes: Int = 4) throws {
        let url = root.appendingPathComponent(relative)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(count: bytes).write(to: url)
    }

    @Test func plainBundleWithInsideLinksIsOK() throws {
        let root = try fixture { r in
            try write(r, "Contents/MacOS/FnCaps")
            try write(r, "Contents/Frameworks/X.framework/Versions/A/X")
            try FileManager.default.createSymbolicLink(
                atPath: r.path + "/Contents/Frameworks/X.framework/Versions/Current", withDestinationPath: "A")
            try FileManager.default.createSymbolicLink(
                atPath: r.path + "/Contents/Frameworks/X.framework/X",
                withDestinationPath: "Versions/Current/X")
        }
        defer { cleanup(root) }
        #expect(UnpackedTreeCheck.inspect(root: root) == .ok)
    }

    @Test func absoluteSymlinkIsRejected() throws {
        let root = try fixture { r in
            try FileManager.default.createSymbolicLink(
                atPath: r.path + "/evil", withDestinationPath: "/etc/passwd")
        }
        defer { cleanup(root) }
        #expect(UnpackedTreeCheck.inspect(root: root) == .escapingSymlink("evil"))
    }

    @Test func parentEscapingSymlinkIsRejected() throws {
        let root = try fixture { r in
            try write(r, "Contents/x")
            try FileManager.default.createSymbolicLink(
                atPath: r.path + "/Contents/up", withDestinationPath: "../../outside")
        }
        defer { cleanup(root) }
        #expect(UnpackedTreeCheck.inspect(root: root) == .escapingSymlink("Contents/up"))
    }

    @Test func parentSymlinkThatStaysInsideIsAllowed() throws {
        let root = try fixture { r in
            try write(r, "Contents/a/file")
            try FileManager.default.createSymbolicLink(
                atPath: r.path + "/Contents/a/back", withDestinationPath: "../a/file")
        }
        defer { cleanup(root) }
        #expect(UnpackedTreeCheck.inspect(root: root) == .ok)
    }

    @Test func totalSizeCapUsesRealBytes() throws {
        let root = try fixture { r in
            try write(r, "a", bytes: 600)
            try write(r, "b", bytes: 600)
        }
        defer { cleanup(root) }
        #expect(UnpackedTreeCheck.inspect(root: root, maxBytes: 1000, maxEntries: 10) == .tooLarge)
        #expect(UnpackedTreeCheck.inspect(root: root, maxBytes: 1300, maxEntries: 10) == .ok)
    }

    @Test func entryCountCapCountsDirectoriesToo() throws {
        let root = try fixture { r in
            try write(r, "d/1")
            try write(r, "d/2")
            try write(r, "d/3")
        }
        defer { cleanup(root) }
        // d + 3 files = 4 entries
        #expect(UnpackedTreeCheck.inspect(root: root, maxBytes: 1000, maxEntries: 3) == .tooManyEntries)
        #expect(UnpackedTreeCheck.inspect(root: root, maxBytes: 1000, maxEntries: 4) == .ok)
    }

    @Test func hardLinkIsRejected() throws {
        let root = try fixture { r in
            try write(r, "a")
            try FileManager.default.linkItem(atPath: r.path + "/a", toPath: r.path + "/b")
        }
        defer { cleanup(root) }
        let verdict = UnpackedTreeCheck.inspect(root: root)
        guard case .hardLink = verdict else {
            Issue.record("expected hardLink, got \(verdict)")
            return
        }
    }

    @Test func rootThatIsASymlinkOrMissingIsInvalid() throws {
        let root = try fixture { r in try write(r, "a") }
        defer { cleanup(root) }
        let link = (root as NSString).deletingLastPathComponent + "/Link.app"
        try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: root)
        #expect(UnpackedTreeCheck.inspect(root: link) == .rootInvalid)
        #expect(UnpackedTreeCheck.inspect(root: root + "/nope") == .rootInvalid)
    }

    @Test func linkResolutionIsLexicalAndRefusesAbsolute() {
        let root = "/private/tmp/w/FnCaps.app"
        #expect(UnpackedTreeCheck.linkStaysInside(target: "A", linkDirectory: root + "/X", root: root))
        #expect(!UnpackedTreeCheck.linkStaysInside(target: "/x", linkDirectory: root, root: root))
        #expect(!UnpackedTreeCheck.linkStaysInside(target: "..", linkDirectory: root, root: root))
        #expect(UnpackedTreeCheck.linkStaysInside(target: "../b", linkDirectory: root + "/a", root: root))
        #expect(!UnpackedTreeCheck.linkStaysInside(target: "", linkDirectory: root, root: root))
    }
}
