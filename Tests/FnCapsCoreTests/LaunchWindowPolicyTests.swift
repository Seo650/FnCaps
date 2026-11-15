import Testing
@testable import FnCapsCore

@Suite struct LaunchWindowPolicyTests {
    @Test func firstLaunchAlwaysShows() {
        #expect(LaunchWindowPolicy.shouldShow(firstLaunch: true, restarted: false, loginItem: true))
    }

    @Test func restartShowsEvenAtLogin() {
        #expect(LaunchWindowPolicy.shouldShow(firstLaunch: false, restarted: true, loginItem: true))
    }

    @Test func directOpenShows() {
        #expect(LaunchWindowPolicy.shouldShow(firstLaunch: false, restarted: false, loginItem: false))
    }

    @Test func loginLaunchStaysQuiet() {
        #expect(!LaunchWindowPolicy.shouldShow(firstLaunch: false, restarted: false, loginItem: true))
    }

    @Test func unknownLaunchShows() {
        #expect(LaunchWindowPolicy.shouldShow(firstLaunch: false, restarted: false, loginItem: nil))
    }
}
