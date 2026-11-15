import Testing
@testable import FnCapsCore

@Suite struct KeyHoldTests {
    @Test func passesWhenIdle() {
        var h = KeyHold()
        #expect(h.classify(isKey: true, now: 0) == .pass)
    }

    @Test func capturesKeysOnlyWhileHolding() {
        var h = KeyHold()
        h.begin(now: 10)
        #expect(h.classify(isKey: true, now: 10.01) == .capture)
        #expect(h.classify(isKey: false, now: 10.01) == .pass)
        #expect(h.count == 1)
        h.flushed(posted: 1, now: 10.02)
        #expect(h.echoSeen() == false)
        #expect(h.classify(isKey: true, now: 10.03) == .pass)
    }

    @Test func preservesOrderAtTimeLimit() {
        var h = KeyHold(maxMs: 200, capacity: 32)
        h.begin(now: 0)
        #expect(h.classify(isKey: true, now: 0.199) == .capture)
        #expect(h.classify(isKey: true, now: 0.2) == .captureThenFlush)
        #expect(h.count == 2)
        h.flushed(posted: 2, now: 0.2)
        #expect(h.classify(isKey: true, now: 0.21) == .capture)
        #expect(h.echoSeen() == false)
        #expect(h.echoSeen() == true)
        h.flushed(posted: 1, now: 0.22)
        #expect(h.echoSeen() == false)
        #expect(h.classify(isKey: true, now: 0.23) == .pass)
    }

    @Test func flushesAtCapacity() {
        var h = KeyHold(maxMs: 1000, capacity: 2)
        h.begin(now: 0)
        #expect(h.classify(isKey: true, now: 0) == .capture)
        #expect(h.classify(isKey: true, now: 0) == .capture)
        #expect(h.classify(isKey: true, now: 0) == .captureThenFlush)
    }

    @Test func beginWhileHoldingKeepsCount() {
        var h = KeyHold(maxMs: 1000, capacity: 2)
        h.begin(now: 0)
        #expect(h.classify(isKey: true, now: 0) == .capture)
        h.begin(now: 1)
        #expect(h.count == 1)
        #expect(h.classify(isKey: true, now: 1) == .capture)
        #expect(h.classify(isKey: true, now: 1) == .captureThenFlush)
    }

    @Test func beginWhileDrainingKeepsCount() {
        var h = KeyHold(maxMs: 200, capacity: 32)
        var held: [Int] = []
        h.begin(now: 0)
        for i in 1...2 {
            #expect(h.classify(isKey: true, now: 0.01) == .capture)
            held.append(i)
        }
        h.flushed(posted: held.count, now: 0.05)
        held = []
        #expect(h.classify(isKey: true, now: 0.06) == .capture)
        held.append(3)
        h.begin(now: 0.07)
        #expect(h.count == 1)
        #expect(held.count == h.count)
        #expect(h.inFlight == 2)
    }

    @Test func lateEchoIgnored() {
        var h = KeyHold(maxMs: 200, capacity: 32)
        h.flushed(posted: 1, now: 0)
        #expect(h.classify(isKey: true, now: 0.25) == .captureThenFlush)
        #expect(h.echoSeen() == false)
        #expect(h.inFlight == 0)
        #expect(h.echoTrusted == false)
        h.begin(now: 1)
        #expect(h.echoTrusted == true)
    }

    @Test func drainTimeoutStopsWaitingForEcho() {
        var h = KeyHold(maxMs: 200, capacity: 32)
        h.flushed(posted: 2, now: 0)
        #expect(h.classify(isKey: true, now: 0.25) == .captureThenFlush)
        h.flushed(posted: 1, now: 0.25)
        #expect(h.isBusy == false)
        #expect(h.classify(isKey: true, now: 0.26) == .pass)
    }

    @Test func expireReleasesSingleKey() {
        var h = KeyHold(maxMs: 200, capacity: 32)
        #expect(h.expire(now: 5) == false)
        h.begin(now: 0)
        #expect(h.classify(isKey: true, now: 0.05) == .capture)
        #expect(h.expire(now: 0.1) == false)
        #expect(h.expire(now: 0.2) == true)
    }

    @Test func resetClearsEverything() {
        var h = KeyHold(maxMs: 200, capacity: 32)
        h.begin(now: 0)
        _ = h.classify(isKey: true, now: 0.01)
        h.flushed(posted: 1, now: 0.02)
        _ = h.classify(isKey: true, now: 0.5)
        h.reset()
        #expect(h.count == 0)
        #expect(h.inFlight == 0)
        #expect(!h.isHolding)
        #expect(h.echoTrusted)
        #expect(!h.isBusy)
    }

    /// Owner model: real keys 1...8 with the limit hit midway; echoes interleaved between real keys.
    @Test func preservesOrderSimulation() {
        var h = KeyHold(maxMs: 1000, capacity: 3)
        var held: [Int] = []
        var replayQueue: [Int] = []   // reposted, not yet echoed
        var output: [Int] = []
        var t = 0.0

        func release() {
            let n = held.count
            replayQueue.append(contentsOf: held)
            held = []
            h.flushed(posted: n, now: t)
        }
        func echo() {
            guard !replayQueue.isEmpty else { return }
            output.append(replayQueue.removeFirst())
            if h.echoSeen() { release() }
        }
        func real(_ k: Int) {
            switch h.classify(isKey: true, now: t) {
            case .pass: output.append(k)
            case .capture: held.append(k)
            case .captureThenFlush: held.append(k); release()
            }
        }

        h.begin(now: 0)
        for k in 1...8 {
            t += 0.001
            real(k)
            if k % 2 == 0 { echo() }
        }
        while !replayQueue.isEmpty { echo() }
        if !held.isEmpty { release(); while !replayQueue.isEmpty { echo() } }
        #expect(output == Array(1...8))
    }
}
