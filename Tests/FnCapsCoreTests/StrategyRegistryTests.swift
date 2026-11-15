import Testing
@testable import FnCapsSystem

@Suite struct StrategyRegistryTests {
    @Test func parseFixture() {
        let e: [String: Any] = [
            "enabled": 1,
            "value": ["parameters": [32, 49, 262144], "type": "standard"] as [String: Any],
        ]
        #expect(SymbolicHotkeyReader.parse(e)
            == SymbolicHotkey(enabled: true, ascii: 32, keyCode: 49, modifierMask: 262144))
    }

    @Test func parseRejectsBadShapes() {
        #expect(SymbolicHotkeyReader.parse([:]) == nil)
        let short: [String: Any] = ["enabled": 1, "value": ["parameters": [32, 49]] as [String: Any]]
        #expect(SymbolicHotkeyReader.parse(short) == nil)
    }

    @Test func liveHotkey60() {
        // Baseline on this Mac: Ctrl+Space enabled. Nil is tolerated (pref absent), not a failure.
        if let hk = SymbolicHotkeyReader.read(id: 60) { #expect(hk.keyCode >= 0) }
    }

    @MainActor @Test func registry() {
        #expect(StrategyRegistry.names.count == 9)
        #expect(Set(StrategyRegistry.names).count == 9)
        #expect(StrategyRegistry.make(named: "S6-FocusedAppTSM") == nil)
        #expect(StrategyRegistry.runnableNames.count == 8)
        for n in StrategyRegistry.runnableNames { #expect(StrategyRegistry.make(named: n)?.name == n) }
        #expect(StrategyRegistry.make(named: DefaultStrategy.name) != nil)
        #expect(StrategyRegistry.make(named: "nope") == nil)
        #expect(StrategyRegistry.makeAll().count == StrategyRegistry.runnableNames.count)
    }

    @Test func launchNameValidation() {
        #expect(StrategyRegistry.launchName(stored: nil) == DefaultStrategy.name)
        #expect(StrategyRegistry.launchName(stored: "S6-FocusedAppTSM") == DefaultStrategy.name)
        #expect(StrategyRegistry.launchName(stored: "S8-AXReturn") == DefaultStrategy.name)
        #expect(StrategyRegistry.launchName(stored: "garbage") == DefaultStrategy.name)
        #expect(StrategyRegistry.launchName(stored: "S5a-TempWindow-1ms") == "S5a-TempWindow-1ms")
    }

    @MainActor @Test func diagnosticStrategies() {
        #expect(StrategyRegistry.diagnosticNames.count == 4)
        #expect(StrategyRegistry.make(named: "S8-AXReturn") == nil)
        #expect(!StrategyRegistry.diagnosticNames.contains("S8-AXReturn"))
        for n in StrategyRegistry.diagnosticNames {
            #expect(StrategyRegistry.make(named: n)?.name == n)
            #expect(!StrategyRegistry.names.contains(n))
        }
        #expect(StrategyRegistry.names.count == 9)
    }
}
