import Testing
@testable import FnCapsCore

@Suite struct FnGestureTests {
    func down(_ t: Double = 0) -> FnGesture.Input { .fnFlags(down: true, now: t) }
    func up(_ t: Double) -> FnGesture.Input { .fnFlags(down: false, now: t) }

    @Test func loneTapSwitchesOnRelease() {
        var g = FnGesture()
        #expect(g.handle(down()) == .pass)
        #expect(g.handle(up(0.1)) == .consumeAndSwitch)
    }

    @Test func globeKey179AlwaysConsumed() {
        var g = FnGesture()
        #expect(g.handle(.globeKey179) == .consume)
        _ = g.handle(down())
        #expect(g.handle(.globeKey179) == .consume)
    }

    @Test func otherKeyDownMakesReleasePass() {
        var g = FnGesture()
        _ = g.handle(down())
        #expect(g.handle(.otherKeyDown(keyCode: 122)) == .pass)
        #expect(g.handle(up(0.1)) == .pass)
    }

    @Test func otherFlagsChangedMakesReleasePass() {
        var g = FnGesture()
        _ = g.handle(down())
        #expect(g.handle(.otherFlagsChanged) == .pass)
        #expect(g.handle(up(0.1)) == .pass)
    }

    @Test func systemDefinedMakesReleasePass() {
        var g = FnGesture()
        _ = g.handle(down())
        #expect(g.handle(.systemDefined) == .pass)
        #expect(g.handle(up(0.1)) == .pass)
    }

    @Test func mouseDownMakesReleasePass() {
        var g = FnGesture()
        _ = g.handle(down())
        #expect(g.handle(.mouseDown) == .pass)
        #expect(g.handle(up(0.1)) == .pass)
    }

    @Test func otherKeyUpDoesNotChangeState() {
        var g = FnGesture()
        _ = g.handle(down())
        #expect(g.handle(.otherKeyUp) == .pass)
        #expect(g.handle(up(0.1)) == .consumeAndSwitch)
    }

    @Test func keyBeforeFnDoesNotTaintNextTap() {
        var g = FnGesture()
        _ = g.handle(.otherKeyDown(keyCode: 0))
        _ = g.handle(down(1))
        #expect(g.handle(up(1.1)) == .consumeAndSwitch)
    }

    @Test func longPressIgnoredWhenCancelOff() {
        var g = FnGesture()
        _ = g.handle(down())
        #expect(g.handle(up(2.0)) == .consumeAndSwitch)
    }

    @Test func longPressCancelsWhenOn() {
        var g = FnGesture()
        g.cancelOnLongPress = true
        _ = g.handle(down())
        #expect(g.handle(up(0.49)) == .consumeAndSwitch)
        _ = g.handle(down(10))
        #expect(g.handle(up(10.5)) == .consume)
        _ = g.handle(down(20))
        #expect(g.handle(up(21)) == .consume)
    }

    @Test func strayUpPasses() {
        var g = FnGesture()
        #expect(g.handle(up(1)) == .pass)
    }

    @Test func doubleDownSwitchesOnce() {
        var g = FnGesture()
        _ = g.handle(down(0))
        #expect(g.handle(down(0.05)) == .pass)
        #expect(g.handle(up(0.1)) == .consumeAndSwitch)
        #expect(g.handle(up(0.2)) == .pass)
    }

    @Test func resetClearsState() {
        var g = FnGesture()
        _ = g.handle(down())
        #expect(g.handle(.reset) == .pass)
        #expect(g.isFnDown == false)
        #expect(g.handle(up(0.1)) == .pass)
    }

    @Test func repeatedTapsEachSwitch() {
        var g = FnGesture()
        _ = g.handle(down(0))
        #expect(g.handle(up(0.1)) == .consumeAndSwitch)
        _ = g.handle(down(0.2))
        #expect(g.handle(up(0.3)) == .consumeAndSwitch)
    }

    @Test func thresholdValue() {
        #expect(FnGesture.longPressThreshold == 0.5)
    }
}
