import Testing
@testable import FnCapsCore

private let abc = Fx.abc.id
private let ko2 = Fx.ko2.id
private let ja = Fx.ja.id
private let zh = Fx.zh.id

/// 기본 구성(D-05): Caps = [ABC], fn = 외국어 소스 순서대로.
private func defaultLayout(_ sources: [SourceInfo]) -> KeyLayout {
    let c = SourceClassifier.classify(sources)
    return KeyLayout(caps: c.base, fn: c.foreign, sources: sources, rule: .nextAfterLast)
}
private let two = defaultLayout([Fx.abc, Fx.ko2, Fx.ja])
private let three = defaultLayout([Fx.abc, Fx.ko2, Fx.ja, Fx.zh])

private extension SwitchPipeline.RequestResult {
    var startID: SourceID? {
        if case .start(let id, _, _) = self { return id }
        return nil
    }
}

private extension SwitchPipeline {
    /// Completes the current run and returns the next source to start.
    mutating func done(_ actual: SourceID?, _ c: KeyLayout) -> SourceID? {
        completed(run: inFlightRun!, actual: actual, layout: c).next?.id
    }
}

private func seeded(_ c: KeyLayout, current: SourceID) -> SwitchPipeline {
    var p = SwitchPipeline()
    p.seed(current: current, history: [current], layout: c)
    return p
}

@Suite struct SwitchPipelineDecisionTests {
    @Test func fnFnReturnsToOriginalWithTwoModes() {
        let c = two
        var p = seeded(c, current: ko2)
        let a = p.press(.fn, actual: ko2, layout: c)
        #expect(a.decision == .switchTo(ja))
        #expect(a.request?.startID == ja)
        let b = p.press(.fn, actual: ko2, layout: c)
        #expect(b.decision == .switchTo(ko2))
        #expect(b.request?.startID == nil)
        #expect(p.queued == ko2)
        #expect(p.done(ja, c) == ko2)
        #expect(p.done(ko2, c) == nil)
        #expect(p.tracker.lastFn == ko2)
        #expect(!p.isSwitching)
    }

    @Test func threePressesEndOnJapaneseAndClearQueue() {
        let c = two
        var p = seeded(c, current: ko2)
        _ = p.press(.fn, actual: ko2, layout: c)
        _ = p.press(.fn, actual: ko2, layout: c)
        _ = p.press(.fn, actual: ko2, layout: c)
        #expect(p.queued == nil)
        #expect(p.pendingTarget == ja)
        #expect(p.done(ja, c) == nil)
        #expect(p.tracker.lastFn == ja)
    }

    @Test func twoPressesInThreeModesEndOnChinese() {
        let c = three
        var p = seeded(c, current: ko2)
        _ = p.press(.fn, actual: ko2, layout: c)
        _ = p.press(.fn, actual: ko2, layout: c)
        #expect(p.pendingTarget == zh)
        #expect(p.done(ja, c) == zh)
    }

    @Test func threePressesInThreeModesWrapToKoreanAndFourthAdvances() {
        let c = three
        var p = seeded(c, current: ko2)
        for _ in 0..<3 { _ = p.press(.fn, actual: ko2, layout: c) }
        #expect(p.pendingTarget == ko2)
        _ = p.press(.fn, actual: ko2, layout: c)
        #expect(p.pendingTarget == ja)
        #expect(p.queued == nil)
        _ = p.press(.fn, actual: ko2, layout: c)
        _ = p.press(.fn, actual: ko2, layout: c)
        #expect(p.pendingTarget == ko2)
        #expect(p.done(ja, c) == ko2)
        #expect(p.done(ko2, c) == nil)
    }

    @Test func capsDuringInFlightFnDecidesFromDestination() {
        let c = three
        var p = seeded(c, current: ko2)
        _ = p.press(.fn, actual: ko2, layout: c)
        let a = p.press(.caps, actual: ko2, layout: c)
        #expect(a.decision == .switchTo(abc))
        #expect(p.queued == abc)
        let b = p.press(.caps, actual: ko2, layout: c)
        #expect(b.decision == .switchTo(ja))
        #expect(p.queued == nil)
        #expect(p.pendingTarget == ja)
    }

    @Test func userExampleCapsThenFnWhileInFlight() {
        let c = three
        var p = seeded(c, current: ko2)
        let a = p.press(.caps, actual: ko2, layout: c)
        #expect(a.request?.startID == abc)
        let b = p.press(.fn, actual: ko2, layout: c)
        #expect(b.decision == .switchTo(ja))
        #expect(p.queued == ja)
        #expect(p.done(abc, c) == ja)
    }

    @Test func projectionStaysAuthoritativeWhileQueued() {
        let c = three
        var p = seeded(c, current: ko2)
        _ = p.press(.fn, actual: ko2, layout: c)
        _ = p.press(.fn, actual: ko2, layout: c)
        #expect(p.queued == zh)
        _ = p.press(.caps, actual: ko2, layout: c)
        #expect(p.queued == abc)
        #expect(p.done(ja, c) == abc)
        #expect(p.tracker.lastFn == zh)
        let d = p.press(.caps, actual: ja, layout: c)
        #expect(d.decision == .switchTo(zh))
    }

    @Test func resyncsFromActualAfterFailedSwitch() {
        let c = three
        var p = seeded(c, current: ko2)
        _ = p.press(.fn, actual: ko2, layout: c)
        #expect(p.done(ko2, c) == nil)
        #expect(p.tracker.lastFn == ko2)
    }

    @Test func observeUserIgnoredWhileSwitchingAppliedWhenIdle() {
        let c = three
        var p = seeded(c, current: ko2)
        _ = p.press(.fn, actual: ko2, layout: c)
        p.observeUser(selected: zh, layout: c)
        #expect(p.tracker.lastFn == ja)
        _ = p.done(ja, c)
        p.observeUser(selected: zh, layout: c)
        #expect(p.tracker.lastFn == zh)
    }

    @Test func noActualAndNothingPendingIsNoop() {
        let c = three
        var p = seeded(c, current: ko2)
        let r = p.press(.fn, actual: nil, layout: c)
        #expect(r.decision == .noop)
        #expect(r.request?.startID == nil)
        #expect(!p.isSwitching)
    }

    /// 규칙 변경(04-02 ListSwitcher D-10): fn 목록이 비면 통과한다. 한 칸짜리 목록은 더는 통과가 아니라
    /// 다른 목록의 마지막 소스로 간다(D-07, 아래 시험).
    @Test func fnWithEmptyFnListPassesThrough() {
        let c = defaultLayout([Fx.abc])
        var p = seeded(c, current: abc)
        let r = p.press(.fn, actual: abc, layout: c)
        #expect(r.decision == .passThrough)
        #expect(!p.isSwitching)
    }
}

/// Records every issued token and checks the exactly-once invariant.
private struct Ledger {
    var issued: [SwitchPipeline.Token] = []
    var resolved: [SwitchPipeline.Token] = []

    mutating func note(_ r: SwitchPipeline.RequestResult?) {
        guard let r else { return }
        switch r {
        case .start(_, _, let t): issued.append(t)
        case .queued(let t, let s), .joined(let t, let s):
            issued.append(t)
            resolved += s
        }
    }

    mutating func note(_ c: SwitchPipeline.Completion) { resolved += c.finished }

    func exactlyOnce() -> Bool {
        Set(resolved).count == resolved.count && Set(resolved) == Set(issued)
    }
}

@Suite struct SwitchPipelineTokenTests {
    @Test func startReturnsRunAndDistinctTokens() {
        let c = two
        var p = seeded(c, current: ko2)
        guard case .start(let id, let run, let t1)? = p.press(.fn, actual: ko2, layout: c).request else {
            Issue.record("expected start"); return
        }
        #expect(id == ja)
        #expect(p.inFlightRun == run)
        guard case .queued(let t2, let sup)? = p.press(.fn, actual: ko2, layout: c).request else {
            Issue.record("expected queued"); return
        }
        #expect(t1 != t2)
        #expect(sup.isEmpty)
    }

    @Test func joiningInFlightAddsTokenAndSupersedesQueue() {
        let c = two
        var p = seeded(c, current: ko2)
        var ledger = Ledger()
        ledger.note(p.press(.fn, actual: ko2, layout: c).request)
        ledger.note(p.press(.fn, actual: ko2, layout: c).request)
        let third = p.press(.fn, actual: ko2, layout: c).request
        guard case .joined(_, let sup)? = third else { Issue.record("expected joined"); return }
        #expect(sup.count == 1)
        ledger.note(third)
        let run = p.inFlightRun!
        let done = p.completed(run: run, actual: ja, layout: c)
        #expect(done.finished.count == 2)
        #expect(done.next == nil)
        ledger.note(done)
        #expect(ledger.exactlyOnce())
    }

    @Test func replacingQueuedReturnsSupersededTokens() {
        let c = three
        var p = seeded(c, current: ko2)
        _ = p.press(.fn, actual: ko2, layout: c)
        guard case .queued(let t2, _)? = p.press(.fn, actual: ko2, layout: c).request,
            case .queued(_, let sup)? = p.press(.caps, actual: ko2, layout: c).request
        else { Issue.record("expected queued"); return }
        #expect(sup == [t2])
    }

    @Test func completionWithQueuedEqualToActualFlushes() {
        let c = two
        var p = seeded(c, current: ko2)
        var ledger = Ledger()
        ledger.note(p.press(.fn, actual: ko2, layout: c).request)
        ledger.note(p.press(.fn, actual: ko2, layout: c).request)
        let done = p.completed(run: p.inFlightRun!, actual: ko2, layout: c)
        #expect(done.next == nil)
        #expect(done.finished.count == 2)
        ledger.note(done)
        #expect(ledger.exactlyOnce())
        #expect(!p.isSwitching)
    }

    @Test func exactlyOnceSequenceA() {
        let c = two
        var p = seeded(c, current: ko2)
        var l = Ledger()
        l.note(p.press(.fn, actual: ko2, layout: c).request)
        l.note(p.press(.fn, actual: ko2, layout: c).request)
        let d1 = p.completed(run: p.inFlightRun!, actual: ja, layout: c)
        #expect(d1.next?.id == ko2)
        l.note(d1)
        let d2 = p.completed(run: p.inFlightRun!, actual: ko2, layout: c)
        #expect(d2.next == nil)
        l.note(d2)
        #expect(l.exactlyOnce())
    }

    @Test func exactlyOnceSequenceC() {
        let c = three
        var p = seeded(c, current: ko2)
        var l = Ledger()
        l.note(p.press(.fn, actual: ko2, layout: c).request)
        l.note(p.press(.caps, actual: ko2, layout: c).request)
        l.note(p.press(.caps, actual: ko2, layout: c).request)
        l.note(p.completed(run: p.inFlightRun!, actual: ja, layout: c))
        #expect(l.exactlyOnce())
    }

    @Test func exactlyOnceSequenceDRepeatedRequests() {
        let c = three
        var p = seeded(c, current: ko2)
        var l = Ledger()
        for _ in 0..<3 {
            let r: SwitchPipeline.RequestResult = p.request(ja, layout: c)
            l.note(r)
        }
        l.note(p.completed(run: p.inFlightRun!, actual: ja, layout: c))
        #expect(l.exactlyOnce())
    }

    @Test func timeoutResolvesAndLateCompletionIsIgnored() {
        let c = two
        var p = seeded(c, current: ko2)
        var l = Ledger()
        l.note(p.press(.fn, actual: ko2, layout: c).request)
        l.note(p.press(.fn, actual: ko2, layout: c).request)
        let old = p.inFlightRun!
        let t = p.timedOut(run: old, actual: ja, layout: c)
        #expect(t.finished.count == 1)
        #expect(t.next?.id == ko2)
        l.note(t)
        let before = p
        let late = p.completed(run: old, actual: ja, layout: c)
        #expect(late.finished.isEmpty)
        #expect(late.next == nil)
        #expect(p == before)
        l.note(p.completed(run: p.inFlightRun!, actual: ko2, layout: c))
        #expect(l.exactlyOnce())
    }

    @Test func staleTimeoutIsIgnored() {
        let c = two
        var p = seeded(c, current: ko2)
        _ = p.press(.fn, actual: ko2, layout: c)
        let old = p.inFlightRun!
        _ = p.completed(run: old, actual: ja, layout: c)
        let t = p.timedOut(run: old, actual: ja, layout: c)
        #expect(t.finished.isEmpty)
        #expect(t.next == nil)
    }
}

@Suite struct SwitchPipelinePreviewTests {
    @Test func previewDoesNotMutate() {
        let c = three
        let p = seeded(c, current: ko2)
        let before = p
        #expect(p.preview(.fn, actual: ko2, layout: c) == .switchTo(ja))
        #expect(p == before)
    }

    @Test func previewMatchesNextPressWhileSwitching() {
        let c = three
        var p = seeded(c, current: ko2)
        _ = p.press(.fn, actual: ko2, layout: c)
        let before = p
        let preview = p.preview(.fn, actual: ko2, layout: c)
        #expect(preview == .switchTo(zh))
        #expect(p == before)
        #expect(p.press(.fn, actual: ko2, layout: c).decision == preview)
    }

    @Test func twoModesToggleWhileSwitching() {
        let c = two
        var p = seeded(c, current: ko2)
        _ = p.press(.fn, actual: ko2, layout: c)
        #expect(p.preview(.fn, actual: ko2, layout: c) == .switchTo(ko2))
    }

    @Test func noopAndPassThrough() {
        let p = SwitchPipeline()
        #expect(p.preview(.fn, actual: nil, layout: two) == .noop)
        let none = defaultLayout([Fx.abc])
        let q = seeded(none, current: abc)
        #expect(q.preview(.fn, actual: abc, layout: none) == .passThrough)
        // 한 칸짜리 fn 목록: 목록 안에서 누르면 다른 목록의 마지막 소스로 간다(D-07/D-08 이전 규칙과 다름).
        let one = defaultLayout([Fx.abc, Fx.ko2])
        let r = seeded(one, current: ko2)
        #expect(r.preview(.fn, actual: ko2, layout: one) == .switchTo(abc))
    }
}

/// D-46: 지정 소스로 바로 가는 미리보기. 실제 전환은 기존 `request`가 맡는다(상태를 바꾸지 않는다).
@Suite struct SwitchPipelineAssignedTests {
    /// caps [ABC], fn [JA], 지정 [KO].
    private var layout: KeyLayout {
        KeyLayout(caps: [abc], fn: [ja], assigned: [ko2], sources: [Fx.abc, Fx.ko2, Fx.ja], rule: .nextAfterLast)
    }

    @Test func previewAssignedReturnsSwitchWithoutChangingState() {
        let c = layout
        var p = seeded(c, current: abc)
        #expect(p.previewAssigned(ko2, actual: abc, layout: c) == .switchTo(ko2))
        #expect(p.inFlight == nil)
        #expect(p.queued == nil)
        #expect(p.tracker.last(in: .assigned) == nil)
        #expect(p.tracker.lastCaps == abc)
    }

    @Test func previewAssignedUsesPendingTarget() {
        // 진행 중 전환의 대상이 이미 R이면 다시 전환하지 않는다.
        let c = layout
        var p = seeded(c, current: abc)
        _ = p.request(ko2, layout: c)
        #expect(p.pendingTarget == ko2)
        #expect(p.previewAssigned(ko2, actual: abc, layout: c) == .noop)
    }

    @Test func previewAssignedNoopWhenTargetNotAssigned() {
        let c = layout
        var p = seeded(c, current: abc)
        #expect(p.previewAssigned(ja, actual: abc, layout: c) == .noop)
        #expect(p.previewAssigned(abc, actual: abc, layout: c) == .noop)
        // 현재 소스가 없으면 판정하지 않는다.
        #expect(SwitchPipeline().previewAssigned(ko2, actual: nil, layout: c) == .noop)
    }
}
