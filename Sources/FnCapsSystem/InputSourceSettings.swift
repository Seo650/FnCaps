import AppKit
import os

/// 「입력 소스 추가…」(D-36)의 목적지: 시스템 설정 > 키보드 > 입력 소스.
///
/// 앵커 조사(읽기 전용, 2026-11-07, macOS 27.2, 시스템 설정은 열지 않음):
/// - `ls /System/Library/ExtensionKit/Extensions | grep -i keyboard` → KeyboardSettings.appex, KeyboardSettingsIntents.appex
/// - `plutil -p KeyboardSettings.appex/Contents/Info.plist` → CFBundleIdentifier com.apple.Keyboard-Settings.extension,
///   allowsXAppleSystemPreferencesURLScheme = true
/// - `strings KeyboardSettings` → InputSourceView, InputSourceSheetView 등(앵커 문자열 「InputSources」 단독은 없음)
/// - `plutil -p Resources/en.lproj/Keyboard.searchTerms` 최상위 키 → InputSources("Keyboard layouts",
///   "Show input menu in menu bar" …), CapsLockInputSources, Shortcuts, Dictation 등
/// 고른 주소: `x-apple.systempreferences:com.apple.Keyboard-Settings.extension?InputSources`.
/// 확인 안 됨: 실제로 입력 소스 화면(또는 그 시트)이 열리는지. 04-09 실기기 확인으로 넘긴다.
/// NSWorkspace.open의 true는 「주소를 넘겼다」는 뜻일 뿐이라 후보 고르기에 쓰지 않는다.
public enum InputSourceSettings {
    static let anchored = "x-apple.systempreferences:com.apple.Keyboard-Settings.extension?InputSources"
    static let keyboard = "x-apple.systempreferences:com.apple.Keyboard-Settings.extension"
    private static let log = Logger(subsystem: "io.github.seo650.fncaps", category: "settings")

    @discardableResult
    public static func open() -> Bool {
        if let url = URL(string: anchored), NSWorkspace.shared.open(url) { return true }
        log.info("input source settings anchor open returned false; falling back to keyboard pane")
        guard let url = URL(string: keyboard) else { return false }
        return NSWorkspace.shared.open(url)
    }

    /// 시스템 설정 > 키보드 첫 화면(「🌐 키를 누르면」 항목이 있는 곳)을 연다.
    @discardableResult
    public static func openKeyboard() -> Bool {
        guard let url = URL(string: keyboard) else { return false }
        return NSWorkspace.shared.open(url)
    }
}
