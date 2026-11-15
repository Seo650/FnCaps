import Testing
@testable import FnCapsCore

@Suite struct PermissionTraceTests {
    @Test func firstRecordFormats() {
        var t = PermissionTrace()
        #expect(t.record(ax: false, probe: false, tapInstalled: false, tapEnabled: nil)
            == "permission ax=false probe=false tap=false tapEnabled=-")
    }

    @Test func duplicateSuppressed() {
        var t = PermissionTrace()
        _ = t.record(ax: false, probe: false, tapInstalled: false, tapEnabled: nil)
        #expect(t.record(ax: false, probe: false, tapInstalled: false, tapEnabled: nil) == nil)
    }

    @Test func axTrueProbeFalseDistinguished() {
        var t = PermissionTrace()
        _ = t.record(ax: false, probe: false, tapInstalled: false, tapEnabled: nil)
        #expect(t.record(ax: true, probe: false, tapInstalled: false, tapEnabled: nil)
            == "permission ax=true probe=false tap=false tapEnabled=-")
    }

    @Test func installedTapHasNoProbe() {
        var t = PermissionTrace()
        #expect(t.record(ax: true, probe: nil, tapInstalled: true, tapEnabled: true)
            == "permission ax=true probe=- tap=true tapEnabled=true")
    }

    @Test func revertEmitsAgain() {
        var t = PermissionTrace()
        _ = t.record(ax: true, probe: false, tapInstalled: false, tapEnabled: nil)
        _ = t.record(ax: false, probe: false, tapInstalled: false, tapEnabled: nil)
        #expect(t.record(ax: true, probe: false, tapInstalled: false, tapEnabled: nil) != nil)
    }
}
