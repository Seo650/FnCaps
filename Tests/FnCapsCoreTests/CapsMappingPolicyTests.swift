import Testing
@testable import FnCapsCore

@Suite struct CapsMappingPolicyTests {
    private func target(
        ax: Bool = true, enabled: Bool = true, tap: Bool = true, absent: Double = 0, active: Bool = true, away: Bool = false, taken: Bool = false, route: Bool = true, appOff: Bool = false
    ) -> CapsSystemTarget {
        CapsMappingPolicy.target(
            axTrusted: ax, enabled: enabled, tapInstalled: tap, tapAbsentSeconds: absent, capsListActive: active, sessionAway: away, appOff: appOff, capsTaken: taken, hasPulseRoute: route)
    }

    @Test func appOffLowersMappingOnly() {
        // FINAL-REVIEW §7 R1: 「FnCaps 끄기」 앱이 맨 앞이면 화면 잠금과 같은 shortcutOnly(매핑만 내림).
        #expect(target(appOff: true) == .shortcutOnly)
        #expect(target(tap: false, absent: 0, appOff: true) == .shortcutOnly)  // hold 상황에서도
        #expect(target(tap: false, absent: 60, appOff: true) == .shortcutOnly)
    }

    @Test func noneBeatsAppOff() {
        #expect(target(enabled: false, appOff: true) == .none)
        #expect(target(ax: false, appOff: true) == .none)
        #expect(target(active: false, appOff: true) == .none)
        #expect(target(taken: true, appOff: true) == .none)
        #expect(target(route: false, appOff: true) == .none)
    }

    @Test func allConditionsGiveFull() { #expect(target() == .full) }

    @Test func awayKeepsShortcutOnly() {
        #expect(target(away: true) == .shortcutOnly)
        #expect(target(tap: false, absent: 99, away: true) == .shortcutOnly)  // 잠긴 동안에는 탭이 없어도
    }

    @Test func eachNoneConditionGivesNone() {
        #expect(target(enabled: false) == .none)
        #expect(target(ax: false) == .none)
        #expect(target(active: false) == .none)  // Caps 목록이 비면 매핑·#60을 걸지 않는다(D-26)
        #expect(target(taken: true) == .none)
        #expect(target(route: false) == .none)
    }

    @Test func noneBeatsAway() {
        #expect(target(enabled: false, away: true) == .none)
        #expect(target(ax: false, away: true) == .none)
        #expect(target(away: true, taken: true) == .none)
        #expect(target(away: true, route: false) == .none)
        #expect(target(active: false, away: true) == .none)
    }

    @Test func trustedWithoutTapWithinGraceHoldsInsteadOfNone() {
        // WR-01: 정책에는 탭 성공 여부가 아니라 실제 권한 값이 간다. 권한 참 + 탭 없음 + 5초 미만 = hold.
        #expect(target(ax: true, tap: false, absent: 0) == .hold)
        #expect(target(ax: true, tap: false, absent: 4.99) == .hold)
        #expect(target(ax: true, tap: false, absent: 5) == .none)
    }

    @Test func missingTapHoldsFiveSecondsThenNone() {
        #expect(target(tap: false, absent: 0) == .hold)
        #expect(target(tap: false, absent: 4.9) == .hold)
        #expect(target(tap: false, absent: 5) == .none)
        #expect(target(tap: false, absent: 60) == .none)
    }

    @Test func missingTapWithoutPermissionOrEnabledIsNone() {
        #expect(target(ax: false, tap: false, absent: 0) == .none)
        #expect(target(enabled: false, tap: false, absent: 0) == .none)
    }

    @Test func truthTableOverAllBooleanInputs() {
        // 모든 불리언 조합: 없음 조건이 하나라도 있으면 .none, 아니면 away > tap 순서.
        for bits in 0..<(1 << 7) {
            let ax = bits & 1 != 0, en = bits & 2 != 0, tap = bits & 4 != 0, base = bits & 8 != 0
            let away = bits & 16 != 0, taken = bits & 32 != 0, route = bits & 64 != 0
            let got = target(ax: ax, enabled: en, tap: tap, absent: 10, active: base, away: away, taken: taken, route: route)
            let expected: CapsSystemTarget
            if !(ax && en && base && !taken && route) { expected = .none }
            else if away { expected = .shortcutOnly }
            else if !tap { expected = .none }
            else { expected = .full }
            #expect(got == expected, "bits=\(bits)")
        }
    }
}

@Suite struct CapsTickDecisionTests {
    @Test func proceedsOnlyWhenIdleActiveAndFull() {
        #expect(CapsTickDecision.decide(sessionAway: false, lastTarget: .full, gateIdle: true, terminating: false) == .proceed)
    }

    @Test func awayWithFullMarksAway() {
        #expect(CapsTickDecision.decide(sessionAway: true, lastTarget: .full, gateIdle: true, terminating: false) == .markAway)
    }

    @Test func everythingElseStaysIdle() {
        let none: CapsSystemTarget? = CapsSystemTarget.none
        #expect(CapsTickDecision.decide(sessionAway: false, lastTarget: none, gateIdle: true, terminating: false) == .stayIdle)
        #expect(CapsTickDecision.decide(sessionAway: false, lastTarget: .full, gateIdle: false, terminating: false) == .stayIdle)
        #expect(CapsTickDecision.decide(sessionAway: false, lastTarget: .full, gateIdle: true, terminating: true) == .stayIdle)
        #expect(CapsTickDecision.decide(sessionAway: false, lastTarget: nil, gateIdle: true, terminating: false) == .stayIdle)
        #expect(CapsTickDecision.decide(sessionAway: true, lastTarget: .shortcutOnly, gateIdle: true, terminating: false) == .stayIdle)
        #expect(CapsTickDecision.decide(sessionAway: true, lastTarget: nil, gateIdle: true, terminating: false) == .stayIdle)
        #expect(CapsTickDecision.decide(sessionAway: true, lastTarget: .full, gateIdle: false, terminating: false) == .stayIdle)
        #expect(CapsTickDecision.decide(sessionAway: true, lastTarget: .full, gateIdle: true, terminating: true) == .stayIdle)
    }
}
