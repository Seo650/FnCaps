import Testing
@testable import FnCapsCore

@Suite struct CapsSwitchPlanTests {
    private func recent(current: String, previous: String) -> RecentSources {
        var r = RecentSources()
        r.seed(current: current, history: [current, previous])
        return r
    }

    @Test func previousIsTargetGivesPulse() {
        let r = recent(current: "ja", previous: "abc")
        let p = CapsSwitchPlan.decide(
            target: "abc", origin: "ja", recent: r, originIsLayout: false, targetIsLayout: true, mayBeComposing: true)
        #expect(p == .pulse)
    }

    @Test func originLayoutPrimesWithoutHop() {
        let r = recent(current: "abc", previous: "ko")
        let p = CapsSwitchPlan.decide(
            target: "ja", origin: "abc", recent: r, originIsLayout: true, targetIsLayout: false, mayBeComposing: true)
        #expect(p == .primeThenPulse)
    }

    @Test func targetInputMethodPrimesWithoutHop() {
        let r = recent(current: "ko", previous: "ja")
        let p = CapsSwitchPlan.decide(
            target: "zh", origin: "ko", recent: r, originIsLayout: false, targetIsLayout: false, mayBeComposing: true)
        #expect(p == .primeThenPulse)
    }

    @Test func riskyComposingWithPreviousHops() {
        let r = recent(current: "ja", previous: "ko")
        let p = CapsSwitchPlan.decide(
            target: "abc", origin: "ja", recent: r, originIsLayout: false, targetIsLayout: true, mayBeComposing: true)
        #expect(p == .hopThenPrime)
    }

    @Test func riskyNotComposingPrimes() {
        let r = recent(current: "ja", previous: "ko")
        let p = CapsSwitchPlan.decide(
            target: "abc", origin: "ja", recent: r, originIsLayout: false, targetIsLayout: true, mayBeComposing: false)
        #expect(p == .primeThenPulse)
    }

    @Test func riskyWithoutPreviousPrimes() {
        let r = RecentSources()
        let p = CapsSwitchPlan.decide(
            target: "abc", origin: "ja", recent: r, originIsLayout: false, targetIsLayout: true, mayBeComposing: true)
        #expect(p == .primeThenPulse)
    }

    @Test func timingConstants() {
        #expect(SignalTiming.perSignalLimitMs == 500)
    }

    @Test func failureLogReplay() {
        var s = LandingStability(timeoutMs: SignalTiming.perSignalLimitMs, stableMs: 30)
        #expect(s.observe(isTarget: false, elapsedMs: 45.9) == .waiting)
        #expect(s.observe(isTarget: false, elapsedMs: 105) == .waiting)
        #expect(s.observe(isTarget: true, elapsedMs: 110.3) == .waiting)
        #expect(s.observe(isTarget: true, elapsedMs: 140.3) == .landed)
    }

    @Test func neverLandingPulseTimesOutAtLimit() {
        var s = LandingStability(timeoutMs: SignalTiming.perSignalLimitMs, stableMs: 30)
        #expect(s.observe(isTarget: false, elapsedMs: 499.9) == .waiting)
        #expect(s.observe(isTarget: false, elapsedMs: 500) == .timedOut)
    }
}
