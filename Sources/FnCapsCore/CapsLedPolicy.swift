import Foundation

/// 표시등을 다루는 경로. Phase 7 실기 판정으로 제품 경로를 하나만 남겼다(D-01, D-09).
public enum CapsLedPath: String, CaseIterable, Equatable, Sendable {
    /// 경로 A: 잠금 변경 뒤 `HIDCapsLockLED`에 `Auto`를 다시 쓴다. 덮어쓰지 않는다.
    case auto
    /// 경로 B: 잠금이 켜지면 `On`, 꺼지면 `Auto`를 쓴다. 덮어쓰기라 복원 책임이 따른다(D-07).
    case on
    /// 경로 C: `HIDCapsLockState`를 잠금 값과 맞춘다. 시스템 잠금도 함께 바뀐다.
    case state
    /// 쓰지 않는다. 0.9.2와 같은 동작이다.
    case off
}

/// Caps Lock 표시등의 서비스 속성 값. 필터가 아는 네 값 중 덮어쓰기 두 개와 시스템 기본 하나만 다룬다.
/// `Inhibit`은 쓰지 않는다. 입력 서비스가 쓰는 값이고, 앱이 쓸 이유가 없다(D-01).
public enum CapsLedMode: String, Equatable, Sendable {
    case on = "On"
    case off = "Off"
    case auto = "Auto"
}

/// 이번에 표시등에 무엇을 쓸지. 두 값이 모두 nil이면 아무것도 쓰지 않는다.
public struct CapsLedPlan: Equatable, Sendable {
    /// `HIDCapsLockLED`에 쓸 값. nil이면 쓰지 않는다.
    public var mode: CapsLedMode?
    /// `HIDCapsLockState`에 쓸 값(경로 C). nil이면 쓰지 않는다.
    public var syncState: Bool?

    public init(mode: CapsLedMode?, syncState: Bool?) {
        self.mode = mode
        self.syncState = syncState
    }

    /// 시스템 기본으로 되돌린다. 잔존한 `On`도 이 한 번으로 풀린다(D-07).
    public static let release = CapsLedPlan(mode: .auto, syncState: nil)
    /// 쓰지 않는다(경로 off, 0.9.2 동작).
    public static let none = CapsLedPlan(mode: nil, syncState: nil)
}

/// 표시등을 실제로 쓰는 쪽(System). Core는 모양만 정하고 구현을 주입받는다(CLAUDE.md 계층 경계).
public protocol CapsLedWriting: AnyObject {
    /// 계획을 대상 서비스에 쓴다. 반환값: nil = 심볼·클라이언트·커널 키보드 집합이 없어 쓰지 못함,
    /// 0 = 쓸 대상 서비스가 없음, n = 쓴 서비스 수.
    @discardableResult func write(_ plan: CapsLedPlan) -> Int?

    /// 모든 대상 서비스를 시스템 기본(`Auto`)으로 돌려놓는다. 멱등. 반환값 규칙은 `write`와 같다.
    @discardableResult func release() -> Int?
}

/// 지금 표시등에 무엇을 쓸지 정한다. 순수 함수라 표 전체를 시험으로 고정한다(D-01, D-08).
public enum CapsLedPolicy {
    /// 제품 경로. Phase 7 실기 판정(07-SPIKE.md): 경로 A(`auto`), D-09.
    public static let productPath: CapsLedPath = .auto

    /// - mappingUp: 매핑이 올라가 있는가(`tap.capsKeyCode != nil`). 내려가 있으면 진짜 Caps가
    ///   시스템에 있으므로 경로와 무관하게 시스템 기본으로 돌려준다(D-04, D-07).
    public static func plan(path: CapsLedPath, mappingUp: Bool, lockOn: Bool) -> CapsLedPlan {
        guard mappingUp else { return .release }
        switch path {
        case .off:
            return .none
        // A: 덮어쓰지 않고, 필터가 잠금에서 LED를 다시 맞추게 한다.
        case .auto:
            return .release
        // B: 켜짐이면 On. 끌 때는 Off가 아니라 Auto를 쓴다. Off도 덮어쓰기라 잔존 위험이 같고,
        // Auto는 필터 상태를 따르므로 진실이 하나로 유지된다(D-07, D-08).
        case .on:
            return CapsLedPlan(mode: lockOn ? .on : .auto, syncState: nil)
        // C: 잠금 값을 서비스에 직접 쓴다. 시스템 잠금도 함께 바뀐다.
        case .state:
            return CapsLedPlan(mode: .auto, syncState: lockOn)
        }
    }
}

/// 경로 읽기와 로그를 한 곳에서 처리한다. 실제 IPC는 주입받은 `CapsLedWriting`이 한다.
public final class CapsLedManager {
    private let writer: CapsLedWriting
    /// 지금 쓸 경로. 제품은 `CapsLedPolicy.productPath`를 돌려준다(D-09).
    private let path: () -> CapsLedPath
    private let log: (String) -> Void
    private let now: () -> TimeInterval

    public init(
        writer: CapsLedWriting, path: @escaping () -> CapsLedPath, log: @escaping (String) -> Void,
        now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
    ) {
        self.writer = writer
        self.path = path
        self.log = log
        self.now = now
    }

    /// 잠금이 바뀌었거나 깨어난 뒤 표시등을 맞춘다. 잠금 값을 읽지 못했으면 쓰지 않는다.
    public func apply(reason: String, mappingUp: Bool, lockOn: Bool?) {
        let path = self.path()
        guard let lockOn else {
            log(
                "led apply reason=\(reason) path=\(path.rawValue) lockOn=- mappingUp=\(flag(mappingUp)) "
                    + "services=- ms=0 result=skip")
            return
        }
        let plan = CapsLedPolicy.plan(path: path, mappingUp: mappingUp, lockOn: lockOn)
        guard plan != CapsLedPlan.none else {
            log(
                "led apply reason=\(reason) path=\(path.rawValue) lockOn=\(flag(lockOn)) "
                    + "mappingUp=\(flag(mappingUp)) services=0 ms=0 result=off")
            return
        }
        let start = now()
        let written = writer.write(plan)
        log(
            "led apply reason=\(reason) path=\(path.rawValue) lockOn=\(flag(lockOn)) "
                + "mappingUp=\(flag(mappingUp)) services=\(count(written)) "
                + "ms=\(ms(since: start)) result=\(result(written))")
    }

    /// 매핑을 내리는 모든 지점에서 시스템에 돌려준다. 경로와 무관하게 한 번 쓴다.
    public func release(reason: String) {
        let path = self.path()
        let start = now()
        let written = writer.release()
        log(
            "led release reason=\(reason) path=\(path.rawValue) services=\(count(written)) "
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
