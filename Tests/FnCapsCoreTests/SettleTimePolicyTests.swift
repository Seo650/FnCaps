import Foundation
import Testing
@testable import FnCapsCore

@Suite struct SettleTimePolicyTests {
    @Test func clamps() {
        #expect(SettleTimePolicy.clamp(200) == 150)
        #expect(SettleTimePolicy.clamp(-5) == 0)
        #expect(SettleTimePolicy.clamp(80) == 80)
    }

    @Test func decodedSanitizes() {
        #expect(SettleExceptions.decoded(Data("bad".utf8)) == [])
        let raw = [
            SettleException(bundleID: "com.a", ms: 500, off: true), SettleException(bundleID: "", ms: 1, off: true),
            SettleException(bundleID: "bad id!", ms: 1, off: true), SettleException(bundleID: "com.a", ms: 9, off: true),
        ]
        let out = SettleExceptions.decoded(SettleExceptions.encoded(raw))
        #expect(out == [SettleException(bundleID: "com.a", ms: 150, off: true)])
        let many = (0..<120).map { SettleException(bundleID: "app\($0)", ms: 1, off: true) }
        #expect(SettleExceptions.decoded(SettleExceptions.encoded(many)).count == 100)
    }

    @Test func adding() {
        let base = [SettleException(bundleID: "a", ms: 5, off: true)]
        let same = SettleExceptions.adding(base, bundleID: "a")
        #expect(same?.list == base && same?.index == 0)
        let new = SettleExceptions.adding(base, bundleID: "b")
        #expect(new?.index == 1 && new?.list.count == 2)
        #expect(SettleExceptions.adding(base, bundleID: "bad id") == nil)
    }
}
