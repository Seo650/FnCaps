import CoreGraphics
import Testing
@testable import FnCapsSystem

/// 다시 내보내는 키가 게시 시점의 대문자 잠금 값을 싣는 규칙의 회귀 시험(T-03-14).
/// 만든 CGEvent는 게시하지 않는다.
@Suite struct FnTapReplayTests {
    private func event(flags: CGEventFlags = [], keyCode: CGKeyCode = 0) -> CGEvent {
        let e = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true)!
        e.flags = flags
        return e
    }

    @Test func lockOnSetsAlphaShift() {
        let e = event()
        FnTap.stampReplay(e, capsOn: true)
        #expect(e.flags.contains(.maskAlphaShift))
    }

    @Test func lockOffClearsStaleAlphaShift() {
        let e = event(flags: .maskAlphaShift)
        FnTap.stampReplay(e, capsOn: false)
        #expect(!e.flags.contains(.maskAlphaShift))
    }

    @Test func nilLeavesFlagsAsTheyWere() {
        let on = event(flags: .maskAlphaShift)
        FnTap.stampReplay(on, capsOn: nil)
        #expect(on.flags.contains(.maskAlphaShift))
        let off = event(flags: .maskShift)
        FnTap.stampReplay(off, capsOn: nil)
        #expect(!off.flags.contains(.maskAlphaShift))
    }

    @Test func otherFlagsAndKeycodeAreKept() {
        let e = event(flags: [.maskShift, .maskSecondaryFn, .maskAlphaShift], keyCode: 40)
        FnTap.stampReplay(e, capsOn: false)
        #expect(e.flags.contains(.maskShift))
        #expect(e.flags.contains(.maskSecondaryFn))
        #expect(e.getIntegerValueField(.keyboardEventKeycode) == 40)
        let f = event(flags: .maskShift, keyCode: 12)
        FnTap.stampReplay(f, capsOn: true)
        #expect(f.flags.contains(.maskShift))
        #expect(f.flags.contains(.maskAlphaShift))
        #expect(f.getIntegerValueField(.keyboardEventKeycode) == 12)
    }

    @Test func replayMarkerIsAlwaysSet() {
        for capsOn in [true, false, nil] as [Bool?] {
            let e = event()
            FnTap.stampReplay(e, capsOn: capsOn)
            #expect(e.getIntegerValueField(.eventSourceUserData) == fncapsReplayMarker)
        }
    }

    @Test func nextCapsOnReadsFlagsFromKeyEvents() {
        for t in [CGEventType.keyDown, .keyUp, .flagsChanged] {
            #expect(FnTap.nextCapsOn(current: nil, type: t, flags: .maskAlphaShift) == true)
            #expect(FnTap.nextCapsOn(current: true, type: t, flags: []) == false)
        }
    }

    @Test func nextCapsOnKeepsValueForMouseAndSystemDefined() {
        let sysDefined = CGEventType(rawValue: 14)!
        for t in [CGEventType.leftMouseDown, .rightMouseDown, .otherMouseDown, sysDefined] {
            #expect(FnTap.nextCapsOn(current: true, type: t, flags: []) == true)
            #expect(FnTap.nextCapsOn(current: false, type: t, flags: .maskAlphaShift) == false)
            #expect(FnTap.nextCapsOn(current: nil, type: t, flags: .maskAlphaShift) == nil)
        }
    }

    @Test func bypassesFnWhenDisabled() {
        #expect(FnTap.bypassesFn(type: .flagsChanged, keycode: 63, fnEnabled: false))
        #expect(FnTap.bypassesFn(type: .keyDown, keycode: 179, fnEnabled: false))
        #expect(FnTap.bypassesFn(type: .keyUp, keycode: 179, fnEnabled: false))
    }

    @Test func bypassesFnNeverWhenEnabled() {
        #expect(!FnTap.bypassesFn(type: .flagsChanged, keycode: 63, fnEnabled: true))
        #expect(!FnTap.bypassesFn(type: .keyDown, keycode: 179, fnEnabled: true))
    }

    @Test func bypassesFnIgnoresOtherKeys() {
        #expect(!FnTap.bypassesFn(type: .keyDown, keycode: 0, fnEnabled: false))
        #expect(!FnTap.bypassesFn(type: .flagsChanged, keycode: 57, fnEnabled: false))
    }
}
