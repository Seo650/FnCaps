import Testing
@testable import FnCapsCore

@Suite struct GuardPolicyTests {
    @Test func policy() {
        #expect(GuardPolicy.shouldPost(.anyApp, frontmostPid: nil))
        #expect(GuardPolicy.shouldPost(.anyApp, frontmostPid: 5))
        #expect(GuardPolicy.shouldPost(.pid(5), frontmostPid: 5))
        #expect(GuardPolicy.shouldPost(.pid(5), frontmostPid: 6) == false)
        #expect(GuardPolicy.shouldPost(.pid(5), frontmostPid: nil) == false)
    }

    @Test func unsetPidNeverMatches() {
        #expect(GuardPolicy.shouldPost(.pid(0), frontmostPid: 0) == false)
        #expect(GuardPolicy.shouldPost(.pid(-1), frontmostPid: -1) == false)
    }
}
