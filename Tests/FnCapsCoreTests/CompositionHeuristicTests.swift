import Testing
@testable import FnCapsCore

@Suite struct CompositionHeuristicTests {
    func key(_ code: UInt16, cmd: Bool = false, ctrl: Bool = false, im: Bool = true) -> CompositionHeuristic.Event {
        .keyDown(keyCode: code, command: cmd, control: ctrl, sourceIsInputMethod: im)
    }

    @Test func startsFalse() {
        #expect(CompositionHeuristic().mayBeComposing == false)
    }

    @Test func printableInInputMethodSetsTrue() {
        var h = CompositionHeuristic()
        h.handle(key(40))  // k
        #expect(h.mayBeComposing)
    }

    @Test func printableInKeyboardLayoutStaysFalse() {
        var h = CompositionHeuristic()
        h.handle(key(40, im: false))
        #expect(h.mayBeComposing == false)
    }

    @Test func printableWithCommandOrControlIgnored() {
        var h = CompositionHeuristic()
        h.handle(key(40, cmd: true))
        h.handle(key(40, ctrl: true))
        #expect(h.mayBeComposing == false)
    }

    @Test func clearingEvents() {
        for code: UInt16 in [36, 76, 53] {
            var h = CompositionHeuristic()
            h.handle(key(40))
            h.handle(key(code))
            #expect(h.mayBeComposing == false)
        }
        var h = CompositionHeuristic()
        h.handle(key(40))
        h.handle(.sourceChanged)
        #expect(h.mayBeComposing == false)
    }

    @Test func neutralEventsLeaveStateUnchanged() {
        for code: UInt16 in [49, 51, 48, 123, 124, 125, 126] {
            var h = CompositionHeuristic()
            h.handle(key(code))
            #expect(h.mayBeComposing == false)
            h.handle(key(40))
            h.handle(key(code))
            #expect(h.mayBeComposing)
        }
        var h = CompositionHeuristic()
        h.handle(key(40))
        h.handle(key(0, cmd: true))
        h.handle(key(0, ctrl: true))
        h.handle(.mouseDown)
        #expect(h.mayBeComposing)
    }
}
