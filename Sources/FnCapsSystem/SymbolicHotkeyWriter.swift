// 구조 참고: gksdud main.swift(#60 쓰기, activateSettings) (MIT)
import Foundation
import FnCapsCore

/// `com.apple.symbolichotkeys`를 읽고 쓰고 반영하는 실제 구현. 시험은 이 값을 참조하지 않는다(T-03-09).
public enum SymbolicHotkeyWriter {
    static let domain = "com.apple.symbolichotkeys" as CFString
    static let key = "AppleSymbolicHotKeys" as CFString
    /// 비공개 경로다. 없으면 #60도 매핑도 쓰지 않는다(A6).
    static let activateSettingsPath =
        "/System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings"
    private static let activateTimeout: TimeInterval = 3
    private static let queue = DispatchQueue(label: "io.github.seo650.fncaps.activate-settings", qos: .userInitiated)

    /// 읽기와 쓰기는 호출 스레드에서, activate는 전용 직렬 큐에서 돌리고 completion은 main에서 부른다.
    public static var live: ShortcutPreferences {
        ShortcutPreferences(
            read: {
                CFPreferencesAppSynchronize(domain)
                // 03-08 WR-10: 키가 없는 계정만 빈 사전으로 시작하고, 사전이 아닌 값은 읽기 실패로 남긴다.
                return ShortcutPreferences.interpret(raw: CFPreferencesCopyAppValue(key, domain))
            },
            write: { all in
                CFPreferencesSetAppValue(key, all as CFDictionary, domain)
                return CFPreferencesAppSynchronize(domain)
            },
            canActivate: { FileManager.default.isExecutableFile(atPath: activateSettingsPath) },
            activate: { done in
                queue.async {
                    // 고정 경로와 고정 인자, 셸 없음, 시간 제한 3초(T-03-06).
                    let ok = PermissionReset.runProcess(
                        path: activateSettingsPath, arguments: ["-u", "-virtualSession"], timeout: activateTimeout)
                    DispatchQueue.main.async { done(ok) }
                }
            })
    }
}
