import Foundation
import Testing
@testable import FnCapsCore

@Suite struct PermissionFlowTests {

    // MARK: RestartMemory

    @Test func restartMemoryStartsAllowed() {
        let d = MemoryDefaults()
        #expect(RestartMemory(defaults: d).canRestart == true)
    }

    @Test func markRestartedPersistsAcrossInstances() {
        let d = MemoryDefaults()
        RestartMemory(defaults: d).markRestarted()
        #expect(RestartMemory(defaults: d).canRestart == false)
        #expect(d.bool(forKey: RestartMemory.key) == true)
    }

    @Test func clearAllowsRestartAgain() {
        let d = MemoryDefaults()
        let m = RestartMemory(defaults: d)
        m.markRestarted()
        m.clear()
        #expect(RestartMemory(defaults: d).canRestart == true)
    }

    // MARK: RecoveryFailureAction

    @Test func permissionRequiredIgnoresCanRestart() {
        #expect(RecoveryFailureAction.decide(result: .permissionRequired, canRestart: true, tapStartedSinceGrant: false) == .showPermissionNeeded)
        #expect(RecoveryFailureAction.decide(result: .permissionRequired, canRestart: false, tapStartedSinceGrant: false) == .showPermissionNeeded)
    }

    @Test func failedRestartsOnceThenShowsReset() {
        #expect(RecoveryFailureAction.decide(result: .failed, canRestart: true, tapStartedSinceGrant: false) == .autoRestart)
        #expect(RecoveryFailureAction.decide(result: .failed, canRestart: false, tapStartedSinceGrant: false) == .showReset)
    }

    @Test func startedAndCancelledAreIgnored() {
        for canRestart in [true, false] {
            #expect(RecoveryFailureAction.decide(result: .started, canRestart: canRestart, tapStartedSinceGrant: false) == .ignore)
            #expect(RecoveryFailureAction.decide(result: .cancelled, canRestart: canRestart, tapStartedSinceGrant: false) == .ignore)
        }
    }

    // MARK: 재시작 고리 방지

    @Test func noRestartLoopAcrossInstances() {
        let d = MemoryDefaults()
        let first = RestartMemory(defaults: d)
        #expect(RecoveryFailureAction.decide(result: .failed, canRestart: first.canRestart, tapStartedSinceGrant: false) == .autoRestart)
        first.markRestarted()
        let afterRestart = RestartMemory(defaults: d)
        #expect(RecoveryFailureAction.decide(result: .failed, canRestart: afterRestart.canRestart, tapStartedSinceGrant: false) == .showReset)
    }

    @Test func oneSuccessAfterRestartDoesNotReopenTheLoop() {
        let d = MemoryDefaults()
        let first = RestartMemory(defaults: d)
        #expect(RecoveryFailureAction.decide(result: .failed, canRestart: first.canRestart, tapStartedSinceGrant: false) == .autoRestart)
        first.markRestarted()

        let afterRestart = RestartMemory(defaults: d)
        var stability = RestartStability()
        // 재시작 뒤 탭이 한 번 성공해도 60 s가 차지 않았으므로 기록을 지우지 않는다.
        if stability.noteSuccess(now: 0) { afterRestart.clear() }
        #expect(RecoveryFailureAction.decide(result: .failed, canRestart: afterRestart.canRestart, tapStartedSinceGrant: false) == .showReset)
    }

    // MARK: G-08.1-4 권한 잃음

    @Test func failedAfterTapStartedStaysInPlace() {
        #expect(RecoveryFailureAction.decide(result: .failed, canRestart: true, tapStartedSinceGrant: true) == .showPermissionNeeded)
        #expect(RecoveryFailureAction.decide(result: .failed, canRestart: false, tapStartedSinceGrant: true) == .showPermissionNeeded)
    }

    @Test func tapHistoryDoesNotChangeOtherResults() {
        for tapStarted in [true, false] {
            #expect(RecoveryFailureAction.decide(result: .permissionRequired, canRestart: true, tapStartedSinceGrant: tapStarted) == .showPermissionNeeded)
            #expect(RecoveryFailureAction.decide(result: .started, canRestart: true, tapStartedSinceGrant: tapStarted) == .ignore)
            #expect(RecoveryFailureAction.decide(result: .cancelled, canRestart: true, tapStartedSinceGrant: tapStarted) == .ignore)
        }
    }

    @Test func grantSessionTracksTapSinceGrant() {
        var session = GrantSession()
        #expect(session.tapStartedSinceGrant == false)
        session.noteTapStarted()
        #expect(session.tapStartedSinceGrant == true)
        session.noteGrant()
        #expect(session.tapStartedSinceGrant == false)
    }

    @Test func notificationClearsOnlyAfterLossShown() {
        var session = GrantSession()
        session.noteTapStarted()
        // 잃음을 보이기 전의 알림(철회 알림 자체)은 지우지 않는다.
        session.noteAccessibilityNotification()
        #expect(session.tapStartedSinceGrant == true)
        session.noteLossShown()
        // 잃음을 보인 뒤 온 알림은 다시 허용일 수 있어 지운다(낡은 ax가 계속 true여도 L2가 살아난다).
        session.noteAccessibilityNotification()
        #expect(session.tapStartedSinceGrant == false)
    }

    @Test func lossShownWithoutTapIsNoOp() {
        var session = GrantSession()
        session.noteLossShown()
        #expect(session.tapStartedSinceGrant == false)
        session.noteAccessibilityNotification()
        #expect(session.tapStartedSinceGrant == false)
    }

    @Test func revokeThenRegrantRestartsAgain() {
        var session = GrantSession()
        session.noteTapStarted()
        // 철회 알림 → 탭 실패는 재시작하지 않고 제자리 권한 없음.
        session.noteAccessibilityNotification()
        #expect(RecoveryFailureAction.decide(result: .failed, canRestart: true, tapStartedSinceGrant: session.tapStartedSinceGrant) == .showPermissionNeeded)
        // 잃음을 보인 뒤 다시 허용 알림이 오면 탭 실패가 다시 L2 자동 재시작 대상이다.
        session.noteLossShown()
        session.noteAccessibilityNotification()
        #expect(RecoveryFailureAction.decide(result: .failed, canRestart: true, tapStartedSinceGrant: session.tapStartedSinceGrant) == .autoRestart)
    }

    // MARK: RestartStability

    @Test func stabilityNeedsSixtySecondsFromFirstSuccess() {
        var s = RestartStability()
        #expect(s.noteSuccess(now: 0) == false)
        #expect(s.noteSuccess(now: 59) == false)
        #expect(s.noteSuccess(now: 60) == true)
    }

    @Test func failureRestartsTheCount() {
        var s = RestartStability()
        #expect(s.noteSuccess(now: 0) == false)
        s.noteFailure()
        #expect(s.noteSuccess(now: 60) == false)
        #expect(s.noteSuccess(now: 119) == false)
        #expect(s.noteSuccess(now: 120) == true)
    }

    @Test func requiredIsSixtySeconds() {
        #expect(RestartStability.required == 60)
    }

    // MARK: PermissionPanel

    @Test func trustedHidesPanelWhateverStuckSays() {
        for stuck in [true, false] {
            for resetFailed in [true, false] {
                #expect(PermissionPanel.resolve(trusted: true, stuck: stuck, resetFailed: resetFailed) == .hidden)
            }
        }
    }

    @Test func untrustedPanelStates() {
        #expect(PermissionPanel.resolve(trusted: false, stuck: false, resetFailed: false) == .grant)
        #expect(PermissionPanel.resolve(trusted: false, stuck: true, resetFailed: false) == .stuck)
        #expect(PermissionPanel.resolve(trusted: false, stuck: true, resetFailed: true) == .stuckResetFailed)
    }

    @Test func resetFailedKeepsGuidanceAfterStuckClears() {
        #expect(PermissionPanel.resolve(trusted: false, stuck: false, resetFailed: true) == .stuckResetFailed)
    }

    // MARK: RetryPolicy

    private func runRetry(succeedOnCall: Int?) -> (result: Bool, calls: Int, sleeps: [TimeInterval]) {
        var calls = 0
        var sleeps: [TimeInterval] = []
        let result = RetryPolicy.run(sleep: { sleeps.append($0) }) {
            calls += 1
            return calls == succeedOnCall
        }
        return (result, calls, sleeps)
    }

    @Test func retryStopsAtFirstSuccess() {
        let r = runRetry(succeedOnCall: 1)
        #expect(r.result == true)
        #expect(r.calls == 1)
        #expect(r.sleeps.isEmpty)
    }

    @Test func retrySleepsBetweenAttempts() {
        let r = runRetry(succeedOnCall: 2)
        #expect(r.result == true)
        #expect(r.calls == 2)
        #expect(r.sleeps == [0.3])
    }

    @Test func retryGivesUpAfterThree() {
        let r = runRetry(succeedOnCall: nil)
        #expect(r.result == false)
        #expect(r.calls == 3)
        #expect(r.sleeps == [0.3, 0.3])
    }

    // MARK: TapRebuildSchedule

    @Test func rebuildTimes() {
        #expect(TapRebuildSchedule.firstAttempt == 0.3)
        #expect(TapRebuildSchedule.finalCheck == 1.5)
    }
}
