import Testing
@testable import FnCapsCore

@Suite struct GlobeSettingAdvisorTests {
    @Test func noticeUnlessChangeInputSource() {
        #expect(!GlobeSettingAdvisor.needsNotice(usage: 1))
        for v in [0, 2, 3, 99] { #expect(GlobeSettingAdvisor.needsNotice(usage: v)) }
        /// 새 계정은 키가 없다. 1로 본다(D-10)
        #expect(!GlobeSettingAdvisor.needsNotice(usage: nil))
    }

    @Test func effectiveUsageTreatsNilAsChangeInputSource() {
        // 값이 없는 새 계정은 1(🌐 키로 입력 소스 변경)로 본다(D-10).
        #expect(FnRoutePolicy.effectiveUsage(nil) == FnRoutePolicy.changeInputSourceUsage)
        #expect(FnRoutePolicy.effectiveUsage(0) == 0)
        #expect(FnRoutePolicy.effectiveUsage(3) == 3)
    }
}
