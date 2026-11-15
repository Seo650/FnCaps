import Foundation

/// Product-side strategy selection (D-17).
/// Default is S10-RealGlobe (user decision 2026-10-29, GAP-09 Finder comparison table): the OS performs
/// the switch natively. S2-TISReselect is the escape hatch. The `strategyOverride` defaults key accepts
/// only these two; any other value is ignored (ASVS V5). S7/S3/S4/S9 live in the spike
/// `StrategyRegistry` only.
public enum ProductStrategy {
    public static let defaultName = "S10-RealGlobe"
    public static let allowedNames = ["S10-RealGlobe", "S2-TISReselect"]
    public static let overrideDefaultsKey = "strategyOverride"

    public static func resolve(stored: String?) -> String {
        guard let stored, allowedNames.contains(stored) else { return defaultName }
        return stored
    }

    public static func make(named: String) -> SwitchStrategy {
        switch resolve(stored: named) {
        case "S2-TISReselect": return TISReselectStrategy()
        default: return RealGlobeStrategy()
        }
    }
}
