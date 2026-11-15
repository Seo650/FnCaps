import Foundation

/// Decides whether typed keys are held back while an input-source switch settles, keeping typing order.
///
/// Right after a programmatic switch the focused app's input context lags the system source for a few
/// tens of ms; keys typed in that window reach the previous IME. Two states keep keys held:
/// - holding: waiting for the switch to settle.
/// - draining: the owner re-posted held events and waits for them to pass the tap again (the echo).
///   Until the re-posted events come back through the tap, new real keys are held too, so a real key
///   can never overtake a re-posted one. 재게시분이 탭을 다시 지나기 전에는 새 키도 붙잡아 순서를 지킨다.
/// Both are bounded by `maxMs` and `capacity` so a stuck switch or a lost echo can never eat typing.
public struct KeyHold: Equatable, Sendable {
    public enum Verdict: Equatable, Sendable {
        case pass
        case capture
        /// Limit reached: capture this event too, and the owner re-posts everything held, in order, now.
        case captureThenFlush
    }

    public var maxMs: Double
    public var capacity: Int
    public private(set) var isHolding = false
    public private(set) var count = 0
    /// Re-posted events that have not yet come back through the tap.
    public private(set) var inFlight = 0
    /// False after an echo wait timed out: later echoes are not awaited until the next `begin`.
    public private(set) var echoTrusted = true
    private var startedAt: TimeInterval = 0
    private var drainStartedAt: TimeInterval = 0

    public init(maxMs: Double = 200, capacity: Int = 32) {
        self.maxMs = maxMs
        self.capacity = capacity
    }

    public var isBusy: Bool { isHolding || inFlight > 0 }

    /// Starts (or extends) a hold. Never drops what is already held or in flight.
    public mutating func begin(now: TimeInterval) {
        isHolding = true
        startedAt = now
        echoTrusted = true
    }

    /// The owner re-posted `posted` held events.
    public mutating func flushed(posted: Int, now: TimeInterval) {
        count = 0
        isHolding = false
        if echoTrusted, posted > 0 {
            inFlight += posted
            drainStartedAt = now
        }
    }

    /// A re-posted event passed the tap again. True when the owner must re-post what was held meanwhile.
    public mutating func echoSeen() -> Bool {
        guard inFlight > 0 else { return false }
        inFlight = max(0, inFlight - 1)
        return inFlight == 0 && count > 0
    }

    /// True when held keys have waited past `maxMs` and the owner must release them now.
    public mutating func expire(now: TimeInterval) -> Bool {
        guard count > 0 else { return false }
        if isHolding {
            return (now - startedAt) * 1000 >= maxMs
        }
        if inFlight > 0, (now - drainStartedAt) * 1000 >= maxMs {
            echoTrusted = false
            inFlight = 0
            return true
        }
        return false
    }

    public mutating func reset() {
        isHolding = false
        count = 0
        inFlight = 0
        echoTrusted = true
        startedAt = 0
        drainStartedAt = 0
    }

    /// `isKey`: keyDown/keyUp of a non-Globe key. Modifiers, mouse and system events always pass.
    public mutating func classify(isKey: Bool, now: TimeInterval) -> Verdict {
        guard isKey else { return .pass }
        if isHolding {
            let over = (now - startedAt) * 1000 >= maxMs || count >= capacity
            count += 1
            if over {
                isHolding = false
                return .captureThenFlush
            }
            return .capture
        }
        if inFlight > 0 {
            if (now - drainStartedAt) * 1000 >= maxMs {
                echoTrusted = false
                inFlight = 0
                count += 1
                return .captureThenFlush
            }
            let over = count >= capacity
            count += 1
            return over ? .captureThenFlush : .capture
        }
        return .pass
    }
}
