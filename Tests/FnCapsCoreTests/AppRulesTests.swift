import Foundation
import Testing
@testable import FnCapsCore

/// 앱별 설정은 「FnCaps 끄기」 목록이다(FINAL-REVIEW §3-1 B, D-39, 2026-11-11 앱별 대기 시간 삭제).
@Suite struct AppRulesTests {
    /// 옛 「대기 시간만」 행은 끄라는 뜻이 아니었으므로 읽을 때 버린다.
    @Test func legacyTimeOnlyRowIsDropped() {
        let data = Data(#"[{"bundleID":"com.apple.TextEdit","ms":120}]"#.utf8)
        #expect(SettleExceptions.decoded(data).isEmpty)
        let mixed = Data(#"[{"bundleID":"a.ms","ms":40,"off":false},{"bundleID":"a.off","ms":40,"off":true}]"#.utf8)
        #expect(SettleExceptions.decoded(mixed).map(\.bundleID) == ["a.off"])
    }

    @Test func offSurvivesRoundTrip() {
        let list = [SettleException(bundleID: "com.apple.TextEdit", ms: 40, off: true)]
        let out = SettleExceptions.decoded(SettleExceptions.encoded(list))
        #expect(out == list)
    }

    @Test func isOffOnlyForListedFrontApp() {
        let list = [SettleException(bundleID: "a.off", ms: 10, off: true)]
        #expect(SettleTimePolicy.isOff(exceptions: list, frontBundleID: "a.off"))
        #expect(!SettleTimePolicy.isOff(exceptions: list, frontBundleID: "other"))
        #expect(!SettleTimePolicy.isOff(exceptions: list, frontBundleID: nil))
        #expect(!SettleTimePolicy.isOff(exceptions: [], frontBundleID: "a.off"))
    }

    @Test func addedRowIsOff() {
        let added = SettleExceptions.adding([], bundleID: "a.b")
        #expect(added?.list.first?.off == true)
    }
}
