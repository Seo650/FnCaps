// 구조 참고: LinearMouse EventTapRecovery, GlobalEventTapWatchdog (MIT)
import Foundation

/// 탭 생성 실패를 유한하게 재시도한다(L3). 메인 스레드에서만 쓴다.
///
/// LinearMouse와 다른 점: `.started`면 비활성으로 돌아간다. 원본은 활성으로 남지만, 우리는 성공 뒤
/// 탭이 다시 죽었을 때 소유자가 `start`로 새로 복구할 수 있어야 한다.
public final class TapRecovery {
    /// cancelled: 지금은 시도하면 안 되는 상태(재구성 대기, 재설정 등). 재시도도 onFailure도 없이 비활성으로 끝낸다.
    public enum StartResult: Equatable, Sendable { case started, permissionRequired, failed, cancelled }
    public typealias Attempt = (@escaping (StartResult) -> Void) -> Void
    public typealias Schedule = (TimeInterval, @escaping () -> Void) -> Void

    private let delays: [TimeInterval]
    private let schedule: Schedule
    private let attempt: Attempt
    private let onFailure: (StartResult) -> Void

    public private(set) var isActive = false
    /// 지금 기다리는 시도나 예약 하나만 가리킨다. 바뀌면 옛 예약과 늦은 결과는 버려진다.
    private var pendingID: UInt64 = 0

    public init(
        delays: [TimeInterval] = [0.5, 1, 2],
        schedule: @escaping Schedule = { delay, work in
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        },
        attempt: @escaping Attempt,
        onFailure: @escaping (StartResult) -> Void
    ) {
        self.delays = delays
        self.schedule = schedule
        self.attempt = attempt
        self.onFailure = onFailure
    }

    /// .started·.cancelled 뒤에는 isActive == false여서 다음 start가 새로 시도한다.
    /// .permissionRequired와 예산 소진 뒤에는 stop 전까지 활성으로 남아 start를 무시한다.
    public func start() {
        guard !isActive else { return }
        isActive = true
        run(retry: 0)
    }

    public func stop() {
        pendingID &+= 1
        isActive = false
    }

    public func restart() {
        stop()
        start()
    }

    private func run(retry: Int) {
        pendingID &+= 1
        let id = pendingID
        attempt { [weak self] result in
            self?.finish(id: id, retry: retry, result: result)
        }
    }

    private func finish(id: UInt64, retry: Int, result: StartResult) {
        guard isActive, id == pendingID else { return }
        pendingID &+= 1
        switch result {
        case .started, .cancelled:
            isActive = false
        case .permissionRequired:
            onFailure(result)
        case .failed:
            guard retry < delays.count else {
                onFailure(result)
                return
            }
            let scheduledID = pendingID
            schedule(delays[retry]) { [weak self] in
                guard let self, self.isActive, scheduledID == self.pendingID else { return }
                self.run(retry: retry + 1)
            }
        }
    }
}

/// 탭이 살아 있어도 실제 tapCreate로 권한을 시험한다(L4). 메인 스레드에서만 쓴다. 타이머는 소유자가 돌린다.
/// 이유(LinearMouse 주석): permission APIs can report a cached grant after access has been revoked.
///
/// LinearMouse와 다른 점: 실패에 스스로 멈추지 않고 결과를 모두 돌려준다. 막힌 상태에서도 계속 지켜보다
/// 프로브가 성공하면 복구하기 위해서다.
public final class ProbeWatchdog {
    public typealias Probe = (@escaping (Bool) -> Void) -> Void

    private let probe: Probe
    private let onResult: (Bool) -> Void
    private var isWatching = false
    private var isChecking = false
    private var watchID: UInt64 = 0

    public init(probe: @escaping Probe, onResult: @escaping (Bool) -> Void) {
        self.probe = probe
        self.onResult = onResult
    }

    public func start() {
        guard !isWatching else { return }
        isWatching = true
        watchID &+= 1
    }

    /// 돌고 있는 프로브는 끝날 때까지 `isChecking`을 쥐고 있어, stop 뒤 바로 start해도 검사가 겹치지 않는다.
    public func stop() {
        isWatching = false
        watchID &+= 1
    }

    /// 멈춰 있거나 검사 중이면 아무것도 안 함.
    public func check() {
        guard isWatching, !isChecking else { return }
        isChecking = true
        let id = watchID
        probe { [weak self] ok in
            guard let self else { return }
            self.isChecking = false
            guard self.isWatching, id == self.watchID else { return }
            self.onResult(ok)
        }
    }
}
