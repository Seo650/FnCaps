import Testing
@testable import FnCapsCore

@Suite struct SingleInstanceCheckTests {
    private func peer(_ pid: Int32, terminated: Bool = false, alive: Bool = true) -> RunningPeer {
        RunningPeer(pid: pid, terminated: terminated, alive: alive)
    }

    private func shouldExit(
        selfPid: Int32 = 100, parentPid: Int32 = 1, peers: [RunningPeer]
    ) -> Bool {
        SingleInstanceCheck.shouldExit(selfPid: selfPid, parentPid: parentPid, peers: peers)
    }

    @Test func noPeers() {
        #expect(!shouldExit(peers: []))
    }

    @Test func onlySelf() {
        #expect(!shouldExit(peers: [peer(100)]))
    }

    @Test func otherAlive() {
        #expect(shouldExit(peers: [peer(100), peer(200)]))
    }

    @Test func otherTerminated() {
        // 끝난 인스턴스가 LaunchServices 목록에 잠깐 남는 경우.
        #expect(!shouldExit(peers: [peer(100), peer(200, terminated: true)]))
    }

    @Test func otherNotAlive() {
        // 목록에는 있으나 실제 프로세스가 없는 pid.
        #expect(!shouldExit(peers: [peer(100), peer(200, alive: false)]))
    }

    @Test func parentIsHelper() {
        // 업데이트 도우미가 같은 실행 파일로 새 앱의 부모가 된다.
        #expect(!shouldExit(parentPid: 300, peers: [peer(100), peer(300)]))
    }

    @Test func mixed() {
        let peers = [peer(100), peer(300), peer(400, terminated: true), peer(500, alive: false), peer(600)]
        #expect(shouldExit(parentPid: 300, peers: peers))
    }
}
