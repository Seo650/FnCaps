import Foundation
import Testing
@testable import FnCapsCore

/// 실제 파일 시스템을 부르지 않는다. 경로 집합으로 파일 시스템을 흉내 내고 실패할 연산을 주입한다(D-08).
private final class FakeOps: ReplacementFileOps {
    private(set) var existing: Set<String>
    private let failOn: (op: String, from: String)?

    init(existing: Set<String>, failOn: (op: String, from: String)? = nil) {
        self.existing = existing
        self.failOn = failOn
    }

    private func shouldFail(_ op: String, _ from: String) -> Bool {
        guard let failOn else { return false }
        return failOn.op == op && failOn.from == from
    }

    func exists(_ path: String) -> Bool { existing.contains(path) }

    func copy(_ from: String, to: String) throws {
        if shouldFail("copy", from) { throw FakeError.injected }
        existing.insert(to)
    }

    func move(_ from: String, to: String) throws {
        if shouldFail("move", from) { throw FakeError.injected }
        existing.remove(from)
        existing.insert(to)
    }

    func remove(_ path: String) throws {
        if shouldFail("remove", path) { throw FakeError.injected }
        existing.remove(path)
    }
}

private enum FakeError: Error { case injected }

/// 교체·복원 순서의 실패 주입 시험(T-05-07). 성공 경로와 각 단계 실패를 따로 본다.
@Suite struct AppReplacementTests {
    private let installed = "/Applications/FnCaps.app"
    private let candidate = "/private/tmp/fncaps-update-X/FnCaps.app"
    private let token = "T"

    private var paths: (stage: String, backup: String, failed: String) {
        AppReplacement.paths(installed: installed, token: token)
    }

    @Test func pathsSitNextToInstalled() {
        let p = paths
        #expect(p.stage == "/Applications/.fncaps-update-T.app")
        #expect(p.backup == "/Applications/.fncaps-rollback-T.app")
        #expect(p.failed == "/Applications/.fncaps-failed-T.app")
    }

    @Test func successKeepsInstalledAndRemovesBackup() {
        let ops = FakeOps(existing: [installed, candidate])
        let result = AppReplacement.replace(
            installed: installed, candidate: candidate, token: token, ops: ops,
            launchAndConfirm: { _ in true })
        #expect(result == .installed)
        #expect(ops.exists(installed))
        #expect(!ops.exists(paths.backup))
        #expect(!ops.exists(paths.stage))
    }

    @Test func stageCopyFailureLeavesInstalledUntouched() {
        let ops = FakeOps(existing: [installed, candidate], failOn: (op: "copy", from: candidate))
        let result = AppReplacement.replace(
            installed: installed, candidate: candidate, token: token, ops: ops,
            launchAndConfirm: { _ in true })
        #expect(result == .rolledBack(step: "stage"))
        #expect(ops.exists(installed))
        #expect(!ops.exists(paths.stage))
    }

    @Test func backupMoveFailureRemovesStage() {
        let ops = FakeOps(existing: [installed, candidate], failOn: (op: "move", from: installed))
        let result = AppReplacement.replace(
            installed: installed, candidate: candidate, token: token, ops: ops,
            launchAndConfirm: { _ in true })
        #expect(result == .rolledBack(step: "backup"))
        #expect(ops.exists(installed))
        #expect(!ops.exists(paths.stage))
    }

    @Test func swapFailureRestoresBackup() {
        let ops = FakeOps(existing: [installed, candidate], failOn: (op: "move", from: paths.stage))
        let result = AppReplacement.replace(
            installed: installed, candidate: candidate, token: token, ops: ops,
            launchAndConfirm: { _ in true })
        #expect(result == .rolledBack(step: "swap"))
        #expect(ops.exists(installed))
        #expect(!ops.exists(paths.backup))
    }

    @Test func launchFailureRestoresBackupAndParksCandidate() {
        let ops = FakeOps(existing: [installed, candidate])
        let result = AppReplacement.replace(
            installed: installed, candidate: candidate, token: token, ops: ops,
            launchAndConfirm: { _ in false })
        #expect(result == .rolledBack(step: "launch"))
        #expect(ops.exists(installed))
        #expect(!ops.exists(paths.backup))
        #expect(!ops.exists(paths.failed))
    }

    @Test func launchFailureWithoutRestoreReportsBackupPath() {
        let ops = FakeOps(existing: [installed, candidate], failOn: (op: "move", from: paths.backup))
        let result = AppReplacement.replace(
            installed: installed, candidate: candidate, token: token, ops: ops,
            launchAndConfirm: { _ in false })
        #expect(result == .rollbackFailed(backupPath: paths.backup))
        #expect(ops.exists(paths.backup))
    }

    @Test func stageVerificationFailureRollsBackBeforeSwap() {
        let ops = FakeOps(existing: [installed, candidate])
        let result = AppReplacement.replace(
            installed: installed, candidate: candidate, token: token, ops: ops,
            verifyStage: { _ in false },
            launchAndConfirm: { _ in true })
        #expect(result == .rolledBack(step: "stage"))
        #expect(ops.exists(installed))
        #expect(!ops.exists(paths.stage))
        #expect(!ops.exists(paths.backup))
    }

    @Test func swapFailureRemovesTheStage() {
        let ops = FakeOps(existing: [installed, candidate], failOn: (op: "move", from: paths.stage))
        let result = AppReplacement.replace(
            installed: installed, candidate: candidate, token: token, ops: ops,
            launchAndConfirm: { _ in true })
        #expect(result == .rolledBack(step: "swap"))
        #expect(ops.exists(installed))
        #expect(!ops.exists(paths.stage))
    }
}
