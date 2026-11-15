import Foundation
import FnCapsCore

/// S6 is disabled. It used private SPI (CPSGetKeyFocusProcess and a per-process TSM message port) and crashed
/// the process with SIGBUS on macOS 27.0.1 (01-08, see 01-FINDINGS.md). All SPI code was deleted; the class and
/// name remain only for the record. `StrategyRegistry` never builds it.
public final class FocusedAppTSMStrategy: SwitchStrategy {
    public let name = "S6-FocusedAppTSM"
    public init() {}

    public func switchTo(
        _ target: SourceInfo, from origin: SourceInfo?, catalog: InputSourceCatalog,
        completion: @escaping (SwitchOutcome) -> Void
    ) {
        completion(SwitchOutcome(
            tisLanded: false, tisLatencyMs: 0, notes: "S6 disabled: crashed on macOS 27.0.1 (01-08)"))
    }
}
