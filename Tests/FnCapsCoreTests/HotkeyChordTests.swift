import Testing
@testable import FnCapsCore
@testable import FnCapsSystem

@Suite struct HotkeyChordTests {
    static let ctrl: UInt64 = 0x40000
    static let shift: UInt64 = 0x20000
    static let option: UInt64 = 0x80000
    static let cmd: UInt64 = 0x100000
    static let bits: [UInt64] = [ctrl, option, shift, cmd]

    /// Modifier state after replaying a plan (flags events set the state; key events ignored).
    static func finalState(_ plan: [ChordEvent], start: UInt64) -> UInt64 {
        var s = start
        for e in plan where e.kind == .flags { s = e.flags }
        return s
    }

    @Test func nothingHeldMatchesLegacySequence() {
        let p = HotkeyChord.plan(keyCode: 49, modifierMask: Self.ctrl, held: 0)
        #expect(p == [
            ChordEvent(kind: .flags, keyCode: 59, flags: Self.ctrl),
            ChordEvent(kind: .keyDown, keyCode: 49, flags: Self.ctrl),
            ChordEvent(kind: .keyUp, keyCode: 49, flags: Self.ctrl),
            ChordEvent(kind: .flags, keyCode: 59, flags: 0),
        ])
    }

    @Test func heldShiftIsRestored() {
        let p = HotkeyChord.plan(keyCode: 49, modifierMask: Self.ctrl, held: Self.shift)
        #expect(p.suffix(2) == [
            ChordEvent(kind: .flags, keyCode: 59, flags: 0),
            ChordEvent(kind: .flags, keyCode: 56, flags: Self.shift),
        ])
        for e in p where e.kind != .flags { #expect(e.flags == Self.ctrl) }
    }

    @Test func heldSameModifierNotReleased() {
        let p = HotkeyChord.plan(keyCode: 49, modifierMask: Self.ctrl, held: Self.ctrl)
        #expect(Self.finalState(p, start: Self.ctrl) == Self.ctrl)
        #expect(p.last?.flags == Self.ctrl)
        #expect(!p.contains { $0.kind == .flags && $0.keyCode == 59 && $0.flags == 0 })
    }

    @Test func noModifiersNothingHeld() {
        let p = HotkeyChord.plan(keyCode: 49, modifierMask: 0, held: 0)
        #expect(p == [
            ChordEvent(kind: .keyDown, keyCode: 49, flags: 0),
            ChordEvent(kind: .keyUp, keyCode: 49, flags: 0),
        ])
    }

    @Test func exhaustiveFinalStateEqualsHeld() {
        for h in 0..<16 {
            for k in 0..<16 {
                var held: UInt64 = 0, mask: UInt64 = 0
                for i in 0..<4 {
                    if h & (1 << i) != 0 { held |= Self.bits[i] }
                    if k & (1 << i) != 0 { mask |= Self.bits[i] }
                }
                let p = HotkeyChord.plan(keyCode: 49, modifierMask: mask, held: held)
                #expect(Self.finalState(p, start: held) == held)
                for e in p where e.kind != .flags { #expect(e.flags == mask) }
            }
        }
    }

    @Test func extraBitsOfHeldIgnored() {
        let p = HotkeyChord.plan(keyCode: 49, modifierMask: Self.ctrl, held: 0x800000)
        #expect(Self.finalState(p, start: 0) == 0)
    }

    @Test func hotkeyStatus() {
        #expect(SymbolicHotkeyReader.status(of: nil) == .missing)
        let off = SymbolicHotkey(enabled: false, ascii: 32, keyCode: 49, modifierMask: 0)
        #expect(SymbolicHotkeyReader.status(of: off) == .disabled)
        for kc in [65535, -1, 128] {
            let hk = SymbolicHotkey(enabled: true, ascii: 65535, keyCode: kc, modifierMask: 0)
            #expect(SymbolicHotkeyReader.status(of: hk) == .unassigned(keyCode: kc))
        }
        let ok = SymbolicHotkey(enabled: true, ascii: 32, keyCode: 49, modifierMask: Self.ctrl)
        #expect(SymbolicHotkeyReader.status(of: ok) == .usable(ok))
    }

    @Test func hotkeyNotes() {
        #expect(HotkeyStatus.missing.note(id: 60) == "hotkey60_missing")
        #expect(HotkeyStatus.disabled.note(id: 60) == "hotkey60_disabled")
        #expect(HotkeyStatus.unassigned(keyCode: 65535).note(id: 60) == "hotkey60_unassigned(keyCode=65535)")
    }
}
