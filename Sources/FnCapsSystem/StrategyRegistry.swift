import Foundation

public enum StrategyRegistry {
    public static let names: [String] = [
        "S1-TISDirect", "S2-TISReselect", "S3-PrimePulse", "S4a-CapsRefreshEvent",
        "S4b-CapsRefreshLock", "S5a-TempWindow-1ms", "S5b-TempWindow-150ms", "S6-FocusedAppTSM",
        "S7-NativeHop",
    ]

    /// Diagnostic arms for SWITCH-05 (S7 hop variants). S8 is built only by SwitchBench.makeGuarded with a target pid. Not part of `names` (S7-NativeHop itself is in `names`).
    public static let diagnosticNames: [String] = NativeHopStrategy.variantNames.filter { $0 != "S7-NativeHop" }

    /// S6 crashed the process on macOS 27.0.1 (SIGBUS in SLPSGetKeyFocusProcess, reached through
    /// CPSGetKeyFocusProcess with an assumed private-SPI signature; see 01-FINDINGS.md). The code is kept
    /// for the record but it must never run: every bench matrix and the dev menu use `runnableNames`.
    public static let unsafeNames: Set<String> = ["S6-FocusedAppTSM"]

    /// Strategies that are safe to execute (all matrices, menus and bench picks use this).
    public static var runnableNames: [String] { names.filter { !unsafeNames.contains($0) } }

    public static func make(named: String) -> SwitchStrategy? {
        if unsafeNames.contains(named) { return nil }
        switch named {
        case "S1-TISDirect": return TISDirectStrategy()
        case "S2-TISReselect": return TISReselectStrategy()
        case "S3-PrimePulse": return PrimePulseStrategy()
        case "S4a-CapsRefreshEvent": return CapsRefreshEventStrategy()
        case "S4b-CapsRefreshLock": return CapsRefreshLockStrategy()
        case "S5a-TempWindow-1ms": return TempWindowStrategy(holdMs: 1)
        case "S5b-TempWindow-150ms": return TempWindowStrategy(holdMs: 150)
        default: return NativeHopStrategy.make(named: named)
        }
    }

    public static func makeAll() -> [SwitchStrategy] { runnableNames.compactMap { make(named: $0) } }

    /// Strategy name to use at launch: the stored default only if it is runnable, else `DefaultStrategy.name`.
    public static func launchName(stored: String?) -> String {
        if let stored, runnableNames.contains(stored) { return stored }
        return DefaultStrategy.name
    }
}
