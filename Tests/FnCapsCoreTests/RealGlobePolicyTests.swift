import Testing
@testable import FnCapsCore

@Suite struct RealGlobePolicyRecentSourcesTests {
    @Test func startsEmpty() {
        let r = RecentSources()
        #expect(r.current == nil)
        #expect(r.previous == nil)
    }

    @Test func observeTracksPrevious() {
        var r = RecentSources()
        r.observe(selected: "ko")
        #expect(r.current == "ko")
        #expect(r.previous == nil)
        r.observe(selected: "ja")
        #expect(r.current == "ja")
        #expect(r.previous == "ko")
    }

    @Test func observeIgnoresNilAndSame() {
        var r = RecentSources()
        r.observe(selected: "ko")
        r.observe(selected: "ja")
        r.observe(selected: nil)
        r.observe(selected: "ja")
        #expect(r.current == "ja")
        #expect(r.previous == "ko")
    }

    @Test func seedFromHistory() {
        var r = RecentSources()
        r.seed(current: "ko", history: ["ko", "ja", "zh"])
        #expect(r.current == "ko")
        #expect(r.previous == "ja")
        r.seed(current: nil, history: ["ja", "ko"])
        #expect(r.current == "ja")
        #expect(r.previous == "ko")
        r.seed(current: "ko", history: [])
        #expect(r.previous == nil)
        r.seed(current: "ko", history: ["ja", "ko"])
        #expect(r.previous == "ja")
    }
}

@Suite struct RealGlobePolicyPrimeDecisionTests {
    private func recent() -> RecentSources {
        var r = RecentSources()
        r.seed(current: "ko", history: ["ko", "ja"])
        return r
    }

    @Test func skipsWhenTargetIsPreviousAndOriginIsCurrent() {
        #expect(PrimeDecision.decide(target: "ja", origin: "ko", recent: recent()) == .skip)
    }

    @Test func primesOtherwise() {
        #expect(PrimeDecision.decide(target: "zh", origin: "ko", recent: recent()) == .prime)
        #expect(PrimeDecision.decide(target: "ja", origin: "abc", recent: recent()) == .prime)
        var r = RecentSources()
        r.observe(selected: "ko")
        #expect(PrimeDecision.decide(target: "ja", origin: "ko", recent: r) == .prime)
    }
}

@Suite struct RealGlobePolicyPrimeTimingTests {
    @Test func adoptedValueIsRelease() {
        #expect(PrimeTiming.defaultValue == .release)
    }
}

@Suite struct RealGlobePolicyPassWindowTests {
    @Test func opensAndCloses() {
        var w = GlobePassWindow(seconds: 0.5)
        #expect(GlobePassWindow.defaultSeconds == 0.5)
        #expect(w.allows(now: 0) == false)
        w.open(now: 10)
        #expect(w.allows(now: 10.2) == true)
        #expect(w.allows(now: 10.5) == false)
        w.close()
        #expect(w.allows(now: 10.1) == false)
    }
}

@Suite struct RealGlobePolicyRepeatGuardTests {
    @Test func firstPressIsNotRapid() {
        var g = FnRepeatGuard(windowMs: 400)
        // user away — review at UAT, Phase 2 결정 500ms 변경 (05-06, 05-FN-TEMPO.md)
        #expect(FnRepeatGuard.defaultWindowMs == 1000)
        #expect(g.notePress(now: 0) == false)
        #expect(g.notePress(now: 0.16) == true)
    }

    @Test func defaultWindowBoundary() {
        var inside = FnRepeatGuard()
        _ = inside.notePress(now: 10)
        #expect(inside.notePress(now: 10.999) == true)
        var outside = FnRepeatGuard()
        _ = outside.notePress(now: 10)
        #expect(outside.notePress(now: 11.001) == false)
    }

    /// 05-06: 0.6~1.0초 간격(중간 박자)도 앱 안 경로로 간다. 04.1-UAT O1·C7.
    @Test func widenedWindowCatchesMediumTempoPresses() {
        var g = FnRepeatGuard()
        _ = g.notePress(now: 10)
        #expect(g.wouldBeRapid(now: 10.7) == true)
        #expect(g.wouldBeRapid(now: 11.1) == false)
    }

    @Test func chainsFromPreviousPress() {
        var g = FnRepeatGuard(windowMs: 400)
        #expect(g.notePress(now: 0) == false)
        #expect(g.notePress(now: 0.3) == true)
        #expect(g.notePress(now: 0.6) == true)
        #expect(g.lastPressAt == 0.6)
        #expect(g.notePress(now: 1.1) == false)
        #expect(g.lastPressAt == 1.1)
    }

    @Test func wouldBeRapidDoesNotMutate() {
        var g = FnRepeatGuard(windowMs: 400)
        _ = g.notePress(now: 0)
        #expect(g.wouldBeRapid(now: 0.1) == true)
        #expect(g.lastPressAt == 0)
        #expect(g.notePress(now: 0.5) == false)
    }

    @Test func zeroWindowAndReset() {
        var z = FnRepeatGuard(windowMs: 0)
        #expect(z.notePress(now: 0) == false)
        #expect(z.notePress(now: 0.001) == false)
        var g = FnRepeatGuard(windowMs: 400)
        _ = g.notePress(now: 0)
        g.reset()
        #expect(g.notePress(now: 0.1) == false)
    }
}

@Suite struct RealGlobePolicyRouteTests {
    @Test func passesToOSForUsageOneOrUnsetAndCalm() {
        #expect(FnRoutePolicy.changeInputSourceUsage == 1)
        #expect(FnRoutePolicy.decide(isSwitch: true, usage: 1, rapid: false, alreadySwitching: false) == .passToOS)
        for u in [0, 2, 3] as [Int?] {
            #expect(FnRoutePolicy.decide(isSwitch: true, usage: u, rapid: false, alreadySwitching: false) == .inApp)
        }
        // 새 계정은 키가 없다. 1로 본다(D-10)
        #expect(FnRoutePolicy.decide(isSwitch: true, usage: nil, rapid: false, alreadySwitching: false) == .passToOS)
        #expect(FnRoutePolicy.decide(isSwitch: true, usage: nil, rapid: true, alreadySwitching: false) == .inApp)
        #expect(FnRoutePolicy.decide(isSwitch: true, usage: nil, rapid: false, alreadySwitching: true) == .inApp)
        #expect(FnRoutePolicy.decide(isSwitch: false, usage: nil, rapid: false, alreadySwitching: false) == .inApp)
        #expect(FnRoutePolicy.decide(isSwitch: true, usage: 1, rapid: true, alreadySwitching: false) == .inApp)
        #expect(FnRoutePolicy.decide(isSwitch: true, usage: 1, rapid: false, alreadySwitching: true) == .inApp)
        #expect(FnRoutePolicy.decide(isSwitch: false, usage: 1, rapid: false, alreadySwitching: false) == .inApp)
    }
}

@Suite struct RealGlobePolicySignalTimingTests {
    @Test func capsHopWorstCaseCoversTwoLegsStableAndPlanB() {
        #expect(SignalTiming.capsHopWorstCaseMs == SignalTiming.perSignalLimitMs * 3 + 60)
        #expect(SignalTiming.capsHopWorstCaseMs == 1560)
    }

    @Test func switchWatchdogIsDerivedFromTheSignalLimit() {
        #expect(SignalTiming.switchWatchdogMs == SignalTiming.perSignalLimitMs * 3 + 300)
        #expect(SignalTiming.switchWatchdogMs == 1800)
    }

    @Test func switchWatchdogOutlivesTheCapsHopWorstCase() {
        #expect(SignalTiming.switchWatchdogMs - SignalTiming.capsHopWorstCaseMs >= 200)
    }
}
