import Foundation

/// 실행 중인 같은 앱 인스턴스 하나. 시작 시점의 LaunchServices 목록 값과 실제 프로세스 존재를 함께 담는다.
public struct RunningPeer: Equatable, Sendable {
    public let pid: Int32
    /// LaunchServices가 이미 끝났다고 표시했는가.
    public let terminated: Bool
    /// 프로세스가 실제로 살아 있는가(`kill(pid, 0)`).
    public let alive: Bool

    public init(pid: Int32, terminated: Bool, alive: Bool) {
        self.pid = pid
        self.terminated = terminated
        self.alive = alive
    }
}

/// 같은 번들 ID의 앱이 이미 살아 있으면 새로 뜬 쪽이 Caps 매핑·#60에 닿기 전에 끝나게 하는 판정.
/// 2026-11-16 사고: /Applications 0.9.0과 build 0.9.1이 함께 돌았고, 나중에 끝난 쪽이 복원하면서
/// #60을 원래 조합으로 되돌려 남은 쪽의 Caps 전환이 매번 펄스 시간 초과로 떨어졌다.
/// 시스템에 닿지 않는다.
public enum SingleInstanceCheck {
    /// 살아 있는 다른 인스턴스가 있으면 참. 자식 CLI 실행(FreshSourceLister)과 업데이트 도우미는 부모 pid이므로 뺀다.
    /// - parentPid: 업데이트 도우미(`--install-update`)가 같은 실행 파일로 새 앱의 부모가 되므로, 부모는 중복이 아니다.
    /// - peers의 terminated·alive: 끝난 pid가 LaunchServices 목록에 잠깐 남는 경우를 막는다.
    public static func shouldExit(selfPid: Int32, parentPid: Int32, peers: [RunningPeer]) -> Bool {
        peers.contains { $0.pid != selfPid && $0.pid != parentPid && !$0.terminated && $0.alive }
    }
}
