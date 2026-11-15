// 구조 참고: sindresorhus/KeyboardShortcuts Shortcut.swift(MIT), 코드 복사 없음 (04-RESEARCH-SHORTCUTS §2-4, §4)
import AppKit
import Carbon
import Foundation
import FnCapsCore

/// 시스템 기호 단축키 읽기(Carbon). 값은 읽기만 하고 쓰지 않는다(T-04-69).
public enum SystemHotkeys {
    /// 켜진 시스템 기호 단축키 집합에 FnCaps가 목록에서 숨긴 입력 소스 조합을 더해 돌려준다.
    /// 이 Carbon 함수는 자주 부르지 말라고 문서에 적혀 있으므로(연구 §3-1),
    /// 부르는 곳은 녹화 확정과 설정 창 열기뿐이다.
    public static func enabledChords() -> SystemChordSet {
        SystemChordSet(carbonEntries: entries(), extraChords: extraChords())
    }

    private static func entries() -> [(keyCode: Int, carbonModifiers: Int, enabled: Bool)] {
        var array: Unmanaged<CFArray>?
        guard CopySymbolicHotKeys(&array) == noErr, let array else { return [] }
        var out: [(keyCode: Int, carbonModifiers: Int, enabled: Bool)] = []
        for case let dict as NSDictionary in (array.takeRetainedValue() as NSArray) {
            guard let code = dict[kHISymbolicHotKeyCode as String] as? NSNumber,
                let modifiers = dict[kHISymbolicHotKeyModifiers as String] as? NSNumber
            else { continue }
            let enabled = (dict[kHISymbolicHotKeyEnabled as String] as? NSNumber)?.boolValue ?? false
            out.append((code.intValue, modifiers.intValue, enabled))
        }
        return out
    }

    /// FnCaps가 #60을 F18로 바꿔 둔 동안 시스템 목록에는 원래 조합이 없다. 백업해 둔 원래 #60
    /// (읽기만, 없으면 ⌃Space)과 #61 기본값 ⌃⌥Space를 더한다(W5, 연구 §3-3).
    private static func extraChords() -> [KeyChord] {
        let original =
            ShortcutManager.originalChord(defaults: .standard)
            ?? KeyChord(keyCode: 49, modifiers: 0x40000)
        return [original, KeyChord(keyCode: 49, modifiers: 0x40000 | 0x80000)]
    }
}

/// 키코드의 표시 글자(연구 §4). 메인 스레드 전용.
/// 한국어·일본어 입력기 소스에는 UCHR이 없으므로 지금 소스가 아니라 ASCII 가능 자판에서 읽는다.
public enum KeyNames {
    /// 대문자 한 글자. 공백·제어 문자면 nil.
    public static func character(for keyCode: UInt16) -> String? {
        dispatchPrecondition(condition: .onQueue(.main))
        guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
            let ptr = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(ptr).takeUnretainedValue() as Data
        return data.withUnsafeBytes { raw -> String? in
            guard let layout = raw.bindMemory(to: UCKeyboardLayout.self).baseAddress else { return nil }
            var deadKeyState: UInt32 = 0
            var length = 0
            var chars = [UniChar](repeating: 0, count: 4)
            let status = UCKeyTranslate(
                layout, keyCode, UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeyState, chars.count, &length, &chars)
            guard status == noErr, length > 0 else { return nil }
            let text = String(utf16CodeUnits: chars, count: length)
            guard text.unicodeScalars.count == 1, let scalar = text.unicodeScalars.first,
                !CharacterSet.whitespacesAndNewlines.contains(scalar),
                !CharacterSet.controlCharacters.contains(scalar)
            else { return nil }
            return text.uppercased()
        }
    }
}
