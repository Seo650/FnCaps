import Testing
@testable import FnCapsCore

@Suite struct GlobeSettingAdvisorTests {
    @Test func noticeUnlessChangeInputSource() {
        #expect(!GlobeSettingAdvisor.needsNotice(usage: 1))
        for v in [0, 2, 3, 99] { #expect(GlobeSettingAdvisor.needsNotice(usage: v)) }
        #expect(GlobeSettingAdvisor.needsNotice(usage: nil))
    }
}
