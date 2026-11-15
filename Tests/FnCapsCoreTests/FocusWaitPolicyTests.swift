import Testing
@testable import FnCapsCore

@Suite struct FocusWaitPolicyTests {
    @Test func satisfiedWhenExpectedIsFront() {
        #expect(FocusWaitPolicy.decide(frontmostPid: 5, expectedPid: 5, ownPid: 9, elapsedMs: 0, maxMs: 300) == .satisfied)
    }
    @Test func waitsWhileOwnAppIsFront() {
        #expect(FocusWaitPolicy.decide(frontmostPid: 9, expectedPid: 5, ownPid: 9, elapsedMs: 100, maxMs: 300) == .keepWaiting)
    }
    @Test func timesOut() {
        #expect(FocusWaitPolicy.decide(frontmostPid: 9, expectedPid: 5, ownPid: 9, elapsedMs: 300, maxMs: 300) == .timedOut)
        #expect(FocusWaitPolicy.decide(frontmostPid: nil, expectedPid: 5, ownPid: 9, elapsedMs: 400, maxMs: 300) == .timedOut)
    }
    @Test func invalidExpectedNeverSatisfied() {
        #expect(FocusWaitPolicy.decide(frontmostPid: 0, expectedPid: 0, ownPid: 9, elapsedMs: 0, maxMs: 300) == .keepWaiting)
        #expect(FocusWaitPolicy.decide(frontmostPid: -1, expectedPid: -1, ownPid: 9, elapsedMs: 300, maxMs: 300) == .timedOut)
    }
}
