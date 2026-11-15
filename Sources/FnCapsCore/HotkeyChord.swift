import Foundation

public struct ChordEvent: Equatable, Sendable {
    public enum Kind: Equatable, Sendable { case flags, keyDown, keyUp }
    public var kind: Kind
    public var keyCode: UInt16
    public var flags: UInt64

    public init(kind: Kind, keyCode: UInt16, flags: UInt64) {
        self.kind = kind
        self.keyCode = keyCode
        self.flags = flags
    }
}

/// Pure event plan for posting a symbolic-hotkey chord.
/// Review M-04: the chord must end with the modifiers the user is physically holding
/// (captured before posting), not with every modifier cleared.
public enum HotkeyChord {
    /// Control 59, Option 58, Shift 56, Command 55 (raw CGEventFlags bits).
    public static let table: [(keyCode: UInt16, bit: UInt64)] = [
        (59, 0x40000), (58, 0x80000), (56, 0x20000), (55, 0x100000),
    ]
    public static let modifierBits: UInt64 = table.reduce(0) { $0 | $1.bit }

    public static func plan(keyCode: UInt16, modifierMask: UInt64, held: UInt64) -> [ChordEvent] {
        let mask = modifierMask & modifierBits
        let heldBits = held & modifierBits
        var events: [ChordEvent] = []
        var state: UInt64 = 0
        let present = table.filter { mask & $0.bit != 0 }
        for m in present {
            state |= m.bit
            events.append(ChordEvent(kind: .flags, keyCode: m.keyCode, flags: state))
        }
        events.append(ChordEvent(kind: .keyDown, keyCode: keyCode, flags: modifierMask))
        events.append(ChordEvent(kind: .keyUp, keyCode: keyCode, flags: modifierMask))
        for m in present.reversed() where heldBits & m.bit == 0 {
            state &= ~m.bit
            events.append(ChordEvent(kind: .flags, keyCode: m.keyCode, flags: state))
        }
        for m in table where heldBits & m.bit != 0 && state & m.bit == 0 {
            state |= m.bit
            events.append(ChordEvent(kind: .flags, keyCode: m.keyCode, flags: state))
        }
        return events
    }
}
