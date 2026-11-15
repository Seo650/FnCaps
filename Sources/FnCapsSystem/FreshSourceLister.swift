import Foundation
import FnCapsCore

/// 우리 실행 파일을 새 프로세스로 띄워 켜진 입력 소스 목록을 읽는다(GAP-01).
/// 앱 프로세스의 TIS 캐시를 거치지 않으므로 삭제·추가를 바로 본다(02-20 1부: 36~335 ms, 오판 없음).
/// 고정 경로, 고정 인자 하나, 셸 없음. 프로세스 실행은 전용 큐에서만 한다.
public final class FreshSourceLister {
    private static let argument = "--list-enabled-source-ids"
    private static let timeoutSeconds = 2.0

    private let executablePath: String?
    private let log: (String) -> Void
    private let queue = DispatchQueue(label: "io.github.seo650.fncaps.fresh-source-lister", qos: .utility)

    public init(
        executablePath: String? = Bundle.main.executablePath,
        log: @escaping (String) -> Void = { _ in }
    ) {
        self.executablePath = executablePath
        self.log = log
    }

    /// `completion`은 메인 큐에서 불린다. 비정상 종료·시간 초과·깨진 출력·빈 목록은 nil.
    public func list(completion: @escaping ([SourceInfo]?) -> Void) {
        queue.async { [executablePath, log] in
            let start = DispatchTime.now()
            let result = Self.run(executablePath).flatMap(EnabledSourceList.decode)
            let ms = (DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
            DispatchQueue.main.async {
                log("sources fresh n=\(result.map { String($0.count) } ?? "fail") ms=\(ms)")
                completion(result)
            }
        }
    }

    /// 표준 출력 전체를 돌려준다. 끝날 때까지 호출 스레드를 막으므로 전용 큐에서만 부른다.
    private static func run(_ executablePath: String?) -> Data? {
        guard let executablePath else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = [argument]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        do { try process.run() } catch { return nil }

        var data = Data()
        let reader = DispatchGroup()
        reader.enter()
        DispatchQueue.global(qos: .utility).async {
            data = pipe.fileHandleForReading.readDataToEndOfFile()
            reader.leave()
        }
        if finished.wait(timeout: .now() + timeoutSeconds) == .timedOut {
            process.terminate()
            _ = reader.wait(timeout: .now() + 0.5)
            return nil
        }
        reader.wait()
        return process.terminationStatus == 0 ? data : nil
    }
}
