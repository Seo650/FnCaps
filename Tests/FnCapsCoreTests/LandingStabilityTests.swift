import Testing
@testable import FnCapsCore

@Suite struct LandingStabilityTests {
    @Test func zeroStableLandsOnFirstTargetRead() {
        var s = LandingStability(timeoutMs: 80, stableMs: 0)
        #expect(s.observe(isTarget: true, elapsedMs: 0) == .landed)
    }

    @Test func briefTargetReadAfterPrimeIsNotLanding() {
        var s = LandingStability(timeoutMs: 80, stableMs: 30)
        #expect(s.observe(isTarget: true, elapsedMs: 0) == .waiting)
        #expect(s.observe(isTarget: false, elapsedMs: 5) == .waiting)
        #expect(s.observe(isTarget: false, elapsedMs: 80) == .timedOut)
    }

    @Test func steadyTargetReadLandsAfterStableTime() {
        var s = LandingStability(timeoutMs: 80, stableMs: 30)
        #expect(s.observe(isTarget: true, elapsedMs: 10) == .waiting)
        #expect(s.observe(isTarget: true, elapsedMs: 39) == .waiting)
        #expect(s.observe(isTarget: true, elapsedMs: 40) == .landed)
    }

    @Test func dropResetsStableTime() {
        var s = LandingStability(timeoutMs: 200, stableMs: 30)
        #expect(s.observe(isTarget: true, elapsedMs: 0) == .waiting)
        #expect(s.observe(isTarget: false, elapsedMs: 20) == .waiting)
        #expect(s.observe(isTarget: true, elapsedMs: 40) == .waiting)
        #expect(s.observe(isTarget: true, elapsedMs: 69) == .waiting)
        #expect(s.observe(isTarget: true, elapsedMs: 70) == .landed)
    }

    @Test func targetReadStartedBeforeTimeoutMayFinishAfterIt() {
        var s = LandingStability(timeoutMs: 80, stableMs: 30)
        #expect(s.observe(isTarget: true, elapsedMs: 75) == .waiting)
        #expect(s.observe(isTarget: true, elapsedMs: 85) == .waiting)
        #expect(s.observe(isTarget: true, elapsedMs: 105) == .landed)
    }

    @Test func neverTargetTimesOut() {
        var s = LandingStability(timeoutMs: 80, stableMs: 30)
        #expect(s.observe(isTarget: false, elapsedMs: 79) == .waiting)
        #expect(s.observe(isTarget: false, elapsedMs: 80) == .timedOut)
    }

    @Test func lateOsLandingWithinSignalLimitIsLanded() {
        var s = LandingStability(timeoutMs: SignalTiming.perSignalLimitMs, stableMs: 0)
        #expect(s.observe(isTarget: false, elapsedMs: 80) == .waiting)
        #expect(s.observe(isTarget: false, elapsedMs: 150) == .waiting)
        #expect(s.observe(isTarget: true, elapsedMs: 150.6) == .landed)
    }
}
