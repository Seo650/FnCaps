import Foundation
import Testing
@testable import FnCapsCore

@Suite struct CapsPressTests {
    @Test func firstDownIsAPressAndIsConsumed() {
        var g = CapsPressGate()
        let r = g.handle(down: true, autorepeat: false)
        #expect(r.consume && r.press)
        #expect(g.held)
    }

    @Test func autorepeatIsConsumedButNotAPress() {
        var g = CapsPressGate()
        _ = g.handle(down: true, autorepeat: false)
        let r = g.handle(down: true, autorepeat: true)
        #expect(r.consume)
        #expect(r.press == false)
    }

    @Test func releaseOfHeldKeyIsConsumed() {
        var g = CapsPressGate()
        _ = g.handle(down: true, autorepeat: false)
        let r = g.handle(down: false, autorepeat: false)
        #expect(r.consume)
        #expect(r.press == false)
        #expect(g.held == false)
    }

    @Test func releaseWithoutPressIsNotConsumed() {
        var g = CapsPressGate()
        let r = g.handle(down: false, autorepeat: false)
        #expect(r.consume == false)
        #expect(r.press == false)
    }

    @Test func missedReleaseThenNewDownIsANewPress() {
        var g = CapsPressGate()
        _ = g.handle(down: true, autorepeat: false)
        let r = g.handle(down: true, autorepeat: false)
        #expect(r.consume && r.press)
    }

    @Test func resetClearsHeld() {
        var g = CapsPressGate()
        _ = g.handle(down: true, autorepeat: false)
        g.reset()
        #expect(g.held == false)
        #expect(g.handle(down: false, autorepeat: false).consume == false)
    }
}

@Suite struct CapsPressJudgeTests {
    private func begun(delay: TimeInterval = 0.5) -> CapsPressJudge {
        var j = CapsPressJudge()
        j.begin(now: 10, delay: delay)
        return j
    }

    // 표의 각 행
    @Test func releaseBeforeDelaySwitches() {
        var j = begun()
        #expect(j.release(now: 10.499) == .switchNow(.release))
    }

    @Test func releaseAtExactDelayIsLong() {
        var j = begun()
        #expect(j.release(now: 10.5) == .long)
    }

    @Test func releaseAfterDelayWithLateTimerIsLong() {
        var j = begun()
        #expect(j.release(now: 10.9) == .long)
    }

    @Test func otherKeyBeforeDecisionSwitchesByKey() {
        var j = begun()
        #expect(j.otherKey() == .switchNow(.key))
    }

    @Test func timerBeforeDelayDoesNothing() {
        var j = begun()
        #expect(j.timer(now: 10.499) == .none)
        #expect(j.isPending)
    }

    @Test func timerAtBoundaryIsLong() {
        var j = begun()
        #expect(j.timer(now: 10.5) == .long)
        #expect(j.isPending == false)
    }

    // 한 누름당 한 결과
    @Test func afterSwitchOnReleaseEverythingIsNone() {
        var j = begun()
        #expect(j.release(now: 10.1) == .switchNow(.release))
        #expect(j.release(now: 10.2) == .none)
        #expect(j.otherKey() == .none)
        #expect(j.timer(now: 11) == .none)
    }

    @Test func afterSwitchOnKeyEverythingIsNone() {
        var j = begun()
        #expect(j.otherKey() == .switchNow(.key))
        #expect(j.otherKey() == .none)
        #expect(j.release(now: 10.1) == .none)
        #expect(j.timer(now: 11) == .none)
    }

    @Test func afterLongEverythingIsNone() {
        var j = begun()
        #expect(j.timer(now: 10.6) == .long)
        #expect(j.otherKey() == .none)
        #expect(j.release(now: 10.7) == .none)
        #expect(j.timer(now: 11) == .none)
    }

    @Test func afterLongOnReleaseTimerAndKeyAreNone() {
        var j = begun()
        #expect(j.release(now: 10.8) == .long)
        #expect(j.timer(now: 11) == .none)
        #expect(j.otherKey() == .none)
    }

    // 취소: 길게 누르기만 취소하고 뒤이은 뗌은 전환한다
    @Test func cancelBlocksTimerButReleaseStillSwitches() {
        var j = begun()
        j.cancel()
        #expect(j.timer(now: 11) == .none)
        #expect(j.release(now: 11) == .switchNow(.release))
    }

    @Test func cancelThenOtherKeyStillSwitches() {
        var j = begun()
        j.cancel()
        #expect(j.otherKey() == .switchNow(.key))
    }

    // 초기화
    @Test func resetDropsPendingPressSoReleaseDoesNothing() {
        var j = begun()
        j.reset()
        #expect(j.isPending == false)
        #expect(j.release(now: 10.1) == .none)
        #expect(j.otherKey() == .none)
    }

    @Test func idleJudgeReturnsNone() {
        var j = CapsPressJudge()
        #expect(j.release(now: 1) == .none)
        #expect(j.otherKey() == .none)
        #expect(j.timer(now: 1) == .none)
        j.cancel()
        #expect(j.isPending == false)
    }

    @Test func beginClearsPreviousStateIncludingCancel() {
        var j = begun()
        j.cancel()
        j.begin(now: 20, delay: 0.5)
        #expect(j.timer(now: 20.5) == .long)
    }

    @Test func beginReplacesUndecidedPress() {
        var j = begun()
        j.begin(now: 20, delay: 0.5)
        #expect(j.release(now: 20.1) == .switchNow(.release))
    }

    // 설정값
    @Test func timerNoneWhenLongDisabled() {
        var j = CapsPressJudge()
        j.begin(now: 10, delay: 0.5, longEnabled: false)
        #expect(j.timer(now: 12) == .none)
    }

    @Test func lateReleaseStillSwitchesWhenLongDisabled() {
        var j = CapsPressJudge()
        j.begin(now: 10, delay: 0.5, longEnabled: false)
        #expect(j.release(now: 20) == .switchNow(.release))
    }

    @Test func delayComesFromSetting() {
        var j = begun(delay: 0.3)
        #expect(j.timer(now: 10.3) == .long)
        var k = begun(delay: 1.0)
        #expect(k.timer(now: 10.9) == .none)
        #expect(k.release(now: 10.9) == .switchNow(.release))
    }

    @Test func clampKeepsSettingInRange() {
        #expect(CapsPressJudge.clampMs(100) == 300)
        #expect(CapsPressJudge.clampMs(300) == 300)
        #expect(CapsPressJudge.clampMs(500) == 500)
        #expect(CapsPressJudge.clampMs(1000) == 1000)
        #expect(CapsPressJudge.clampMs(5000) == 1000)
        #expect(CapsPressJudge.defaultMs == 500)
    }
}

@Suite struct CapsLongRuleTests {
    // 행: 기준 언어(일반 자판), 그 밖의 일반 자판, 입력기. 열: 체크박스 꺼짐/켬.
    @Test func baseLayoutOff() {
        #expect(CapsLongRule.action(fromBase: true, isLayout: true, layoutsOnly: false) == .flipLock)
    }

    @Test func baseLayoutOn() {
        #expect(CapsLongRule.action(fromBase: true, isLayout: true, layoutsOnly: true) == .flipLock)
    }

    @Test func otherLayoutOff() {
        #expect(CapsLongRule.action(fromBase: false, isLayout: true, layoutsOnly: false) == .switchToBaseThenFlip)
    }

    @Test func otherLayoutOn() {
        #expect(CapsLongRule.action(fromBase: false, isLayout: true, layoutsOnly: true) == .flipLock)
    }

    @Test func inputMethodOff() {
        #expect(CapsLongRule.action(fromBase: false, isLayout: false, layoutsOnly: false) == .switchToBaseThenFlip)
    }

    @Test func inputMethodOn() {
        #expect(CapsLongRule.action(fromBase: false, isLayout: false, layoutsOnly: true) == .ignore)
    }

    @Test func baseInputMethodFollowsTable() {
        #expect(CapsLongRule.action(fromBase: true, isLayout: false, layoutsOnly: false) == .flipLock)
        #expect(CapsLongRule.action(fromBase: true, isLayout: false, layoutsOnly: true) == .ignore)
    }

    @Test func baseReturnLimitIsSeparateConstant() {
        #expect(CapsLongRule.baseReturnLimit == 0.5)
    }

    // MARK: 바꿀 영어 고르기(quick 261121-cle)

    private static let abc = makeSource("abc", ["en"])
    private static let us = makeSource("us", ["en-US"])
    private static let ko = makeSource("ko", ["ko"])
    private static let ja = makeSource("ja", ["ja"])

    /// Caps 목록에 영어가 있으면 그 영어.
    @Test func englishInCapsList() {
        let target = CapsLongRule.englishTarget(
            caps: ["abc", "ko"], fn: ["ja"], excluded: [],
            sources: [Self.abc, Self.us, Self.ko, Self.ja])
        #expect(target == "abc")
    }

    /// 영어가 fn 목록에만 있어도 그 영어로 간다(2026-11-21 사용자 결정).
    @Test func englishOnlyInFnList() {
        let target = CapsLongRule.englishTarget(
            caps: ["ko"], fn: ["abc"], excluded: [], sources: [Self.abc, Self.ko])
        #expect(target == "abc")
    }

    /// 영어가 「사용 안 함」에만 있어도 그 영어로 간다.
    @Test func englishOnlyInExcluded() {
        let target = CapsLongRule.englishTarget(
            caps: ["ko"], fn: ["ja"], excluded: ["abc"], sources: [Self.abc, Self.ko, Self.ja])
        #expect(target == "abc")
    }

    /// 영어가 둘이면 Caps → fn → 사용 안 함 순서로 앞 목록의 영어.
    @Test func listOrderWins() {
        let target = CapsLongRule.englishTarget(
            caps: [], fn: ["abc"], excluded: ["us"], sources: [Self.abc, Self.us])
        #expect(target == "abc")
    }

    /// Caps 목록의 영어가 fn 목록의 영어보다 앞선다.
    @Test func capsBeforeFn() {
        let target = CapsLongRule.englishTarget(
            caps: ["us"], fn: ["abc"], excluded: [], sources: [Self.abc, Self.us])
        #expect(target == "us")
    }

    /// 같은 목록에 영어가 둘이면 놓인 순서의 앞 영어.
    @Test func placementOrderWithinList() {
        let target = CapsLongRule.englishTarget(
            caps: ["us", "abc"], fn: [], excluded: [], sources: [Self.abc, Self.us])
        #expect(target == "us")
    }

    /// 꺼진 소스는 후보에서 뺀다.
    @Test func disabledSourceIgnored() {
        let target = CapsLongRule.englishTarget(
            caps: ["abc"], fn: [], excluded: [], sources: [Self.ko])
        #expect(target == nil)
    }

    /// 영어가 하나도 없으면 nil(전환 없이 잠금만 바꾼다).
    @Test func noEnglishReturnsNil() {
        let target = CapsLongRule.englishTarget(
            caps: ["ko"], fn: ["ja"], excluded: [], sources: [Self.ko, Self.ja])
        #expect(target == nil)
    }
}
