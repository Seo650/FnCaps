import AppKit
import Foundation
import FnCapsCore

/// S7 family. Triggers the user's own "select previous input source" shortcut (hotkey #60, read only) so the
/// OS performs a native switch that commits the composition as shown, then runs S5a to the real target.
/// Never posts Return or printable keys. Never writes preferences.
public final class NativeHopStrategy: SwitchStrategy {
    public let name: String
    public let settleMs: Double
    public let explicitModifiers: Bool
    public let gated: Bool
    /// Posting scope. Decision: in the product S7 posts only the #60 chord read from the user's own settings
    /// (never Return or printable keys), which is exactly what the user's shortcut does in the frontmost app,
    /// so `.anyApp` is the correct default. Bench and the real-app menu set `.pid(...)`.
    public var postTarget: PostTarget = .anyApp
    /// Gated variants hop only when this returns true (nil means true).
    public var composingHint: (() -> Bool)?

    public init(name: String, settleMs: Double, explicitModifiers: Bool, gated: Bool) {
        self.name = name
        self.settleMs = settleMs
        self.explicitModifiers = explicitModifiers
        self.gated = gated
    }

    public static let variantNames = [
        "S7-NativeHop", "S7-NativeHop-w0", "S7-NativeHop-w50", "S7-NativeHop-flagsOnly", "S7g-NativeHopGated",
    ]

    public static func make(named: String) -> NativeHopStrategy? {
        switch named {
        case "S7-NativeHop": return NativeHopStrategy(name: named, settleMs: 20, explicitModifiers: true, gated: false)
        case "S7-NativeHop-w0": return NativeHopStrategy(name: named, settleMs: 0, explicitModifiers: true, gated: false)
        case "S7-NativeHop-w50": return NativeHopStrategy(name: named, settleMs: 50, explicitModifiers: true, gated: false)
        case "S7-NativeHop-flagsOnly":
            return NativeHopStrategy(name: named, settleMs: 20, explicitModifiers: false, gated: false)
        case "S7g-NativeHopGated": return NativeHopStrategy(name: named, settleMs: 20, explicitModifiers: true, gated: true)
        default: return nil
        }
    }

    public func switchTo(
        _ target: SourceInfo, from origin: SourceInfo?, catalog: InputSourceCatalog,
        completion: @escaping (SwitchOutcome) -> Void
    ) {
        dispatchPrecondition(condition: .onQueue(.main))
        let start = CFAbsoluteTimeGetCurrent()
        func ms() -> Double { (CFAbsoluteTimeGetCurrent() - start) * 1000 }

        let wantHop = !gated || (composingHint?() ?? true)
        var skipReason: String?
        var hotkey: SymbolicHotkey?
        if !wantHop {
            skipReason = "not_composing"
        } else {
            switch SymbolicHotkeyReader.status(id: 60) {
            case .usable(let hk): hotkey = hk
            case let other: skipReason = other.note(id: 60)
            }
        }

        let secondLeg: (String) -> Void = { prefix in
            TempWindowStrategy(holdMs: 1).switchTo(target, from: origin, catalog: catalog) { inner in
                completion(SwitchOutcome(
                    tisLanded: inner.tisLanded, tisLatencyMs: ms(),
                    notes: "\(prefix) explicit=\(self.explicitModifiers) then: \(inner.notes)"))
            }
        }

        guard let hk = hotkey else {
            secondLeg("hop=skipped(\(skipReason ?? "unknown")) hop_ms=0 settle=0")
            return
        }
        let postHop: () -> Void = { [self] in
        let before = catalog.currentID()
        SyntheticKeys.postHotkey(
            keyCode: CGKeyCode(hk.keyCode), modifierMask: hk.modifierMask, explicitModifiers: explicitModifiers)
        let hopStart = CFAbsoluteTimeGetCurrent()
        var timedOut = false
        func finishHop() {
            let hopMs = (CFAbsoluteTimeGetCurrent() - hopStart) * 1000
            let note = "hop=yes\(timedOut ? "(hop_timeout)" : "") hop_ms=\(Int(hopMs)) settle=\(Int(self.settleMs))"
            DispatchQueue.main.asyncAfter(deadline: .now() + self.settleMs / 1000) { secondLeg(note) }
        }
        let timer = Timer(timeInterval: 0.002, repeats: true) { t in
            if catalog.currentID() != before {
                t.invalidate()
                finishHop()
            } else if (CFAbsoluteTimeGetCurrent() - hopStart) * 1000 >= 300 {
                t.invalidate()
                timedOut = true
                finishHop()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        }

        func guarded() {
            switch postTarget {
            case .anyApp: postHop()
            case .pid(let pid):
                if pid == ProcessInfo.processInfo.processIdentifier {
                    completion(SwitchOutcome(tisLanded: false, tisLatencyMs: 0, notes: "guard_blocked own_pid")); return
                }
                // Frontmost may still be our own temp window returning focus: wait briefly first.
                FocusWaiter.wait(forPid: pid) { ok, waited in
                    if ok, GuardPolicy.shouldPost(self.postTarget, frontmostPid: NSWorkspace.shared.frontmostApplication?.processIdentifier) {
                        postHop()
                    } else {
                        completion(SwitchOutcome(tisLanded: false, tisLatencyMs: 0,
                            notes: "guard_blocked front=\(FocusWaiter.describeFrontmost()) waited_ms=\(Int(waited))"))
                    }
                }
            }
        }
        guarded()
    }
}

/// Polls the frontmost app (5 ms) until `pid` is frontmost, using the pure `FocusWaitPolicy`.
public enum FocusWaiter {
    public static func wait(
        forPid pid: Int32, maxMs: Double = 300, completion: @escaping (_ ok: Bool, _ waitedMs: Double) -> Void
    ) {
        dispatchPrecondition(condition: .onQueue(.main))
        let start = CFAbsoluteTimeGetCurrent()
        let own = ProcessInfo.processInfo.processIdentifier
        func step() {
            let el = (CFAbsoluteTimeGetCurrent() - start) * 1000
            switch FocusWaitPolicy.decide(
                frontmostPid: NSWorkspace.shared.frontmostApplication?.processIdentifier,
                expectedPid: pid, ownPid: own, elapsedMs: el, maxMs: maxMs)
            {
            case .satisfied: completion(true, el)
            case .timedOut: completion(false, el)
            case .keepWaiting: DispatchQueue.main.asyncAfter(deadline: .now() + 0.005) { step() }
            }
        }
        step()
    }

    public static func describeFrontmost() -> String {
        let a = NSWorkspace.shared.frontmostApplication
        return "\(a?.bundleIdentifier ?? "none") pid=\(a?.processIdentifier ?? 0)"
    }
}
