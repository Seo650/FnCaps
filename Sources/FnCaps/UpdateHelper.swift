import Foundation
import FnCapsCore

/// 앱 안 업데이트(D-08)의 도우미 모드. 새 앱으로 띄운 같은 실행 파일이 부모 종료를 기다렸다가
/// 설치본을 교체하고, 새 앱이 영수증에 자기 pid를 쓰는지로 성공을 판정한다.
/// 이 파일은 앱 객체·매핑 코드를 만들거나 부르지 않는다(RESEARCH Pitfall 5, T-05-13).
enum UpdateHelper {
    static let argument = "--install-update"

    /// 부모 종료 대기 60초, 영수증 대기 20초, 살아 있음 확인 2초(T-05-12).
    static let parentWaitLimit: TimeInterval = 60
    static let receiptLimit: TimeInterval = 20
    static let stabilityLimit: TimeInterval = 2
    private static let pollInterval: TimeInterval = 0.1

    /// 종료 코드: 0 설치, 1 되돌림, 64 인자, 65 작업 경로 거부, 66 부모 대기 초과, 67 후보 재검사 실패.
    /// 64~67처럼 교체에 닿기 전에 실패해도 결과 표지를 쓰고, 작업 폴더를 지우고, 부모가 이미 종료했으면
    /// 원래 앱을 다시 띄운다. 사용자가 메뉴 막대 앱 없이 남지 않게 한다(05 WR-02).
    static func run(_ arguments: [String]) -> Int32 {
        let installed = Bundle.main.bundlePath
        guard let flag = arguments.firstIndex(of: argument),
              arguments.count == flag + 5 else {
            return abort(64, workspace: nil, parentPid: arguments.last.flatMap { Int32($0) }, installed: installed)
        }
        let version = arguments[flag + 3]
        guard let parentPid = Int32(arguments[flag + 4]) else {
            return abort(64, workspace: nil, parentPid: nil, installed: installed)
        }

        let tempRoot = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().path
        let workspace = URL(fileURLWithPath: arguments[flag + 1]).resolvingSymlinksInPath().path
        let candidate = URL(fileURLWithPath: arguments[flag + 2]).resolvingSymlinksInPath().path

        // 인자는 위조될 수 있다고 본다. 임시 폴더 바로 아래의 작업 폴더와 그 안 FnCaps.app만 받는다(T-05-09).
        // 거부한 경로는 지우지 않는다.
        guard UpdateVerification.isHelperArgumentsSafe(
                  workspace: workspace, candidate: candidate, tempRoot: tempRoot) else {
            return abort(65, workspace: nil, parentPid: parentPid, installed: installed)
        }

        guard waitForExit(parentPid: parentPid) else {
            return abort(66, workspace: workspace, parentPid: parentPid, installed: installed)
        }

        // 설치본은 도우미를 띄운 그 앱이다. 후보를 다시 검사한다(T-05-08, T-05-09, 05 WR-04).
        // 번들 ID 동일, 버전 == 안내한 버전, 설치본보다 새 버전이어야 한다(다운그레이드 거부).
        let candidateBundle = Bundle(url: URL(fileURLWithPath: candidate))
        guard UpdateVerification.installLocationOK(bundlePath: installed),
              let requirement = UpdateSignature.installedRequirement(bundleURL: Bundle.main.bundleURL),
              UpdateSignature.satisfies(URL(fileURLWithPath: candidate), requirement: requirement),
              UpdateVerification.acceptCandidate(
                  installedBundleID: Bundle.main.bundleIdentifier ?? "",
                  candidateBundleID: candidateBundle?.bundleIdentifier,
                  candidateVersion: candidateBundle?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
                  releaseVersion: version,
                  installedVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")
        else {
            return abort(67, workspace: workspace, parentPid: parentPid, installed: installed)
        }

        let outcome = AppReplacement.replace(
            installed: installed, candidate: candidate, token: UUID().uuidString,
            ops: LiveReplacementFileOps(),
            // 복사한 stage를 swap 직전에 다시 검증한다(TOCTOU, 05 WR-03).
            verifyStage: { stage in
                UnpackedTreeCheck.inspect(root: stage) == .ok
                    && UpdateSignature.satisfies(URL(fileURLWithPath: stage), requirement: requirement)
            },
            launchAndConfirm: { launchAndConfirm(installed: $0, workspace: workspace) })

        switch outcome {
        case .installed:
            setMarker("installed")
        case .rolledBack:
            setMarker("rolledBack")
            relaunch(installed: installed)
        case .rollbackFailed:
            setMarker("rollbackFailed")
        }
        AppLog.info("update helper result=\(marker(outcome))")
        try? FileManager.default.removeItem(atPath: workspace)
        if case .installed = outcome { return 0 }
        return 1
    }

    /// 교체에 닿기 전의 실패. 표지를 쓰고, 안전하다고 확인된 작업 폴더만 지우고,
    /// 부모가 이미 종료했으면 원래 앱을 다시 띄운다(부모가 살아 있으면 중복 실행을 만들지 않는다).
    private static func abort(_ code: Int32, workspace: String?, parentPid: Int32?, installed: String) -> Int32 {
        setMarker("rolledBack")
        AppLog.info("update helper abort code=\(code)")
        if let workspace { try? FileManager.default.removeItem(atPath: workspace) }
        if let parentPid, !isRunning(parentPid) { relaunch(installed: installed) }
        return code
    }

    /// 표지를 쓰고 곧바로 디스크에 내린다. 도우미가 바로 종료해도 값이 사라지지 않게 한다(05 IN-03).
    private static func setMarker(_ value: String) {
        UserDefaults.standard.set(value, forKey: UpdateResultMarker.defaultsKey)
        UserDefaults.standard.synchronize()
    }

    // MARK: 실행 확인

    /// 새 설치본을 실행하고 영수증 pid를 기다린다. 영수증이 없거나 곧 죽으면 false(T-05-12).
    private static func launchAndConfirm(installed: String, workspace: String) -> Bool {
        let receipt = workspace + "/" + UpdateAssets.receiptFileName
        try? FileManager.default.removeItem(atPath: receipt)
        guard let executableURL = Bundle(url: URL(fileURLWithPath: installed))?.executableURL else { return false }

        let process = Process()
        process.executableURL = executableURL
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        var environment = ProcessInfo.processInfo.environment
        environment[UpdateReceipt.environmentKey] = receipt
        process.environment = environment
        do { try process.run() } catch { return false }
        let child = process.processIdentifier

        let deadline = Date().addingTimeInterval(receiptLimit)
        while Date() < deadline {
            if receiptPid(at: receipt) == child {
                // 영수증만 쓰고 바로 죽는 경우를 거른다.
                let stable = Date().addingTimeInterval(stabilityLimit)
                while Date() < stable {
                    if !isRunning(child) { break }
                    Thread.sleep(forTimeInterval: pollInterval)
                }
                if isRunning(child) { return true }
                stop(process)
                return false
            }
            if !isRunning(child) { break }
            Thread.sleep(forTimeInterval: pollInterval)
        }
        stop(process)
        return false
    }

    /// 새 앱을 종료시키고 실제로 내려갈 때까지 기다린다(최대 2초, 안 죽으면 SIGKILL).
    /// 두 인스턴스가 겹쳐 Caps 매핑을 서로 지우지 않게, 되돌린 뒤 재실행은 이 뒤에만 한다(05 IN-04).
    private static func stop(_ process: Process) {
        guard process.isRunning else { return }
        process.terminate()
        let deadline = Date().addingTimeInterval(2)
        while process.isRunning, Date() < deadline {
            Thread.sleep(forTimeInterval: pollInterval)
        }
        if process.isRunning {
            kill(process.processIdentifier, SIGKILL)
            let killDeadline = Date().addingTimeInterval(1)
            while process.isRunning, Date() < killDeadline {
                Thread.sleep(forTimeInterval: pollInterval)
            }
        }
    }

    /// 되돌린 뒤에는 원래 앱을 다시 띄운다. 영수증은 기다리지 않는다.
    private static func relaunch(installed: String) {
        guard let executableURL = Bundle(url: URL(fileURLWithPath: installed))?.executableURL else { return }
        let process = Process()
        process.executableURL = executableURL
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
    }

    private static func waitForExit(parentPid: Int32) -> Bool {
        guard parentPid > 0 else { return false }
        let deadline = Date().addingTimeInterval(parentWaitLimit)
        while Date() < deadline {
            if !isRunning(parentPid) { return true }
            Thread.sleep(forTimeInterval: pollInterval)
        }
        return !isRunning(parentPid)
    }

    private static func isRunning(_ pid: Int32) -> Bool {
        pid > 0 && kill(pid, 0) == 0
    }

    private static func receiptPid(at path: String) -> Int32? {
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        return Int32(text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private static func marker(_ outcome: AppReplacement.Result) -> String {
        switch outcome {
        case .installed: return "installed"
        case .rolledBack: return "rolledBack"
        case .rollbackFailed: return "rollbackFailed"
        }
    }
}

/// 새 앱이 자기 pid를 남기는 영수증. 도우미만 이 환경 변수를 자식에게 넣는다(T-05-05).
enum UpdateReceipt {
    static let environmentKey = "FNCAPS_UPDATE_READY"

    /// 시작이 끝난 뒤 한 번 부른다. 환경 변수가 없거나 경로가 안전하지 않으면 아무것도 하지 않는다.
    static func writeIfRequested() {
        guard let path = ProcessInfo.processInfo.environment[environmentKey], !path.isEmpty else { return }
        defer { unsetenv(environmentKey) }
        let resolved = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
        let tempRoot = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().path
        guard UpdateVerification.isReceiptPathSafe(resolved, tempRoot: tempRoot) else { return }
        try? String(getpid()).write(toFile: resolved, atomically: true, encoding: .utf8)
    }
}

/// 업데이트 결과 표지. "installed" | "rolledBack" | "rollbackFailed"(T-05-14).
enum UpdateResultMarker {
    static let defaultsKey = "update.installResult"
}
