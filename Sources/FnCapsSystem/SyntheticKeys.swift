import CoreGraphics
import Foundation
import FnCapsCore

/// Marker written to `eventSourceUserData` of every event FnCaps posts, so later taps can ignore them. (ASCII "FNCP").
public let fncapsEventMarker: Int64 = 0x464E4350

/// Posts synthetic keyboard events. Posting requires the Accessibility grant of the running bundle.
public enum SyntheticKeys {
    public static func post(keyCode: CGKeyCode, flags: CGEventFlags = [], down: Bool) {
        let source = CGEventSource(stateID: .hidSystemState)
        guard let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: down) else { return }
        event.flags = flags
        event.setIntegerValueField(.eventSourceUserData, value: fncapsEventMarker)
        event.post(tap: .cghidEventTap)
    }

    public static func tap(keyCode: CGKeyCode, flags: CGEventFlags = []) {
        post(keyCode: keyCode, flags: flags, down: true)
        post(keyCode: keyCode, flags: flags, down: false)
    }

    public static func postFlagsChanged(keyCode: CGKeyCode, flags: CGEventFlags) {
        let source = CGEventSource(stateID: .hidSystemState)
        guard let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true) else { return }
        event.type = .flagsChanged
        event.flags = flags
        event.setIntegerValueField(.eventSourceUserData, value: fncapsEventMarker)
        event.post(tap: .cghidEventTap)
    }

    /// Posts a symbolic-hotkey chord. `explicitModifiers`: flagsChanged for each modifier (flags accumulate),
    /// key down/up with full flags, then flagsChanged back to empty. Otherwise key down/up carry flags only.
    public static func postHotkey(keyCode: CGKeyCode, modifierMask: UInt64, explicitModifiers: Bool) {
        let full = CGEventFlags(rawValue: modifierMask)
        guard explicitModifiers else {
            tap(keyCode: keyCode, flags: full)
            return
        }
        // Review M-04: restore the modifiers the user physically holds.
        let held = CGEventSource.flagsState(.hidSystemState).rawValue
        for e in HotkeyChord.plan(keyCode: UInt16(keyCode), modifierMask: modifierMask, held: held) {
            switch e.kind {
            case .flags: postFlagsChanged(keyCode: CGKeyCode(e.keyCode), flags: CGEventFlags(rawValue: e.flags))
            case .keyDown: post(keyCode: CGKeyCode(e.keyCode), flags: CGEventFlags(rawValue: e.flags), down: true)
            case .keyUp: post(keyCode: CGKeyCode(e.keyCode), flags: CGEventFlags(rawValue: e.flags), down: false)
            }
        }
    }
}
