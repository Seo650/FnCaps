import Testing
@testable import FnCapsSystem

@Suite(.serialized)
struct GlobeSettingReaderSmokeTests {
    @Test func readsWithoutCrash() {
        let v = GlobeSettingReader.readUsage()
        if let v { #expect((0...3).contains(v)) }
    }
}
