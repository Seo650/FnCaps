import Testing
@testable import FnCapsCore

/// 충돌 앱 감지(D-40, 04-RESEARCH-ADDENDUM §2·§4).
@Suite struct ConflictAppsTests {
    @Test func detectsGksdud() {
        #expect(ConflictApps.detected(runningBundleIDs: ["com.apple.finder", "io.gksdud.inputswitch"]) == ["gksdud"])
    }

    @Test func nothingWhenAbsent() {
        #expect(ConflictApps.detected(runningBundleIDs: ["com.apple.finder"]) == [])
        #expect(ConflictApps.detected(runningBundleIDs: []) == [])
    }

    @Test func duplicateIDsCountOnce() {
        #expect(ConflictApps.detected(runningBundleIDs: ["io.gksdud.inputswitch", "io.gksdud.inputswitch"]) == ["gksdud"])
    }

    @Test func detectsKarabinerCoreService() {
        #expect(ConflictApps.detected(runningBundleIDs: ["org.pqrs.Karabiner-Core-Service"]) == ["Karabiner-Elements"])
    }

    @Test func detectsKarabinerByPrefix() {
        #expect(ConflictApps.detected(runningBundleIDs: ["org.pqrs.Karabiner-NotificationWindow"]) == ["Karabiner-Elements"])
    }

    @Test func manyKarabinerProcessesCountOnce() {
        let ids = ["org.pqrs.Karabiner-Core-Service", "org.pqrs.Karabiner-NotificationWindow", "org.pqrs.Karabiner-Elements.Settings"]
        #expect(ConflictApps.detected(runningBundleIDs: ids) == ["Karabiner-Elements"])
    }

    @Test func otherPqrsAppIsNotKarabiner() {
        #expect(ConflictApps.detected(runningBundleIDs: ["org.pqrs.SomethingElse"]) == [])
    }

    @Test func bothInWarningOrder() {
        #expect(ConflictApps.detected(runningBundleIDs: ["io.gksdud.inputswitch", "org.pqrs.Karabiner-Core-Service"])
            == ["Karabiner-Elements", "gksdud"])
    }
}
