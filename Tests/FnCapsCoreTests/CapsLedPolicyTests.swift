import Testing
@testable import FnCapsCore

@Suite struct CapsLedPolicyTests {
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

    private func manager(_ writer: FakeWriter, sink: LogSink) -> CapsLedManager {
        CapsLedManager(writer: writer, log: { sink.lines.append($0) }, now: { 0 })
    }

    // MARK: 계획

    @Test func releaseRewritesAuto() {
        // Phase 7 판정(07-SPIKE.md pass-clean): 경로 A 하나만 남아 늘 Auto를 쓴다(07-REVIEW WR-03).
        #expect(CapsLedPlan.release.mode == .auto)
        #expect(CapsLedPlan.release.mode != .off)
    }

    // MARK: 관리자

    @Test func applyWritesReleaseOnEveryMappingState() {
        // 매핑이 올라가 있든 내려가 있든 Auto 한 번. 경로 표가 사라져 판정 차이가 없다(WR-03).
        for mappingUp in [true, false] {
            for lockOn in [true, false] {
                let writer = FakeWriter()
                let sink = LogSink()
                manager(writer, sink: sink).apply(reason: "lock", mappingUp: mappingUp, lockOn: lockOn)
                #expect(writer.writes == [.release], "mappingUp=\(mappingUp) lockOn=\(lockOn)")
                #expect(writer.releases == 0)
            }
        }
    }

    @Test func applyWithoutLockStateStillWritesAuto() {
        // 깨어남 뒤 잠금 값을 읽지 못해도 재동기를 건너뛰지 않는다(07-REVIEW IN-02).
        let writer = FakeWriter()
        let sink = LogSink()
        manager(writer, sink: sink).apply(reason: "recover", mappingUp: true, lockOn: nil)
        #expect(writer.writes == [.release])
        let line = sink.lines.last ?? ""
        #expect(line.contains("lockOn=-"))
        #expect(line.contains("result=ok"))
    }

    @Test func applyReportsWriterResult() {
        func run(_ result: Int?) -> (Int, String) {
            let writer = FakeWriter()
            writer.result = result
            let sink = LogSink()
            manager(writer, sink: sink).apply(reason: "lock", mappingUp: true, lockOn: true)
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

    @Test func releaseCallsWriterOnce() {
        let writer = FakeWriter()
        let sink = LogSink()
        manager(writer, sink: sink).release(reason: "restore")
        #expect(writer.releases == 1)
        #expect(writer.writes.isEmpty)
        #expect(sink.lines.last?.hasPrefix("led release reason=restore") == true)
    }

    @Test func logLinesCarryStateWordsOnly() {
        let writer = FakeWriter()
        let sink = LogSink()
        let m = manager(writer, sink: sink)
        m.apply(reason: "lock", mappingUp: true, lockOn: false)
        m.release(reason: "launch")
        #expect(!sink.lines.isEmpty)
        for line in sink.lines {
            #expect(line.hasPrefix("led apply reason=") || line.hasPrefix("led release reason="))
            #expect(line.contains("path=auto"))
            #expect(line.contains("services="))
            #expect(line.contains("ms="))
            #expect(line.contains("result="))
        }
    }

    // MARK: 쓰기 대상

    @Test func targetAcceptsKernelKeyboard() {
        #expect(CapsLedTarget.isEligible(isKeyboard: true, transport: "USB", registryID: 7, kernel: [7]))
        #expect(CapsLedTarget.isEligible(isKeyboard: true, transport: "SPI", registryID: 7, kernel: [7]))
        #expect(CapsLedTarget.isEligible(isKeyboard: true, transport: "Bluetooth", registryID: 7, kernel: [7]))
    }

    @Test func targetRejectsVirtualAndMissingTransport() {
        // 리매퍼 가상 키보드와 Transport가 없는 서비스는 쓰기 대상이 아니다(T-07-04, 07-REVIEW IN-06).
        #expect(
            !CapsLedTarget.isEligible(
                isKeyboard: true, transport: CapsLedTarget.virtualTransport, registryID: 7, kernel: [7]))
        #expect(!CapsLedTarget.isEligible(isKeyboard: true, transport: nil, registryID: 7, kernel: [7]))
    }

    @Test func targetRejectsOutsideKernelSet() {
        // 매핑과 같은 커널 키보드 집합 밖이거나 집합을 못 읽으면 쓰지 않는다(fail closed, IN-06).
        #expect(!CapsLedTarget.isEligible(isKeyboard: true, transport: "USB", registryID: 8, kernel: [7]))
        #expect(!CapsLedTarget.isEligible(isKeyboard: true, transport: "USB", registryID: nil, kernel: [7]))
        #expect(!CapsLedTarget.isEligible(isKeyboard: true, transport: "USB", registryID: 7, kernel: nil))
    }

    @Test func targetRejectsNonKeyboard() {
        #expect(!CapsLedTarget.isEligible(isKeyboard: false, transport: "USB", registryID: 7, kernel: [7]))
    }
}
