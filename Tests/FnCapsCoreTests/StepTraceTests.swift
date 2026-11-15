import Testing
@testable import FnCapsCore

@Suite struct StepTraceTests {
    private let trace = StepTrace(label: "caps step", seq: 3, decidedAt: 100.0)

    @Test func elapsedMs() {
        #expect(abs(trace.elapsedMs(at: 100.25) - 250) < 0.001)
    }

    @Test func window() {
        #expect(trace.isInWindow(at: 100.0))
        #expect(trace.isInWindow(at: 101.0))
        #expect(!trace.isInWindow(at: 101.0001))
        #expect(!trace.isInWindow(at: 99.9))
    }

    @Test func extendingWindow() {
        let e = trace.extendingWindow(from: 100.8)
        #expect(e.isInWindow(at: 101.8))
        #expect(!e.isInWindow(at: 101.8001))
        #expect(e.seq == 3 && e.decidedAt == 100.0)
        #expect(e.line("x", at: 101.5) == "caps step 3 +1500.0ms x")
        #expect(!e.isInWindow(at: 99.9))
    }

    @Test func extendingNeverShrinks() {
        for from in [100.0, 99.9] {
            let e = trace.extendingWindow(from: from)
            #expect(e.isInWindow(at: 101.0))
            #expect(!e.isInWindow(at: 101.0001))
        }
        let twice = trace.extendingWindow(from: 100.2).extendingWindow(from: 100.8)
        #expect(twice.isInWindow(at: 101.8))
        #expect(!twice.isInWindow(at: 101.8001))
        let reversed = trace.extendingWindow(from: 100.8).extendingWindow(from: 100.2)
        #expect(reversed.isInWindow(at: 101.8))
    }

    @Test func lineFormat() {
        #expect(trace.line("entry trigger=release target=x", at: 100.161)
            == "caps step 3 +161.0ms entry trigger=release target=x")
    }

    @Test func everyEventShapePassesDiagnosticsFilter() {
        let a = "com.apple.keylayout.ABC"
        let k = "com.apple.inputmethod.Korean.2SetKorean"
        let events = [
            "entry trigger=release target=\(k)",
            "plan=noOrigin target=\(k)",
            "plan=hop origin=\(a) target=\(k) recentCurrent=\(a) recentPrevious=nil composing=true",
            "prime leg=first ms=1.2 status=0/0",
            "pulse leg=second postMs=0.12",
            "pulse leg=first failed",
            "wait leg=first id=\(k) landed=false timeoutMs=500.0 sincePostMs=500.3 stableMs=0.0 current=\(a)",
            "fallback plan=hop leg=second reason=timeout",
            "inApp start path=fallback plan=hop",
            "inApp done landed=true current=\(k) notes",
            "source id=\(k) recentCurrent=\(k) recentPrevious=\(a)",
        ]
        let lines = events.map { trace.line($0, at: 100.1) }
        #expect(DiagnosticsReport.safeLogLines(lines) == lines)
        let stamped = lines.map { "12:34:56.789 " + $0 }
        #expect(DiagnosticsReport.safeLogLines(stamped) == stamped)
    }

    @Test func fnLabelLine() {
        let fn = StepTrace(label: "fn step", seq: 2, decidedAt: 100.0)
        #expect(fn.line("x", at: 100.5) == "fn step 2 +500.0ms x")
        #expect(fn.extendingWindow(from: 100.2).label == "fn step")
    }

    @Test func signalLimit() {
        #expect(SignalTiming.perSignalLimitMs == 500)
    }

    @Test func fnEventShapesPassDiagnosticsFilter() {
        let fn = StepTrace(label: "fn step", seq: 2, decidedAt: 100.0)
        let a = "com.apple.keylayout.ABC"
        let k = "com.apple.inputmethod.Korean.2SetKorean"
        let events = [
            "wait target=\(k) landed=false timeoutMs=500.0 waitMs=500.4 stableMs=30.0 current=\(a)",
            "fallback reason=timeout",
            "inApp start",
            "inApp done landed=true current=\(k) status=0/0 delay=30.0ms",
            "source id=\(k) recentCurrent=\(k) recentPrevious=\(a)",
        ]
        let lines = events.map { fn.line($0, at: 100.1) }
        #expect(DiagnosticsReport.safeLogLines(lines) == lines)
        let stamped = lines.map { "12:34:56.789 " + $0 }
        #expect(DiagnosticsReport.safeLogLines(stamped) == stamped)
    }
}
