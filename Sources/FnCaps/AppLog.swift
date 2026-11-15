import Foundation
import os

/// 통합 로그 래퍼. 상태 단어, 소스 ID, 전략 이름, 오류 domain/code만 넘긴다.
/// 키코드·문자·입력 내용은 절대 넘기지 않는다(T-02-17).
/// 읽기: log show --predicate 'subsystem == "io.github.seo650.fncaps"'
/// 진단 정보용으로 최근 줄을 메모리에만 보관한다(디스크에 남기지 않는다).
enum AppLog {
    static let logger = Logger(subsystem: "io.github.seo650.fncaps", category: "app")

    private static let capacity = 300
    private static let lock = NSLock()
    private static var ring: [String] = []
    private static let clock: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    static func info(_ message: String) {
        logger.info("\(message, privacy: .public)")
        lock.lock()
        ring.append("\(clock.string(from: Date())) \(message)")  // DateFormatter도 잠금 안에서만 쓴다
        if ring.count > capacity { ring.removeFirst(ring.count - capacity) }
        lock.unlock()
    }

    /// 시각 머리말을 떼지 않은 최근 줄(오래된 것부터).
    static func recentLines() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return ring
    }
}
