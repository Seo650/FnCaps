import Foundation

/// Decision for waiting until a given app is frontmost again (e.g. after our own temporary window
/// was shown, or before posting a guarded key). Pure, so it can be tested without AppKit.
public enum FocusWaitPolicy {
    public enum Decision: Equatable, Sendable { case satisfied, keepWaiting, timedOut }

    /// `expectedPid` must be a real pid (> 0); otherwise nothing can ever be satisfied.
    /// Our own pid is never accepted unless it is the expected one.
    public static func decide(
        frontmostPid: Int32?, expectedPid: Int32, ownPid: Int32, elapsedMs: Double, maxMs: Double
    ) -> Decision {
        if expectedPid > 0, frontmostPid == expectedPid, (expectedPid != ownPid || frontmostPid == ownPid) {
            return .satisfied
        }
        return elapsedMs >= maxMs ? .timedOut : .keepWaiting
    }
}
