// 구조 참고: LinearMouse AuthorizationProgress (재시작 1회), gksdud forgetUnusablePermissions (재시도) (MIT)
import Foundation

/// 권한 흐름 하나당 자동 재시작 1회(L2). 지우는 때는 ax false→true, 재설정 뒤 재허용, 탭과 프로브의 60 s 연속 성공뿐이다.
/// 탭 성공 한 번에 지우면 재시작 → 성공 → 감시 실패 → 재시작 고리가 생긴다.
public struct RestartMemory {
    public static let key = "permissionAutoRestartDone"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults) { self.defaults = defaults }

    public var canRestart: Bool { !defaults.bool(forKey: Self.key) }

    public func markRestarted() { defaults.set(true, forKey: Self.key) }

    /// ax false→true, 재설정 뒤 재허용, RestartStability 충족 때만 부른다. 탭 성공 한 번으로는 부르지 않는다.
    public func clear() { defaults.removeObject(forKey: Self.key) }
}

/// 탭과 프로브가 60 s 이어서 성공했는지 본다. 시간은 주입한다.
public struct RestartStability: Equatable, Sendable {
    public static let required: TimeInterval = 60

    private var firstSuccess: TimeInterval?

    public init() {}

    public mutating func noteFailure() { firstSuccess = nil }

    /// 첫 성공부터 required 이상 실패 없이 이어졌으면 true. 메모리에만 둔다(재시작하면 처음부터).
    public mutating func noteSuccess(now: TimeInterval) -> Bool {
        let first = firstSuccess ?? now
        firstSuccess = first
        return now - first >= Self.required
    }
}

/// 이 프로세스에서 마지막 허용(ax false→true) 뒤 탭 생성(설치나 프로브)이 한 번이라도 성공했는지 센다(G-08.1-4).
/// 깔린 적이 있으면 그 뒤의 탭 실패는 허용 직후 문제(L2)가 아니라 권한을 잃은 것이다. 철회 직후
/// AXIsProcessTrusted가 낡은 true를 줄 수 있어(PermissionMonitor·TapRecovery 주석, LinearMouse) 실패가
/// .failed로 온다. 재시작은 철회에 고칠 것이 없고 창만 닫는다.
public struct GrantSession: Equatable, Sendable {
    public private(set) var tapStartedSinceGrant = false
    private var lossShown = false

    public init() {}

    public mutating func noteTapStarted() {
        tapStartedSinceGrant = true
        lossShown = false
    }

    public mutating func noteGrant() {
        tapStartedSinceGrant = false
        lossShown = false
    }

    /// 잃음을 보인 때만 표시한다. 탭을 깐 적이 없으면(권한 없음이 처음부터) 지울 것도 없다.
    public mutating func noteLossShown() {
        if tapStartedSinceGrant { lossShown = true }
    }

    /// 권한 없음을 보인 뒤 온 알림은 다시 허용일 수 있다. 낡은 ax가 계속 true면 noteGrant가 불리지
    /// 않으므로 여기서 지워 L2 재시작을 되살린다. 철회 알림 자체(잃음 표시 전)로는 지우지 않는다.
    public mutating func noteAccessibilityNotification() {
        if lossShown {
            tapStartedSinceGrant = false
            lossShown = false
        }
    }
}

/// TapRecovery가 포기했을 때 무엇을 할지 정한다.
public enum RecoveryFailureAction: Equatable, Sendable {
    case showPermissionNeeded, autoRestart, showReset, ignore

    /// 이미 탭을 깔았던 프로세스의 실패는 재시작하지 않고 제자리에서 권한 없음을 보인다(G-08.1-4, 2026-11-23 UAT).
    public static func decide(
        result: TapRecovery.StartResult,
        canRestart: Bool,
        tapStartedSinceGrant: Bool
    ) -> RecoveryFailureAction {
        switch result {
        case .permissionRequired: return .showPermissionNeeded
        case .failed:
            if tapStartedSinceGrant { return .showPermissionNeeded }
            return canRestart ? .autoRestart : .showReset
        case .started, .cancelled: return .ignore
        }
    }
}

/// 설정 창 권한 칸의 상태.
public enum PermissionPanel: Equatable, Sendable {
    case hidden, grant, stuck, stuckResetFailed

    /// resetFailed는 stuck보다 앞선다. 권한이 꺼져 stuck이 풀려도 −/+ 안내를 유지한다.
    public static func resolve(trusted: Bool, stuck: Bool, resetFailed: Bool) -> PermissionPanel {
        if trusted { return .hidden }
        if resetFailed { return .stuckResetFailed }
        return stuck ? .stuck : .grant
    }
}

/// 유한 재시도(L6). 시도 사이에만 sleep한다.
public enum RetryPolicy {
    public static func run(
        attempts: Int = 3,
        delay: TimeInterval = 0.3,
        sleep: (TimeInterval) -> Void,
        operation: () -> Bool
    ) -> Bool {
        for attempt in 0..<max(attempts, 0) {
            if attempt > 0 { sleep(delay) }
            if operation() { return true }
        }
        return false
    }
}

/// 손쉬운 사용 알림 뒤 탭을 다시 만드는 시각(L5). 알림 값이 늦게 바뀔 수 있어 두 번 본다(추정).
public enum TapRebuildSchedule {
    public static let firstAttempt: TimeInterval = 0.3
    public static let finalCheck: TimeInterval = 1.5
}
