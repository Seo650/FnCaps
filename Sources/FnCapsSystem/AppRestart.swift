// 구조 참고: LinearMouse 재시작 (MIT)
import Foundation

/// 현재 프로세스가 끝나기를 기다렸다가 자기 번들을 다시 띄운다(L2).
public enum AppRestart {
    public static let showSettingsArgument = "--show-settings"

    /// 스크립트는 고정 문자열이다. 경로는 환경 변수로만 넘겨 경로 안 글자가 셸 코드가 되지 않게 한다.
    static let script = "while kill -0 \"$PPID\" 2>/dev/null; do /bin/sleep 0.1; done; "
        + "/usr/bin/open \"$BUNDLE_PATH\" --args \(showSettingsArgument)"

    /// 현재 프로세스가 끝나면 자기 번들을 open한다. .app 번들이 아니거나 실행 실패면 false.
    public static func relaunchAfterExit() -> Bool {
        guard let process = makeProcess(bundlePath: Bundle.main.bundlePath) else { return false }
        do { try process.run() } catch { return false }
        return true
    }

    /// .app 번들이 아니면 nil. 실행은 하지 않는다.
    static func makeProcess(bundlePath: String) -> Process? {
        guard bundlePath.hasSuffix(".app") else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script]
        var environment = ProcessInfo.processInfo.environment
        environment["BUNDLE_PATH"] = bundlePath
        process.environment = environment
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        return process
    }
}
