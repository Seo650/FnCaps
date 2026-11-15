import Foundation

/// 조정(적용)과 복원의 진입 순서만 판단하는 순수 타입. 시스템에 닿지 않는다.
///
/// 규칙
/// - 복원이 시작되면 진행 중인 적용은 매핑을 쓰지 않는다(세대가 올라 불일치).
/// - 복원 중 들어온 요청은 무시한다. 복원이 끝나도 되살아나지 않는다.
/// - 종료가 시작되면 이후 조정 요청은 무시하고 기억해 둔 target도 버린다. 복원은 계속 동작한다.
public struct CapsReconcileGate: Equatable, Sendable {
    public enum Request: Equatable, Sendable {
        case start(Int)
        case remembered
        case ignored
    }

    public enum RestoreStart: Equatable, Sendable {
        case start(Int)
        /// 줄 서거나 진행 중인 복원에 합쳐졌다.
        case queued
    }

    public enum AfterApply: Equatable, Sendable {
        case writeMapping
        case skip
    }

    public enum Next: Equatable, Sendable {
        case idle
        case startRestore(Int)
        case reconcile(CapsSystemTarget)
    }

    public private(set) var generation = 0
    public private(set) var applying = false
    public private(set) var restoring = false
    public private(set) var terminating = false
    private var remembered: CapsSystemTarget?
    private var restoreQueued = false
    private var restoreAgain = false

    public init() {}

    public var busy: Bool { applying || restoring }

    /// 적용(.full, .shortcutOnly) 요청.
    public mutating func request(_ target: CapsSystemTarget) -> Request {
        if terminating {
            remembered = nil
            return .ignored
        }
        if restoring || restoreQueued { return .ignored }
        if applying {
            remembered = target
            return .remembered
        }
        applying = true
        generation += 1
        return .start(generation)
    }

    /// 복원 시작. 호출 즉시 세대를 올린다(줄 서는 경우에도).
    /// - force: 이미 복원 중이어도 끝난 뒤 한 번 더 한다(끄기, 되돌리기, 종료). 자동 복원은 합쳐진다.
    public mutating func beginRestore(force: Bool = false) -> RestoreStart {
        generation += 1
        remembered = nil
        if restoring {
            if force { restoreAgain = true }
            return .queued
        }
        if applying {
            restoreQueued = true
            return .queued
        }
        restoring = true
        return .start(generation)
    }

    public mutating func beginTermination() {
        terminating = true
        remembered = nil
    }

    /// 적용 중 activate 완료. 세대가 같고 성공일 때만 매핑을 쓴다.
    public func applyFinished(generation g: Int, success: Bool) -> AfterApply {
        guard g == generation, success, !restoring, !restoreQueued, !terminating else { return .skip }
        return .writeMapping
    }

    /// 적용 경로가 끝났다(매핑을 썼든 건너뛰었든).
    public mutating func applyDone() -> Next {
        applying = false
        if restoreQueued {
            restoreQueued = false
            restoring = true
            return .startRestore(generation)
        }
        if let r = remembered {
            remembered = nil
            return terminating ? .idle : .reconcile(r)
        }
        return .idle
    }

    public mutating func restoreFinished() -> Next {
        restoring = false
        if restoreAgain {
            restoreAgain = false
            restoring = true
            generation += 1
            return .startRestore(generation)
        }
        return .idle
    }
}
