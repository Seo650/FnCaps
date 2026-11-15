// 구조 참고: gksdud UpdateInstaller.swift (MIT)
import AppKit
import FnCapsCore
import Security

/// 설치본이 만족해야 하는 서명 요건(D-08, DIST-04). 같은 인증서 요건을 통과한 앱만 설치해야
/// 손쉬운 사용 권한 기록(TCC)이 새 바이너리에서도 유지된다(T-05-08).
enum UpdateSignature {
    /// 모든 아키텍처·중첩 코드까지 엄격하게 본다.
    static let strictFlags = SecCSFlags(
        rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate | kSecCSCheckNestedCode)

    /// 설치본의 지정 요건(designated requirement)을 돌려준다. 인증서가 없는 ad-hoc 서명이면 nil(T-05-08).
    static func installedRequirement(bundleURL: URL) -> SecRequirement? {
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(bundleURL as CFURL, SecCSFlags(rawValue: 0), &staticCode) == errSecSuccess,
              let staticCode else { return nil }
        var information: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess,
              let dictionary = information as? [String: Any],
              let certificates = dictionary[kSecCodeInfoCertificates as String] as? [Any],
              !certificates.isEmpty else { return nil }
        var requirement: SecRequirement?
        guard SecCodeCopyDesignatedRequirement(staticCode, SecCSFlags(rawValue: 0), &requirement) == errSecSuccess else { return nil }
        return requirement
    }

    /// 후보가 설치본과 같은 지정 요건을 만족하는지 본다(T-05-08).
    static func satisfies(_ candidate: URL, requirement: SecRequirement) -> Bool {
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(candidate as CFURL, SecCSFlags(rawValue: 0), &staticCode) == errSecSuccess,
              let staticCode else { return false }
        return SecStaticCodeCheckValidity(staticCode, strictFlags, requirement) == errSecSuccess
    }
}

/// 앱 안 업데이트(D-08)의 내려받기·검사·도우미 실행. 모든 검사를 통과해야만 도우미를 띄운다.
/// 화면 문구는 여기 없다(05-03). 로그는 단계와 결과 코드만 남긴다(T-05-11).
final class UpdateInstaller {
    enum Stage: Equatable {
        case downloading
        case verifying
        case installing

        var logName: String {
            switch self {
            case .downloading: return "downloading"
            case .verifying: return "verifying"
            case .installing: return "installing"
            }
        }
    }

    enum Failure: String, Error, Equatable {
        case notInstallable
        case unsignedBuild
        case noAssets
        case download
        case checksum
        case archive
        case signature
        case version
        case helper
    }

    private let owner: String
    private let repo: String
    private let currentVersion: String
    private let session: URLSession

    init(owner: String, repo: String, currentVersion: String, session: URLSession) {
        self.owner = owner
        self.repo = repo
        self.currentVersion = currentVersion
        self.session = session
    }

    /// 설정 창의 「업데이트」에서 부른다. 단계 알림과 completion은 메인에서 부른다.
    /// 성공하면 completion(nil) 뒤 스스로 종료한다. 기존 종료 경로가 UserKeyMapping과 #60을 복원한다(D-08).
    func start(onStage: @escaping @MainActor (Stage) -> Void,
               completion: @escaping @MainActor (Failure?) -> Void) {
        Task.detached(priority: .userInitiated) { [self] in
            var workspace: URL?
            do {
                let (url, requirement) = try Self.preflight()
                workspace = url
                try await install(in: url, requirement: requirement, onStage: onStage)
                await MainActor.run { completion(nil) }
                // 주 큐 작업 안에서 terminate를 부르지 않는다. applicationShouldTerminate가 .terminateLater를
                // 돌려주면 AppKit이 그 자리에서 이벤트 루프를 돌리는데, 주 큐는 재진입해 비워지지 않아
                // 복구 완료·2초 시간 제한 블록이 영영 실행되지 않고 앱이 종료 대기에 멈춘다(05-11 UAT C4).
                // 런루프 블록으로 넘기면 ⌘Q와 같은 자리에서 실행된다.
                CFRunLoopPerformBlock(CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue) {
                    NSApp.terminate(nil)
                }
                CFRunLoopWakeUp(CFRunLoopGetMain())
            } catch let failure as Failure {
                if let workspace { try? FileManager.default.removeItem(at: workspace) }
                await MainActor.run { completion(failure) }
            } catch {
                if let workspace { try? FileManager.default.removeItem(at: workspace) }
                Self.log("precheck", Failure.download.rawValue)
                await MainActor.run { completion(.download) }
            }
        }
    }

    // MARK: 단계

    private func install(in workspace: URL, requirement: SecRequirement,
                         onStage: @escaping @MainActor (Stage) -> Void) async throws {
        let tempRoot = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().path
        let workspacePath = workspace.path

        // (1) 릴리스 자산 두 개를 작업 폴더로 받는다. 확인 화면의 결과를 믿지 않고 다시 읽는다(T-05-01).
        let downloaded = try await runStage(.downloading, fallback: .download, onStage: onStage) {
            let (data, response) = try await self.session.data(
                for: UpdateCheck.request(owner: self.owner, repo: self.repo, appVersion: self.currentVersion))
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  let info = UpdateCheck.parseRelease(data),
                  let assets = UpdateVerification.pickAssets(info, owner: self.owner, repo: self.repo) else {
                throw Failure.noAssets
            }
            let folder = workspace.appendingPathComponent("download", isDirectory: true)
            try FileManager.default.createDirectory(
                at: folder, withIntermediateDirectories: false,
                attributes: [.posixPermissions: 0o700])
            let zip = try await self.download(assets.zip, into: folder, limit: UpdateAssets.maxZipBytes)
            let sums = try await self.download(assets.sums, into: folder, limit: UpdateAssets.maxChecksumBytes)
            return (zip: zip, sums: sums, zipName: assets.zip.name, tag: info.tag)
        }

        // (2) 체크섬 -> 압축 목록 -> 풀기 -> 버전·서명 요건 순서로 본다(T-05-02, T-05-03, T-05-04, T-05-08).
        let candidate = try await runStage(.verifying, fallback: .archive, onStage: onStage) {
            guard let sumsText = try? String(contentsOf: downloaded.sums, encoding: .utf8),
                  let expected = UpdateVerification.expectedChecksum(
                      sumsText: sumsText, fileName: downloaded.zipName),
                  let actual = try? UpdateVerification.sha256Hex(of: downloaded.zip),
                  actual == expected else { throw Failure.checksum }

            guard let namesOutput = Self.capture(
                      path: "/usr/bin/unzip", arguments: ["-Z1", downloaded.zip.path], timeout: 10),
                  let listingOutput = Self.capture(
                      path: "/usr/bin/unzip", arguments: ["-Z", "-l", downloaded.zip.path], timeout: 10) else {
                throw Failure.archive
            }
            let names = namesOutput.components(separatedBy: .newlines).filter { !$0.isEmpty }
            guard UpdateVerification.archiveNamesOK(names),
                  UpdateVerification.archiveListingOK(listingOutput, expectedEntries: names.count) else {
                throw Failure.archive
            }
            guard Self.runFixed(
                      path: "/usr/bin/ditto",
                      arguments: ["-x", "-k", downloaded.zip.path, workspacePath], timeout: 60) else {
                throw Failure.archive
            }

            // 풀린 트리를 lstat으로 훑는다: 실제 총 크기·항목 수 한도, 번들 밖 링크 거부(05 WR-05).
            let unpackedRoot = workspacePath + "/" + UpdateAssets.appName
            guard UnpackedTreeCheck.inspect(root: unpackedRoot) == .ok else { throw Failure.archive }

            // Bundle(url:)에 넘기기 전에 링크를 해석한 경로를 쓴다.
            let candidatePath = URL(fileURLWithPath: unpackedRoot).resolvingSymlinksInPath().path
            guard UpdateVerification.isHelperArgumentsSafe(
                      workspace: workspacePath, candidate: candidatePath, tempRoot: tempRoot),
                  let bundle = Bundle(url: URL(fileURLWithPath: candidatePath)) else {
                throw Failure.archive
            }
            // acceptCandidate가 양쪽의 v 접두사를 함께 떼므로 태그를 그대로 넘긴다(T-05-04).
            let releaseVersion = downloaded.tag
            guard UpdateVerification.acceptCandidate(
                      installedBundleID: Bundle.main.bundleIdentifier ?? "",
                      candidateBundleID: bundle.bundleIdentifier,
                      candidateVersion: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
                      releaseVersion: releaseVersion,
                      installedVersion: self.currentVersion) else { throw Failure.version }
            guard UpdateSignature.satisfies(bundle.bundleURL, requirement: requirement) else {
                throw Failure.signature
            }
            return (url: bundle.bundleURL, version: releaseVersion)
        }

        // (3) 같은 실행 파일을 도우미 모드로 띄운다. 도우미가 부모 종료를 기다렸다가 교체한다(RESEARCH Pitfall 5).
        try await runStage(.installing, fallback: .helper, onStage: onStage) {
            guard let executable = Bundle.main.executableURL else { throw Failure.helper }
            let process = Process()
            process.executableURL = executable
            // 도우미 인자와 영수증 키는 UpdateHelper와 같은 상수를 쓴다.
            process.arguments = [
                UpdateHelper.argument, workspacePath, candidate.url.path, candidate.version, String(getpid())
            ]
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            var environment = ProcessInfo.processInfo.environment
            // 부모가 받은 영수증 키를 자식에게 물려주지 않는다.
            environment.removeValue(forKey: UpdateReceipt.environmentKey)
            process.environment = environment
            do { try process.run() } catch { throw Failure.helper }
        }
    }

    /// 단계를 알리고 결과 코드를 남긴다. 단계 안의 알 수 없는 오류는 그 단계의 실패 코드로 묶는다.
    private func runStage<T>(_ stage: Stage, fallback: Failure,
                             onStage: @escaping @MainActor (Stage) -> Void,
                             _ body: () async throws -> T) async throws -> T {
        await onStage(stage)
        do {
            let value = try await body()
            Self.log(stage.logName, "ok")
            return value
        } catch let failure as Failure {
            Self.log(stage.logName, failure.rawValue)
            throw failure
        } catch {
            Self.log(stage.logName, fallback.rawValue)
            throw fallback
        }
    }

    // MARK: 준비

    /// 설치 위치·ad-hoc·작업 폴더를 먼저 본다. 통과하면 작업 폴더와 서명 요건을 돌려준다(T-05-05, T-05-08).
    private static func preflight() throws -> (workspace: URL, requirement: SecRequirement) {
        let bundlePath = Bundle.main.bundlePath
        let folder = (bundlePath as NSString).deletingLastPathComponent
        guard UpdateVerification.installLocationOK(bundlePath: bundlePath),
              FileManager.default.isWritableFile(atPath: folder) else {
            log("precheck", Failure.notInstallable.rawValue)
            throw Failure.notInstallable
        }
        guard let requirement = UpdateSignature.installedRequirement(bundleURL: Bundle.main.bundleURL) else {
            log("precheck", Failure.unsignedBuild.rawValue)
            throw Failure.unsignedBuild
        }
        let tempRoot = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().path
        let path = tempRoot + "/" + UpdateAssets.workspacePrefix + UUID().uuidString
        guard UpdateVerification.isWorkspaceSafe(path, tempRoot: tempRoot) else {
            log("precheck", Failure.notInstallable.rawValue)
            throw Failure.notInstallable
        }
        let workspace = URL(fileURLWithPath: path, isDirectory: true)
        do {
            try FileManager.default.createDirectory(
                at: workspace, withIntermediateDirectories: false,
                attributes: [.posixPermissions: 0o700])
        } catch {
            log("precheck", Failure.download.rawValue)
            throw Failure.download
        }
        return (workspace, requirement)
    }

    // MARK: 내려받기

    /// 자산 하나를 작업 폴더로 받는다. 최종 주소·상태·크기를 모두 확인한 뒤에만 옮긴다(T-05-01, T-05-06).
    private func download(_ asset: ReleaseAsset, into folder: URL, limit: Int) async throws -> URL {
        let (temporary, response) = try await session.download(for: URLRequest(url: asset.url))
        defer { try? FileManager.default.removeItem(at: temporary) }
        guard let http = response as? HTTPURLResponse,
              UpdateVerification.isAllowedDownload(finalURL: http.url, status: http.statusCode) else {
            throw Failure.download
        }
        let attributes = try? FileManager.default.attributesOfItem(atPath: temporary.path)
        guard let size = attributes?[.size] as? Int,
              size == asset.size, (1...limit).contains(size) else { throw Failure.download }
        let destination = folder.appendingPathComponent(asset.name)
        try FileManager.default.moveItem(at: temporary, to: destination)
        return destination
    }

    // MARK: 고정 경로 프로세스

    /// 고정 경로 실행 파일만, 셸 없이, 시간 제한 안에서 돌린다(T-05-10). 종료 코드 0이면 true.
    @discardableResult
    private static func runFixed(path: String, arguments: [String], timeout: TimeInterval) -> Bool {
        guard let process = makeProcess(path: path, arguments: arguments) else { return false }
        process.standardOutput = FileHandle.nullDevice
        return status(process, timeout: timeout) == 0
    }

    /// 표준 출력을 읽어 돌려준다. 파이프가 차서 프로세스가 멈추지 않도록 읽기를 따로 돌린다(T-05-10).
    private static func capture(path: String, arguments: [String], timeout: TimeInterval) -> String? {
        guard let process = makeProcess(path: path, arguments: arguments) else { return nil }
        let pipe = Pipe()
        process.standardOutput = pipe
        let box = PipeBox()
        let readDone = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .userInitiated).async {
            box.set(pipe.fileHandleForReading.readDataToEndOfFile())
            readDone.signal()
        }
        guard status(process, timeout: timeout) == 0 else {
            _ = readDone.wait(timeout: .now() + 2)
            return nil
        }
        guard readDone.wait(timeout: .now() + 2) == .success else { return nil }
        return String(data: box.get(), encoding: .utf8)
    }

    private static func makeProcess(path: String, arguments: [String]) -> Process? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        return process
    }

    /// 끝날 때까지 기다리고 종료 코드를 돌려준다. 시간을 넘기면 terminate하고 -1을 돌려준다.
    private static func status(_ process: Process, timeout: TimeInterval) -> Int32 {
        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        do { try process.run() } catch { return -1 }
        if finished.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            _ = finished.wait(timeout: .now() + 2)
            return -1
        }
        return process.terminationStatus
    }

    private static func log(_ step: String, _ result: String) {
        // URL, 경로, 헤더는 남기지 않는다(T-05-11).
        AppLog.info("update install step=\(step) result=\(result)")
    }
}

/// 파이프 읽기 결과를 스레드 사이에서 옮기는 상자.
private final class PipeBox {
    private let lock = NSLock()
    private var data = Data()

    func set(_ value: Data) {
        lock.lock()
        data = value
        lock.unlock()
    }

    func get() -> Data {
        lock.lock()
        defer { lock.unlock() }
        return data
    }
}
