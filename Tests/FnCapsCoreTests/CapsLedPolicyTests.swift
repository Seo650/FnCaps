import Testing
@testable import FnCapsCore

@Suite struct CapsLedPolicyTests {
    /// 경로 × 매핑 상태 × 잠금 상태 표를 그대로 편다.
    private func plan(_ path: CapsLedPath, mappingUp: Bool, lockOn: Bool) -> CapsLedPlan {
        CapsLedPolicy.plan(path: path, mappingUp: mappingUp, lockOn: lockOn)
    }

    /// 실제 IPC 대신 쓴 기록자. 넣은 계획과 돌려줄 값을 그대로 들고 있는다.
    private final class FakeWriter: CapsLedWriting {
        var writes: [CapsLedPlan] = []
        var releases = 0
        var result: Int? = 1

        func write(_ plan: CapsLedPlan) -> Int? {
            writes.append(plan)
            return result
        }

        func release() -> Int? {
            releases += 1
            return result
        }
    }

    private final class LogSink {
        var lines: [String] = []
    }

    private func manager(_ writer: FakeWriter, path: CapsLedPath, sink: LogSink) -> CapsLedManager {
        CapsLedManager(writer: writer, path: { path }, log: { sink.lines.append($0) }, now: { 0 })
    }

    // MARK: 경로 표

    @Test func mappingDownAlwaysReleases() {
        // 매핑이 내려가 있으면 진짜 Caps가 시스템에 있으므로 네 경로 모두 Auto로 돌려준다.
        for path in CapsLedPath.allCases {
            for lockOn in [true, false] {
                #expect(plan(path, mappingUp: false, lockOn: lockOn) == .release, "path=\(path) lockOn=\(lockOn)")
            }
        }
    }

    @Test func pathAutoRewritesAuto() {
        #expect(plan(.auto, mappingUp: true, lockOn: true) == CapsLedPlan(mode: .auto, syncState: nil))
        #expect(plan(.auto, mappingUp: true, lockOn: false) == CapsLedPlan(mode: .auto, syncState: nil))
    }

    @Test func pathOnFollowsLock() {
        #expect(plan(.on, mappingUp: true, lockOn: true) == CapsLedPlan(mode: .on, syncState: nil))
        // 덮어쓰기는 잔존하므로 끌 때도 Off가 아니라 Auto(필터 상태를 따른다)를 쓴다(D-07).
        #expect(plan(.on, mappingUp: true, lockOn: false) == CapsLedPlan(mode: .auto, syncState: nil))
    }

    @Test func pathStateSyncsLockState() {
        #expect(plan(.state, mappingUp: true, lockOn: true) == CapsLedPlan(mode: .auto, syncState: true))
        #expect(plan(.state, mappingUp: true, lockOn: false) == CapsLedPlan(mode: .auto, syncState: false))
    }

    @Test func pathOffWritesNothing() {
        #expect(plan(.off, mappingUp: true, lockOn: true) == .none)
        #expect(plan(.off, mappingUp: true, lockOn: false) == .none)
    }

    @Test func noCellEverAsksForOffMode() {
        // 열여섯 칸 어디에서도 Off 모드를 내지 않는다. Off도 덮어쓰기라 잔존 위험이 같다.
        for path in CapsLedPath.allCases {
            for mappingUp in [true, false] {
                for lockOn in [true, false] {
                    let got = plan(path, mappingUp: mappingUp, lockOn: lockOn)
                    #expect(got.mode != .off, "path=\(path) mappingUp=\(mappingUp) lockOn=\(lockOn)")
                }
            }
        }
        #expect(CapsLedPlan.release.mode == .auto)
        #expect(CapsLedPlan.release.syncState == nil)
        #expect(CapsLedPlan.none.mode == nil)
        #expect(CapsLedPlan.none.syncState == nil)
    }

    // MARK: 제품 경로

    @Test func productPathIsVerdictPath() {
        // Phase 7 실기 판정(07-SPIKE.md): outcome=pass-clean path=auto. 판정 줄과 코드가 어긋나지 않게 고정한다(D-09).
        #expect(CapsLedPolicy.productPath == .auto)
        #expect(CapsLedPath.allCases == [.auto, .on, .state, .off])
    }

    // MARK: 관리자

    @Test func applyWithPathOffDoesNotWrite() {
        let writer = FakeWriter()
        let sink = LogSink()
        manager(writer, path: .off, sink: sink).apply(reason: "lock", mappingUp: true, lockOn: true)
        #expect(writer.writes.isEmpty)
        #expect(writer.releases == 0)
        #expect(sink.lines.contains { $0.contains("result=off") })
    }

    @Test func applyWithoutLockStateSkips() {
        // 잠금 값을 읽지 못했으면 쓰지 않고 넘어간다.
        let writer = FakeWriter()
        let sink = LogSink()
        manager(writer, path: .on, sink: sink).apply(reason: "recover", mappingUp: true, lockOn: nil)
        #expect(writer.writes.isEmpty)
        #expect(sink.lines.contains { $0.contains("result=skip") })
    }

    @Test func applySendsPolicyPlanToWriterOnce() {
        let writer = FakeWriter()
        let sink = LogSink()
        manager(writer, path: .on, sink: sink).apply(reason: "lock", mappingUp: true, lockOn: true)
        #expect(writer.writes == [CapsLedPlan(mode: .on, syncState: nil)])
        #expect(sink.lines.last?.contains("led apply reason=lock path=on lockOn=1 mappingUp=1") == true)
    }

    @Test func applyReportsWriterResult() {
        func run(_ result: Int?) -> (Int, String) {
            let writer = FakeWriter()
            writer.result = result
            let sink = LogSink()
            manager(writer, path: .on, sink: sink).apply(reason: "lock", mappingUp: true, lockOn: true)
            return (writer.writes.count, sink.lines.last ?? "")
        }
        let ok = run(1)
        #expect(ok.0 == 1)
        #expect(ok.1.contains("result=ok"))
        let none = run(0)
        #expect(none.0 == 1)
        #expect(none.1.contains("result=none"))
        let unsupported = run(nil)
        #expect(unsupported.0 == 1)
        #expect(unsupported.1.contains("result=unsupported"))
    }

    @Test func releaseCallsWriterOnEveryPath() {
        for path in CapsLedPath.allCases {
            let writer = FakeWriter()
            let sink = LogSink()
            manager(writer, path: path, sink: sink).release(reason: "restore")
            #expect(writer.releases == 1, "path=\(path)")
            #expect(sink.lines.last?.hasPrefix("led release reason=restore") == true)
        }
    }

    @Test func logLinesCarryStateWordsOnly() {
        let writer = FakeWriter()
        let sink = LogSink()
        let m = manager(writer, path: .state, sink: sink)
        m.apply(reason: "lock", mappingUp: true, lockOn: false)
        m.release(reason: "launch")
        #expect(!sink.lines.isEmpty)
        for line in sink.lines {
            #expect(line.hasPrefix("led apply reason=") || line.hasPrefix("led release reason="))
            #expect(line.contains("path="))
            #expect(line.contains("services="))
            #expect(line.contains("ms="))
            #expect(line.contains("result="))
        }
    }
}
