import Testing
@testable import FnCapsCore

@Suite struct LandingPollTests {
    @Test func notificationIsOnlyAnExtraWakeUpSoPollingStaysAtFiveMilliseconds() {
        #expect(LandingPoll.notificationFirst == true)
        #expect(LandingPoll.pollMs == 5)
        #expect(LandingPoll.fallbackPollMs == 5)
    }

    @Test func fallbackMatchesTheLegacyInterval() {
        #expect(LandingPoll.legacyPollMs == 5)
        #expect(LandingPoll.legacyPollMs == LandingPoll.fallbackPollMs)
    }
}
