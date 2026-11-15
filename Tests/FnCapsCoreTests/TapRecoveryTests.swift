import Foundation
import Testing
@testable import FnCapsCore

/// 시도와 예약을 모아 두고 테스트가 실행 순서를 직접 정한다.
private final class RecoveryHarness {
    var attempts = 0
    var failures: [TapRecovery.StartResult] = []
    var delays: [TimeInterval] = []
    var scheduled: [() -> Void] = []
    var pending: [(TapRecovery.StartResult) -> Void] = []
    /// nil이면 결과를 바로 주지 않고 `pending`에 모은다.
    var respond: TapRecovery.StartResult? = .failed

    lazy var recovery = TapRecovery(
        schedule: { [unowned self] delay, work in
            self.delays.append(delay)
            self.scheduled.append(work)
        },
        attempt: { [unowned self] completion in
            self.attempts += 1
            if let respond = self.respond {
                completion(respond)
            } else {
                self.pending.append(completion)
            }
        },
        onFailure: { [unowned self] result in self.failures.append(result) }
    )

    func runNextScheduled() {
        scheduled.removeFirst()()
    }

    func runAllScheduled() {
        while !scheduled.isEmpty { runNextScheduled() }
    }
}

@Suite struct TapRecoveryTests {
    @Test func defaultDelaysAreHalfOneTwo() {
        let h = RecoveryHarness()
        h.recovery.start()
        h.runAllScheduled()
        #expect(h.delays == [0.5, 1, 2])
    }

    @Test func persistentFailureTriesFourTimesAndFailsOnce() {
        let h = RecoveryHarness()
        h.recovery.start()
        h.runAllScheduled()
        #expect(h.attempts == 4)
        #expect(h.failures == [.failed])
    }

    @Test func startAfterExhaustedBudgetDoesNothing() {
        let h = RecoveryHarness()
        h.recovery.start()
        h.runAllScheduled()
        #expect(h.recovery.isActive == true)
        h.recovery.start()
        h.runAllScheduled()
        #expect(h.attempts == 4)
        #expect(h.failures.count == 1)
    }

    @Test func restartBeginsFromTheStart() {
        let h = RecoveryHarness()
        h.recovery.start()
        h.runAllScheduled()
        h.delays = []
        h.recovery.restart()
        h.runAllScheduled()
        #expect(h.attempts == 8)
        #expect(h.failures.count == 2)
        #expect(h.delays == [0.5, 1, 2])
    }

    @Test func stopInvalidatesScheduledRetry() {
        let h = RecoveryHarness()
        h.recovery.start()
        #expect(h.attempts == 1)
        h.recovery.stop()
        #expect(h.recovery.isActive == false)
        h.runAllScheduled()
        #expect(h.attempts == 1)
        #expect(h.failures.isEmpty)
    }

    @Test func staleScheduleDoesNotJoinNewRecovery() {
        let h = RecoveryHarness()
        h.recovery.start()
        h.recovery.stop()
        h.recovery.start()
        #expect(h.attempts == 2)
        // 옛 예약을 먼저 실행해도 시도가 늘지 않는다.
        h.runNextScheduled()
        #expect(h.attempts == 2)
        // 새 복구는 처음 지연부터 다시 센다.
        h.runAllScheduled()
        #expect(h.attempts == 5)
        #expect(h.failures == [.failed])
        #expect(h.delays == [0.5, 0.5, 1, 2])
    }

    @Test func lateResultAfterStopIsIgnored() {
        let h = RecoveryHarness()
        h.respond = nil
        h.recovery.start()
        h.recovery.stop()
        h.pending.removeFirst()(.failed)
        #expect(h.failures.isEmpty)
        #expect(h.scheduled.isEmpty)
        #expect(h.attempts == 1)
    }

    @Test func lateResultFromOldRecoveryDoesNotAffectNewOne() {
        let h = RecoveryHarness()
        h.respond = nil
        h.recovery.start()
        h.recovery.restart()
        #expect(h.pending.count == 2)
        h.pending.removeFirst()(.permissionRequired)
        #expect(h.failures.isEmpty)
        #expect(h.scheduled.isEmpty)
        h.pending.removeFirst()(.started)
        #expect(h.recovery.isActive == false)
        #expect(h.failures.isEmpty)
    }

    @Test func secondResultForSameAttemptIsIgnored() {
        let h = RecoveryHarness()
        h.respond = nil
        h.recovery.start()
        let completion = h.pending.removeFirst()
        completion(.failed)
        completion(.failed)
        #expect(h.scheduled.count == 1)
    }

    @Test func startedEndsRecoveryAndNextStartAttemptsAgain() {
        let h = RecoveryHarness()
        h.respond = .started
        h.recovery.start()
        #expect(h.attempts == 1)
        #expect(h.scheduled.isEmpty)
        #expect(h.failures.isEmpty)
        #expect(h.recovery.isActive == false)
        h.recovery.start()
        #expect(h.attempts == 2)
    }

    @Test func startedAfterRetriesStopsRetrying() {
        let h = RecoveryHarness()
        h.recovery.start()
        h.respond = .started
        h.runAllScheduled()
        #expect(h.attempts == 2)
        #expect(h.failures.isEmpty)
        #expect(h.recovery.isActive == false)
    }

    @Test func permissionRequiredFailsOnceWithoutRetryAndStaysActive() {
        let h = RecoveryHarness()
        h.respond = .permissionRequired
        h.recovery.start()
        #expect(h.attempts == 1)
        #expect(h.scheduled.isEmpty)
        #expect(h.failures == [.permissionRequired])
        #expect(h.recovery.isActive == true)
        h.recovery.start()
        #expect(h.attempts == 1)
        #expect(h.failures.count == 1)
    }

    @Test func cancelledEndsQuietly() {
        let h = RecoveryHarness()
        h.respond = .cancelled
        h.recovery.start()
        #expect(h.attempts == 1)
        #expect(h.scheduled.isEmpty)
        #expect(h.failures.isEmpty)
        #expect(h.recovery.isActive == false)
        h.recovery.start()
        #expect(h.attempts == 2)
    }

    @Test func customDelaysSetTheBudget() {
        var attempts = 0
        var work: [() -> Void] = []
        var failures = 0
        let recovery = TapRecovery(
            delays: [0.1],
            schedule: { _, w in work.append(w) },
            attempt: { completion in
                attempts += 1
                completion(.failed)
            },
            onFailure: { _ in failures += 1 }
        )
        recovery.start()
        while !work.isEmpty { work.removeFirst()() }
        #expect(attempts == 2)
        #expect(failures == 1)
    }
}

private final class WatchdogHarness {
    var probes = 0
    var pending: [(Bool) -> Void] = []
    var results: [Bool] = []

    lazy var watchdog = ProbeWatchdog(
        probe: { [unowned self] completion in
            self.probes += 1
            self.pending.append(completion)
        },
        onResult: { [unowned self] ok in self.results.append(ok) }
    )
}

@Suite struct ProbeWatchdogTests {
    @Test func checkBeforeStartDoesNotProbe() {
        let h = WatchdogHarness()
        h.watchdog.check()
        #expect(h.probes == 0)
    }

    @Test func checkWhileCheckingDoesNotOverlap() {
        let h = WatchdogHarness()
        h.watchdog.start()
        h.watchdog.check()
        h.watchdog.check()
        #expect(h.probes == 1)
    }

    @Test func bothResultsAreDeliveredAndWatchingContinues() {
        let h = WatchdogHarness()
        h.watchdog.start()
        h.watchdog.check()
        h.pending.removeFirst()(false)
        // 실패에도 멈추지 않는다.
        h.watchdog.check()
        h.pending.removeFirst()(true)
        #expect(h.results == [false, true])
        #expect(h.probes == 2)
    }

    @Test func lateResultAfterStopIsIgnored() {
        let h = WatchdogHarness()
        h.watchdog.start()
        h.watchdog.check()
        h.watchdog.stop()
        h.pending.removeFirst()(true)
        #expect(h.results.isEmpty)
    }

    @Test func checkAfterStopDoesNotProbe() {
        let h = WatchdogHarness()
        h.watchdog.start()
        h.watchdog.stop()
        h.watchdog.check()
        #expect(h.probes == 0)
    }

    @Test func worksAgainAfterRestart() {
        let h = WatchdogHarness()
        h.watchdog.start()
        h.watchdog.check()
        h.watchdog.stop()
        h.pending.removeFirst()(true)
        h.watchdog.start()
        h.watchdog.check()
        #expect(h.probes == 2)
        h.pending.removeFirst()(false)
        #expect(h.results == [false])
    }

    @Test func oldProbeStillRunningBlocksOverlapAfterRestartAndItsResultIsDropped() {
        let h = WatchdogHarness()
        h.watchdog.start()
        h.watchdog.check()
        h.watchdog.stop()
        h.watchdog.start()
        h.watchdog.check()
        #expect(h.probes == 1)
        h.pending.removeFirst()(true)
        #expect(h.results.isEmpty)
        h.watchdog.check()
        #expect(h.probes == 2)
    }
}
