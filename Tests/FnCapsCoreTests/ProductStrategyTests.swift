import Testing
@testable import FnCapsSystem

@Suite struct ProductStrategyTests {
    @Test func nilResolvesToS10() {
        #expect(ProductStrategy.resolve(stored: nil) == "S10-RealGlobe")
        #expect(ProductStrategy.defaultName == "S10-RealGlobe")
        #expect(ProductStrategy.make(named: ProductStrategy.defaultName) is RealGlobeStrategy)
    }

    @Test func s2IsAllowed() {
        #expect(ProductStrategy.resolve(stored: "S2-TISReselect") == "S2-TISReselect")
        #expect(ProductStrategy.make(named: "S2-TISReselect") is TISReselectStrategy)
    }

    @Test func spikeAndGarbageNamesFallBack() {
        for bad in [
            "S3-PrimePulse", "S4a-CapsRefreshEvent", "S4b-CapsRefreshLock", "S9-HotkeyOnly",
            "S7-NativeHop", "S7g-NativeHopGated", "S1-TISDirect", "S5a-TempWindow-1ms", "garbage", "",
        ] {
            #expect(ProductStrategy.resolve(stored: bad) == "S10-RealGlobe")
        }
    }

    @Test func allowListNamesBuildThemselves() {
        #expect(ProductStrategy.allowedNames == ["S10-RealGlobe", "S2-TISReselect"])
        for n in ProductStrategy.allowedNames {
            #expect(ProductStrategy.make(named: n).name == n)
        }
    }
}
