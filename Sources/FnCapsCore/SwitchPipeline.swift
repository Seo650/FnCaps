import Foundation

/// Pure model of "one switch in flight, at most one queued".
///
/// Decisions use the PENDING target (queued ?? in-flight) as the current source, not the
/// not-yet-updated system source. User rule (2026-10-25): with a 2-entry fn list, fn twice
/// quickly goes ko -> ja -> ko; N quick presses advance N entries of the key list.
/// Only one run is active at a time because S7 posts the #60 chord and two chords must
/// not overlap. A queued request is replaced by newer ones (coalescing).
/// The tracker is a projection of the user's intent while a queue exists; only when
/// nothing is queued does the actual source resync it.
///
/// Invariant: every `Token` issued by `request`/`press` is returned exactly once, either
/// in a `superseded` list or in `Completion.finished` (finish, flush or timeout).
/// A `RunID` identifies one strategy run; completions of any run other than the current
/// in-flight run are ignored (late completion after a timeout).
public struct SwitchPipeline: Equatable, Sendable {
    public struct Token: Hashable, Sendable { public let raw: Int }
    public struct RunID: Hashable, Sendable { public let raw: Int }

    public struct Run: Equatable, Sendable {
        public let id: SourceID
        public let run: RunID
    }

    public enum RequestResult: Equatable, Sendable {
        /// Nothing was in flight: start this run now.
        case start(SourceID, RunID, Token)
        /// Waiting behind the in-flight run. `superseded` tokens were replaced in the queue.
        case queued(Token, superseded: [Token])
        /// Same destination as the in-flight run: shares its outcome. Any queue is dropped.
        case joined(Token, superseded: [Token])
    }

    public struct Completion: Equatable, Sendable {
        public let finished: [Token]
        public let next: Run?
    }

    public private(set) var tracker = ListTracker()
    public private(set) var inFlight: SourceID?
    public private(set) var inFlightRun: RunID?
    public private(set) var queued: SourceID?
    private var inFlightTokens: [Token] = []
    private var queuedTokens: [Token] = []
    private var tokenCounter = 0
    private var runCounter = 0

    public init() {}

    public var isSwitching: Bool { inFlight != nil }
    public var pendingTarget: SourceID? { queued ?? inFlight }

    public mutating func seed(current: SourceID?, history: [SourceID], layout: KeyLayout) {
        tracker.seed(current: current, history: history, layout: layout)
    }

    public mutating func reconcile(layout: KeyLayout) {
        tracker.reconcile(layout: layout)
    }

    public mutating func observeUser(selected: SourceID, layout: KeyLayout) {
        if isSwitching { return }
        tracker.observe(selected: selected, layout: layout, inFlight: false)
    }

    public mutating func request(_ id: SourceID, layout: KeyLayout) -> RequestResult {
        tracker.observe(selected: id, layout: layout, inFlight: false)
        tokenCounter += 1
        let token = Token(raw: tokenCounter)
        guard let current = inFlight else {
            let run = newRun()
            inFlight = id
            inFlightRun = run
            inFlightTokens = [token]
            return .start(id, run, token)
        }
        let superseded = queuedTokens
        queuedTokens = []
        if id == current {
            queued = nil
            inFlightTokens.append(token)
            return .joined(token, superseded: superseded)
        }
        queued = id
        queuedTokens = [token]
        return .queued(token, superseded: superseded)
    }

    public mutating func press(
        _ key: TriggerKey, actual: SourceID?, layout: KeyLayout
    ) -> (decision: Decision, request: RequestResult?) {
        guard let current = pendingTarget ?? actual else { return (.noop, nil) }
        let decision = ListSwitcher.decide(key, current: current, layout: layout, tracker: tracker)
        guard case .switchTo(let id) = decision else { return (decision, nil) }
        return (decision, request(id, layout: layout))
    }

    /// S10은 fn 해제 콜백 안에서 OS에 넘길지 정하기 전에 목표를 알아야 하므로 커밋 없이 결정만 본다.
    /// press와 같은 current 선택과 같은 ListSwitcher 결정을 쓰되 상태를 바꾸지 않는다.
    public func preview(
        _ key: TriggerKey, actual: SourceID?, layout: KeyLayout
    ) -> Decision {
        guard let current = pendingTarget ?? actual else { return .noop }
        return ListSwitcher.decide(key, current: current, layout: layout, tracker: tracker)
    }

    /// D-46: 지정 소스로 바로 가는 목표만 본다. `press`와 같은 current 선택(pendingTarget ?? actual)을
    /// 쓰고 상태를 바꾸지 않는다. 실제 전환은 기존 `request`가 맡는다(04-21).
    public func previewAssigned(_ id: SourceID, actual: SourceID?, layout: KeyLayout) -> Decision {
        guard let current = pendingTarget ?? actual else { return .noop }
        return ListSwitcher.decideAssigned(id, current: current, layout: layout)
    }

    public mutating func completed(run: RunID, actual: SourceID?, layout: KeyLayout) -> Completion {
        guard run == inFlightRun else { return Completion(finished: [], next: nil) }
        var finished = inFlightTokens
        inFlight = nil
        inFlightRun = nil
        inFlightTokens = []
        if let next = queued {
            let tokens = queuedTokens
            queued = nil
            queuedTokens = []
            if next == actual {
                finished += tokens
                return Completion(finished: finished, next: nil)
            }
            let newRun = newRun()
            inFlight = next
            inFlightRun = newRun
            inFlightTokens = tokens
            return Completion(finished: finished, next: Run(id: next, run: newRun))
        }
        if let actual { tracker.observe(selected: actual, layout: layout, inFlight: false) }
        return Completion(finished: finished, next: nil)
    }

    /// Watchdog: resolves the run like a completion; the caller adds the `timeout` note.
    public mutating func timedOut(run: RunID, actual: SourceID?, layout: KeyLayout) -> Completion {
        completed(run: run, actual: actual, layout: layout)
    }

    private mutating func newRun() -> RunID {
        runCounter += 1
        return RunID(raw: runCounter)
    }
}
