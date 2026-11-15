import Testing
@testable import FnCapsCore

private let ctrl: UInt64 = 0x40000
private let opt: UInt64 = 0x80000
private let shift: UInt64 = 0x20000
private let cmd: UInt64 = 0x100000

/// D-46 「지정 단축키」의 순수 규칙: 조합 판정(빼앗기), 끄기 판정, 시스템 조합 집합,
/// 탭 맞춤 상태 기계, 표시 글자.
@Suite struct AssignedShortcutChordTests {
    // MARK: ChordValidation

    @Test func singleModifierChordsAccepted() {
        // D-46: 수정 키 하나만 있어도 받는다(연구 §3-3의 「둘 이상」 권고는 채택하지 않음).
        for flags in [ctrl, opt, cmd, shift, ctrl | opt] {
            let result = ChordValidation.validate(
                keyCode: 38, flags: flags, for: "R", existing: [:], reservedKeyCode: 79)
            #expect(result == .accepted(KeyChord(keyCode: 38, modifiers: flags), takenFrom: nil))
        }
    }

    @Test func noModifierRefused() {
        let none = ChordValidation.validate(keyCode: 38, flags: 0, for: "R", existing: [:], reservedKeyCode: nil)
        #expect(none == .refused(.noModifier))
        // ⇪(0x10000)와 fn(0x800000)은 수정 키 비트가 아니다.
        let caps = ChordValidation.validate(keyCode: 38, flags: 0x10000, for: "R", existing: [:], reservedKeyCode: nil)
        #expect(caps == .refused(.noModifier))
        let fn = ChordValidation.validate(keyCode: 38, flags: 0x800000, for: "R", existing: [:], reservedKeyCode: nil)
        #expect(fn == .refused(.noModifier))
    }

    @Test func modifierKeyCodesAndGlobeRefused() {
        // ⌘ 54/55, ⇧ 56/60, ⇪ 57, ⌥ 58/61, ⌃ 59/62, fn 63, 🌐 179.
        for keyCode in [54, 55, 56, 57, 58, 59, 60, 61, 62, 63, 179] as [UInt16] {
            let result = ChordValidation.validate(
                keyCode: keyCode, flags: ctrl, for: "R", existing: [:], reservedKeyCode: nil)
            #expect(result == .refused(.notAKey), "keyCode \(keyCode)")
        }
    }

    @Test func reservedCapsFKeyRefused() {
        // Caps용으로 쓰는 F 키(보통 F18 79)는 단축키로 받지 않는다.
        let result = ChordValidation.validate(keyCode: 79, flags: ctrl, for: "R", existing: [:], reservedKeyCode: 79)
        #expect(result == .refused(.notAKey))
    }

    @Test func allCapsCandidateFKeysRefused() {
        // IN-03: Caps 키는 나중에 다른 후보로 바뀔 수 있으므로 후보 전부를 거절한다.
        for keyCode in CapsKey.candidates.map({ UInt16($0.keyCode) }) {
            let result = ChordValidation.validate(
                keyCode: keyCode, flags: ctrl, for: "R", existing: [:], reservedKeyCode: nil)
            #expect(result == .refused(.notAKey), "keyCode \(keyCode)")
        }
        let plain = ChordValidation.validate(keyCode: 0x00, flags: ctrl, for: "R", existing: [:], reservedKeyCode: nil)
        #expect(plain == .accepted(KeyChord(keyCode: 0x00, modifiers: ctrl), takenFrom: nil))
    }

    @Test func validateReportsTakenFromOtherSource() {
        // W4 「겹침은 막지 않는다」: 거절하지 않고 가져올 소스를 알린다.
        let chord = KeyChord(keyCode: 38, modifiers: ctrl | opt)
        let result = ChordValidation.validate(
            keyCode: 38, flags: ctrl | opt, for: "R", existing: ["V": chord], reservedKeyCode: nil)
        #expect(result == .accepted(chord, takenFrom: "V"))
    }

    @Test func sameSourceChordIsNotTakenFromItself() {
        let chord = KeyChord(keyCode: 38, modifiers: ctrl)
        let result = ChordValidation.validate(
            keyCode: 38, flags: ctrl, for: "R", existing: ["R": chord], reservedKeyCode: nil)
        #expect(result == .accepted(chord, takenFrom: nil))
    }

    @Test func blocksTypingForShiftAndOptionAlone() {
        #expect(ChordValidation.blocksTyping(KeyChord(keyCode: 38, modifiers: shift)))
        // IN-04: ⌥ 하나뿐인 조합도 ⌥로 치는 특수 문자·죽은 키를 가로챈다.
        #expect(ChordValidation.blocksTyping(KeyChord(keyCode: 38, modifiers: opt)))
        #expect(ChordValidation.blocksTyping(KeyChord(keyCode: 38, modifiers: opt | shift)))
    }

    @Test func blocksTypingFalseForOtherCombos() {
        #expect(!ChordValidation.blocksTyping(KeyChord(keyCode: 38, modifiers: 0)))
        #expect(!ChordValidation.blocksTyping(KeyChord(keyCode: 38, modifiers: ctrl)))
        #expect(!ChordValidation.blocksTyping(KeyChord(keyCode: 38, modifiers: cmd)))
        #expect(!ChordValidation.blocksTyping(KeyChord(keyCode: 38, modifiers: ctrl | shift)))
        #expect(!ChordValidation.blocksTyping(KeyChord(keyCode: 38, modifiers: opt | cmd)))
    }

    @Test func blocksTypingFalseForKeysThatTypeNothing() {
        // IN-05: ⌥·⇧ + 방향키·기능 키·Return 등은 글자를 내지 않으므로 알리지 않는다.
        for keyCode: UInt16 in [123, 124, 125, 126, 122, 96, 36, 48, 51, 53, 115, 121] {
            #expect(!ChordValidation.blocksTyping(KeyChord(keyCode: keyCode, modifiers: opt)))
            #expect(!ChordValidation.blocksTyping(KeyChord(keyCode: keyCode, modifiers: shift)))
            #expect(!ChordValidation.blocksTyping(KeyChord(keyCode: keyCode, modifiers: opt | shift)))
        }
        // Space는 ⌥로 줄 바꿈 없는 공백을 내므로 알린다.
        #expect(ChordValidation.blocksTyping(KeyChord(keyCode: 49, modifiers: opt)))
    }

    // MARK: AssignedShortcutPolicy

    @Test func isActiveTrueWhenEnabledAndAppOn() {
        #expect(AssignedShortcutPolicy.isActive(enabled: true, appOff: false))
    }

    @Test func isActiveFalseWhenAppOff() {
        #expect(!AssignedShortcutPolicy.isActive(enabled: true, appOff: true))
    }

    @Test func isActiveFalseWhenDisabled() {
        #expect(!AssignedShortcutPolicy.isActive(enabled: false, appOff: false))
        #expect(!AssignedShortcutPolicy.isActive(enabled: false, appOff: true))
    }

    // MARK: SystemChordSet

    @Test func systemChordSetMapsCarbonModifiers() {
        // Carbon ⌘ 0x100, ⇧ 0x200, ⌥ 0x800, ⌃ 0x1000만 CGEventFlags 비트로 바꾼다.
        let set = SystemChordSet(carbonEntries: [
            (49, 0x100, true), (50, 0x200, true), (51, 0x800, true), (52, 0x1000, true),
        ])
        #expect(set.contains(KeyChord(keyCode: 49, modifiers: cmd)))
        #expect(set.contains(KeyChord(keyCode: 50, modifiers: shift)))
        #expect(set.contains(KeyChord(keyCode: 51, modifiers: opt)))
        #expect(set.contains(KeyChord(keyCode: 52, modifiers: ctrl)))
        #expect(!set.contains(KeyChord(keyCode: 49, modifiers: 0)))
    }

    @Test func systemChordSetSkipsDisabledAndDropsFnBit() {
        // 꺼진 항목은 넣지 않는다. F 키·화살표의 fn 표시 비트(0x20000)는 남기지 않는다.
        let set = SystemChordSet(carbonEntries: [
            (49, 0x100, false), (79, 0x20000, true),
        ])
        #expect(!set.contains(KeyChord(keyCode: 49, modifiers: cmd)))
        #expect(set.contains(KeyChord(keyCode: 79, modifiers: 0)))
        #expect(!set.contains(KeyChord(keyCode: 79, modifiers: 0x20000)))
    }

    @Test func systemChordSetIncludesExtraChords() {
        // #60을 바꾼 동안 시스템 목록에 없는 입력 소스 조합(원래 #60, ⌃⌥Space)을 넣는 자리.
        let set = SystemChordSet(
            carbonEntries: [(49, 0x100, true)],
            extraChords: [KeyChord(keyCode: 49, modifiers: ctrl), KeyChord(keyCode: 49, modifiers: ctrl | opt)])
        #expect(set.contains(KeyChord(keyCode: 49, modifiers: ctrl)))
        #expect(set.contains(KeyChord(keyCode: 49, modifiers: ctrl | opt)))
        #expect(set.contains(KeyChord(keyCode: 49, modifiers: cmd)))
    }

    // MARK: ShortcutMatcher

    private let jChord = KeyChord(keyCode: 38, modifiers: ctrl | opt)

    @Test func matcherSwitchesAndSwallowsPairKeyUp() {
        var m = ShortcutMatcher(table: [jChord: "R"])
        #expect(m.handle(isDown: true, keyCode: 38, flags: ctrl | opt, autorepeat: false) == .switchTo("R"))
        #expect(m.handle(isDown: false, keyCode: 38, flags: ctrl | opt, autorepeat: false) == .swallow)
        // 짝 keyUp은 한 번만 삼킨다.
        #expect(m.handle(isDown: false, keyCode: 38, flags: 0, autorepeat: false) == .pass)
    }

    @Test func matcherRequiresExactModifierMatch() {
        var m = ShortcutMatcher(table: [jChord: "R"])
        #expect(m.handle(isDown: true, keyCode: 38, flags: ctrl | opt | shift, autorepeat: false) == .pass)
        #expect(m.handle(isDown: true, keyCode: 39, flags: ctrl | opt, autorepeat: false) == .pass)
    }

    @Test func matcherIgnoresCapsLockBit() {
        var m = ShortcutMatcher(table: [jChord: "R"])
        #expect(m.handle(isDown: true, keyCode: 38, flags: ctrl | opt | 0x10000, autorepeat: false) == .switchTo("R"))
    }

    @Test func matcherPausedPassesButStillSwallowsPendingKeyUp() {
        var m = ShortcutMatcher(table: [jChord: "R"])
        _ = m.handle(isDown: true, keyCode: 38, flags: ctrl | opt, autorepeat: false)
        m.paused = true
        #expect(m.handle(isDown: false, keyCode: 38, flags: 0, autorepeat: false) == .swallow)
        #expect(m.handle(isDown: true, keyCode: 38, flags: ctrl | opt, autorepeat: false) == .pass)
    }

    @Test func matcherAutorepeatSwallowsWithoutSecondSwitch() {
        var m = ShortcutMatcher(table: [jChord: "R"])
        _ = m.handle(isDown: true, keyCode: 38, flags: ctrl | opt, autorepeat: false)
        #expect(m.handle(isDown: true, keyCode: 38, flags: ctrl | opt, autorepeat: true) == .swallow)
    }

    @Test func matcherResetForgetsSwallowedKey() {
        var m = ShortcutMatcher(table: [jChord: "R"])
        _ = m.handle(isDown: true, keyCode: 38, flags: ctrl | opt, autorepeat: false)
        m.reset()
        #expect(m.handle(isDown: false, keyCode: 38, flags: ctrl | opt, autorepeat: false) == .pass)
    }

    // MARK: ChordFormatter

    private func name(_ s: String?) -> (UInt16) -> String? { { _ in s } }

    @Test func formatterModifierOrderAndUppercase() {
        let chord = KeyChord(keyCode: 38, modifiers: ctrl | opt | shift | cmd)
        #expect(ChordFormatter.text(chord, keyName: name("j")) == "⌃⌥⇧⌘J")
        #expect(ChordFormatter.text(KeyChord(keyCode: 38, modifiers: opt), keyName: name("j")) == "⌥J")
        #expect(ChordFormatter.modifierText(shift | cmd) == "⇧⌘")
    }

    @Test func formatterSpecialKeys() {
        #expect(ChordFormatter.text(KeyChord(keyCode: 49, modifiers: cmd), keyName: name(" ")) == "⌘␣")
        #expect(ChordFormatter.text(KeyChord(keyCode: 36, modifiers: shift), keyName: name("x")) == "⇧↩")
        #expect(ChordFormatter.text(KeyChord(keyCode: 48, modifiers: ctrl), keyName: name("x")) == "⌃⇥")
        #expect(ChordFormatter.text(KeyChord(keyCode: 51, modifiers: cmd), keyName: name("x")) == "⌘⌫")
        #expect(ChordFormatter.text(KeyChord(keyCode: 53, modifiers: opt), keyName: name("x")) == "⌥⎋")
        #expect(ChordFormatter.text(KeyChord(keyCode: 123, modifiers: ctrl), keyName: name("x")) == "⌃←")
        #expect(ChordFormatter.text(KeyChord(keyCode: 126, modifiers: ctrl), keyName: name("x")) == "⌃↑")
    }

    @Test func formatterFunctionKeys() {
        #expect(ChordFormatter.text(KeyChord(keyCode: 122, modifiers: ctrl), keyName: name("x")) == "⌃F1")
        #expect(ChordFormatter.text(KeyChord(keyCode: 79, modifiers: ctrl), keyName: name("x")) == "⌃F18")
        #expect(ChordFormatter.text(KeyChord(keyCode: 90, modifiers: opt), keyName: name("x")) == "⌥F20")
    }

    @Test func formatterNilKeyNameShowsKeyCode() {
        #expect(ChordFormatter.text(KeyChord(keyCode: 38, modifiers: ctrl), keyName: name(nil)) == "⌃#38")
    }
}
