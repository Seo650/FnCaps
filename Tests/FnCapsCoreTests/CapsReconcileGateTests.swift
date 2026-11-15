import Testing
@testable import FnCapsCore

@Suite struct CapsReconcileGateTests {
    @Test func requestStartsThenRemembersLastWhileApplying() {
        var g = CapsReconcileGate()
        #expect(g.request(.full) == .start(1))
        #expect(g.request(.shortcutOnly) == .remembered)
        #expect(g.request(.full) == .remembered)
        #expect(g.applyFinished(generation: 1, success: true) == .writeMapping)
        #expect(g.applyDone() == .reconcile(.full))  // 마지막 target만 기억
        #expect(g.applyDone() == .idle)
    }

    @Test func fullRequestDuringRestoreIsIgnoredAndNotRevived() {
        var g = CapsReconcileGate()
        #expect(g.beginRestore() == .start(1))
        #expect(g.request(.full) == .ignored)
        #expect(g.restoreFinished() == .idle)
        #expect(g.restoring == false)
        #expect(g.applying == false)
    }

    @Test func restoreDuringApplyQueuesAndApplySkipsMappingWrite() {
        var g = CapsReconcileGate()
        guard case .start(let gen) = g.request(.full) else { Issue.record("no start"); return }
        #expect(g.beginRestore() == .queued)
        #expect(g.generation == gen + 1)  // 줄 서도 즉시 세대가 오른다
        #expect(g.applyFinished(generation: gen, success: true) == .skip)
        #expect(g.applyDone() == .startRestore(gen + 1))
        #expect(g.restoring)
        #expect(g.restoreFinished() == .idle)
    }

    @Test func failedApplyNeverWritesMappingEvenWithSameGeneration() {
        var g = CapsReconcileGate()
        guard case .start(let gen) = g.request(.full) else { Issue.record("no start"); return }
        #expect(g.applyFinished(generation: gen, success: false) == .skip)
    }

    @Test func termination_ignoresRequestsAndDropsRememberedButRestoreStillWorks() {
        var g = CapsReconcileGate()
        _ = g.request(.full)
        #expect(g.request(.shortcutOnly) == .remembered)
        g.beginTermination()
        #expect(g.request(.full) == .ignored)
        #expect(g.applyDone() == .idle)  // 기억해 둔 target은 버려졌다
        #expect(g.beginRestore(force: true) == .start(g.generation))
    }

    @Test func autoRestoreDuringRestoreMergesIntoOne() {
        var g = CapsReconcileGate()
        #expect(g.beginRestore() == .start(1))
        #expect(g.beginRestore() == .queued)
        #expect(g.restoreFinished() == .idle)  // 두 번째 복원 없음
    }

    @Test func forcedRestoreDuringRestoreRunsAgain() {
        var g = CapsReconcileGate()
        _ = g.beginRestore()
        #expect(g.beginRestore(force: true) == .queued)
        if case .startRestore = g.restoreFinished() {} else { Issue.record("expected second restore") }
        #expect(g.restoreFinished() == .idle)
    }

    @Test func turningOffAndResetUseTheSameGate() {
        // 끄기(force)와 되돌리기(force) 모두 beginRestore를 지난다.
        var g = CapsReconcileGate()
        #expect(g.beginRestore(force: true) == .start(1))
        #expect(g.request(.full) == .ignored)
    }

    @Test func requestWhileRestoreQueuedIsIgnored() {
        var g = CapsReconcileGate()
        _ = g.request(.full)
        _ = g.beginRestore()
        #expect(g.request(.full) == .ignored)
    }
}
