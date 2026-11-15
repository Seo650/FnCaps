import Foundation
import Testing
import FnCapsCore
@testable import FnCapsSystem

/// 읽기 전용 시스템 시험. 시스템 값을 쓰지 않고, 이 Mac이 준 값도 단언하지 않는다.
@Suite(.serialized)
@MainActor
struct AssignedShortcutSystemSmokeTests {
    @Test func systemHotkeysReadWithoutCrash() {
        let set = SystemHotkeys.enabledChords()
        // 늘 더하는 조합(⌃⌥Space)만 확인한다. 나머지 값은 이 Mac의 설정에 따라 달라 단언하지 않는다.
        #expect(set.contains(KeyChord(keyCode: 49, modifiers: 0x40000 | 0x80000)))
    }

    @Test func keyNameIsOneUppercaseLetter() {
        guard let name = KeyNames.character(for: 38) else { return }
        #expect(name.count == 1)
        #expect(name == name.uppercased())
        #expect(name.trimmingCharacters(in: .whitespacesAndNewlines) == name)
    }

    @Test func modifiersOnlyHaveNoCharacter() {
        #expect(KeyNames.character(for: 49) == nil)
    }
}
