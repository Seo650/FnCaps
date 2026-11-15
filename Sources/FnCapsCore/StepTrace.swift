import Foundation

/// Caps와 fn 전환 한 번의 단계 기록 기준. 기준 시각(`decidedAt`, 전환 기준 시각)부터 센 ms와 1초 창,
/// 로그 줄 형식만 둔다(순수 타입).
/// 창은 plan B가 돌면 그 시작부터 1초까지 늘어난다.
public struct StepTrace: Equatable, Sendable {
    /// 판정 뒤 실제 소스 변경을 기록하는 시간(ms).
    public static let windowMs: Double = 1000
    /// 줄 머리말(`caps step`, `fn step`).
    public let label: String
    public let seq: Int
    /// 전환 판정 시각(CFAbsoluteTime과 같은 초 단위).
    public let decidedAt: Double

    /// 판정 시각부터 잰 창 끝(ms). 기본은 windowMs.
    public let windowEndMs: Double

    public init(label: String, seq: Int, decidedAt: Double) {
        self.init(label: label, seq: seq, decidedAt: decidedAt, windowEndMs: Self.windowMs)
    }

    private init(label: String, seq: Int, decidedAt: Double, windowEndMs: Double) {
        self.label = label
        self.seq = seq
        self.decidedAt = decidedAt
        self.windowEndMs = windowEndMs
    }

    /// now부터 windowMs까지 창을 늘린 복사본. 창은 줄지 않는다.
    public func extendingWindow(from now: Double) -> StepTrace {
        StepTrace(
            label: label, seq: seq, decidedAt: decidedAt,
            windowEndMs: max(windowEndMs, elapsedMs(at: now) + Self.windowMs))
    }

    public func elapsedMs(at now: Double) -> Double {
        (now - decidedAt) * 1000
    }

    /// 판정 시각 이후 windowEndMs 이내인가. 시계가 되돌아간 경우는 거짓.
    public func isInWindow(at now: Double) -> Bool {
        let ms = elapsedMs(at: now)
        return ms >= 0 && ms <= windowEndMs
    }

    /// `<label> <seq> +<ms>ms <event>`
    public func line(_ event: String, at now: Double) -> String {
        "\(label) \(seq) +\(String(format: "%.1f", elapsedMs(at: now)))ms \(event)"
    }
}
