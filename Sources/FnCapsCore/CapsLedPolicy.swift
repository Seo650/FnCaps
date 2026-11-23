import Foundation

/// Caps Lock 표시등의 서비스 속성 값. 필터가 아는 네 값 중 덮어쓰기 두 개와 시스템 기본 하나만 다룬다.
/// `Inhibit`은 쓰지 않는다. 입력 서비스가 쓰는 값이고, 앱이 쓸 이유가 없다(D-01).
public enum CapsLedMode: String, Equatable, Sendable {
    case on = "On"
    case off = "Off"
    case auto = "Auto"
}

/// 이번에 표시등에 쓸 값. Phase 7 판정 뒤 Auto 하나만 남았다(07-SPIKE.md pass-clean, 07-REVIEW WR-03).
/// 실험 도구(`FnCapsSpike --led-write`)만 다른 모드를 만들어 쓴다.
public struct CapsLedPlan: Equatable, Sendable {
    /// `HIDCapsLockLED`에 쓸 값.
    public var mode: CapsLedMode

    public init(mode: CapsLedMode) {
        self.mode = mode
    }

    /// 시스템 기본으로 되돌린다. 잔존한 `On`도 이 한 번으로 풀린다(D-07).
    public static let release = CapsLedPlan(mode: .auto)
}

/// 표시등을 쓸 대상 서비스 판정. 매핑과 같은 커널 키보드 집합에만 쓰고 가상 키보드를 거른다
/// (T-07-04, 07-REVIEW IN-06). 집합을 못 읽으면 쓰지 않는다(fail closed).
public enum CapsLedTarget {
    /// 리매퍼가 만든 가상 키보드의 Transport 값.
    public static let virtualTransport = "Virtual"

    /// 키보드이고, Transport가 있고 `Virtual`이 아니며, registryID가 커널 키보드 집합에 드는가.
    public static func isEligible(
        isKeyboard: Bool, transport: String?, registryID: UInt64?, kernel: Set<UInt64>?
    ) -> Bool {
        guard isKeyboard, let transport, transport != virtualTransport else { return false }
        guard let registryID, let kernel else { return false }
        return kernel.contains(registryID)
    }
}

/// 표시등을 실제로 쓰는 쪽(System). Core는 모양만 정하고 구현을 주입받는다(CLAUDE.md 계층 경계).
public protocol CapsLedWriting: AnyObject {
    /// 계획을 대상 서비스에 쓴다. 반환값: nil = 심볼·클라이언트·커널 키보드 집합이 없어 쓰지 못함,
    /// 0 = 쓸 대상 서비스가 없음, n = 쓴 서비스 수.
    @discardableResult func write(_ plan: CapsLedPlan) -> Int?

    /// 모든 대상 서비스를 시스템 기본(`Auto`)으로 돌려놓는다. 멱등. 반환값 규칙은 `write`와 같다.
    @discardableResult func release() -> Int?
}

/// Caps Lock 표시등 관리자. Phase 7 판정(07-SPIKE.md pass-clean): 경로 A(Auto 다시 쓰기) 하나만 남겼다.
/// 잠금 변경·깨어남 뒤 `Auto`를 다시 써 필터가 잠금에서 표시등을 맞추게 한다. 쓰지 않는 경로는 지웠다
/// (07-REVIEW WR-03, IN-02). 실제 IPC는 주입받은 `CapsLedWriting`이 한다.
public final class CapsLedManager {
    private let writer: CapsLedWriting
    private let log: (String) -> Void
    private let now: () -> TimeInterval

    public init(
        writer: CapsLedWriting, log: @escaping (String) -> Void,
        now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
    ) {
        self.writer = writer
        self.log = log
        self.now = now
    }

    /// 잠금이 바뀌었거나 깨어난 뒤 표시등을 맞춘다. 잠금 값을 읽지 못해도 Auto를 쓴다(IN-02).
    /// 잠금 값과 매핑 상태는 로그에만 남긴다. `path=auto`는 0.9.3 진단 로그와 이어 읽기 위한 고정 글자다.
    public func apply(reason: String, mappingUp: Bool, lockOn: Bool?) {
        let start = now()
        let written = writer.write(.release)
        log(
            "led apply reason=\(reason) path=auto lockOn=\(lockOn.map(flag) ?? "-") "
                + "mappingUp=\(flag(mappingUp)) services=\(count(written)) "
                + "ms=\(ms(since: start)) result=\(result(written))")
    }

    /// 매핑을 내리는 모든 지점에서 시스템에 돌려준다. 경로와 무관하게 한 번 쓴다.
    public func release(reason: String) {
        let start = now()
        let written = writer.release()
        log(
            "led release reason=\(reason) path=auto services=\(count(written)) "
                + "ms=\(ms(since: start)) result=\(result(written))")
    }

    private func flag(_ value: Bool) -> String { value ? "1" : "0" }

    /// 서비스 수 자리. 쓰지 못했으면 `-`.
    private func count(_ written: Int?) -> String { written.map(String.init) ?? "-" }

    private func ms(since start: TimeInterval) -> Int { Int(((now() - start) * 1000).rounded()) }

    private func result(_ written: Int?) -> String {
        guard let written else { return "unsupported" }
        return written == 0 ? "none" : "ok"
    }
}
