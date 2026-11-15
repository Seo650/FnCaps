import Carbon
import Foundation
import FnCapsCore

/// S1: a single TISSelectInputSource, then wait for landing.
public final class TISDirectStrategy: SwitchStrategy {
    public let name = "S1-TISDirect"
    public init() {}

    public func switchTo(
        _ target: SourceInfo, from origin: SourceInfo?, catalog: InputSourceCatalog,
        completion: @escaping (SwitchOutcome) -> Void
    ) {
        dispatchPrecondition(condition: .onQueue(.main))
        let start = CFAbsoluteTimeGetCurrent()
        guard let src = catalog.tisSource(for: target.id) else {
            completion(SwitchOutcome(tisLanded: false, tisLatencyMs: 0, notes: "source not found"))
            return
        }
        let status = TISSelectInputSource(src)
        LandingWaiter.wait(for: target.id, catalog: catalog, start: start) { landed, ms in
            completion(SwitchOutcome(tisLanded: landed, tisLatencyMs: ms, notes: "status=\(status)"))
        }
    }
}

/// S2: select, wait, select again (re-prime the IME), then wait for landing.
public final class TISReselectStrategy: SwitchStrategy {
    public let name = "S2-TISReselect"
    public var reselectDelayMs: Double = 30
    public init() {}

    public func switchTo(
        _ target: SourceInfo, from origin: SourceInfo?, catalog: InputSourceCatalog,
        completion: @escaping (SwitchOutcome) -> Void
    ) {
        dispatchPrecondition(condition: .onQueue(.main))
        let start = CFAbsoluteTimeGetCurrent()
        guard let src = catalog.tisSource(for: target.id) else {
            completion(SwitchOutcome(tisLanded: false, tisLatencyMs: 0, notes: "source not found"))
            return
        }
        let thirdParty = [target, origin].contains { s in
            guard let s else { return false }
            return !(s.bundleID ?? "com.apple.").hasPrefix("com.apple.")
        }
        let delay = thirdParty ? max(reselectDelayMs, 50) : reselectDelayMs
        let first = TISSelectInputSource(src)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay / 1000) {
            let second = catalog.tisSource(for: target.id).map { TISSelectInputSource($0) } ?? first
            LandingWaiter.wait(for: target.id, catalog: catalog, start: start) { landed, ms in
                completion(
                    SwitchOutcome(
                        tisLanded: landed, tisLatencyMs: ms,
                        notes: "status=\(first)/\(second) delay=\(delay)ms"))
            }
        }
    }
}
