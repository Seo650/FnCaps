// 구조 참고: gksdud UpdateInstaller.forgetUnusablePermissions (MIT)
// 사용자가 설정 창 버튼을 눌렀을 때만 부른다. 호출 전에 탭을 먼저 내린다(L6).
import Foundation
import FnCapsCore

/// 이 앱 자신의 권한 기록을 지운다. 고정 경로, 셸 없음, 서비스 2개 고정.
public enum PermissionReset {
    public static let services = ["Accessibility", "PostEvent"]

    private static let executable = "/usr/bin/tccutil"
    private static let attemptTimeout: TimeInterval = 5
    private static let queue = DispatchQueue(label: "io.github.seo650.fncaps.permission-reset", qos: .userInitiated)

    /// 설정 창 버튼에서만 부른다. 메인 밖에서 실행하고 completion은 메인 큐에서 부른다. 인자는 실패한 서비스 이름.
    public static func run(bundleID: String, completion: @escaping ([String]) -> Void) {
        queue.async {
            let failed = resetAll(
                bundleID: bundleID,
                sleep: { Thread.sleep(forTimeInterval: $0) },
                runner: { service, id in
                    runProcess(path: executable, arguments: ["reset", service, id], timeout: attemptTimeout)
                }
            )
            DispatchQueue.main.async { completion(failed) }
        }
    }

    /// 실패한 서비스 이름을 돌려준다. runner와 sleep에 기본값을 두지 않아 시험에서 실제 명령이 돌 수 없다.
    /// 번들 ID를 빼고 명령을 부르면 모든 앱의 기록이 지워지므로, 빈 값이면 아무것도 실행하지 않고 실패로 돌려준다.
    static func resetAll(
        bundleID: String,
        sleep: (TimeInterval) -> Void,
        runner: (_ service: String, _ bundleID: String) -> Bool
    ) -> [String] {
        guard !bundleID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return services }
        return services.filter { service in
            !RetryPolicy.run(sleep: sleep) { runner(service, bundleID) }
        }
    }

    /// 끝날 때까지 호출 스레드를 막으므로 전용 큐에서만 부른다. 시간을 넘기면 terminate하고 실패로 센다.
    static func runProcess(path: String, arguments: [String], timeout: TimeInterval) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        do { try process.run() } catch { return false }
        if finished.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            return false
        }
        return process.terminationStatus == 0
    }
}
