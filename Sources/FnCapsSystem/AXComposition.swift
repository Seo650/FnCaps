import AppKit
import ApplicationServices
import Foundation
import FnCapsCore

public enum AXComposition {
    /// Length of the focused element's AXTextInputMarkedRange (50 ms timeout). Nil when unreadable, or when
    /// `requirePid` is set and the focused element belongs to another process.
    public static func focusedMarkedLength(requirePid: pid_t?) -> Int? {
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.05)
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
            let focusedRef, CFGetTypeID(focusedRef) == AXUIElementGetTypeID()
        else { return nil }
        let focused = focusedRef as! AXUIElement
        AXUIElementSetMessagingTimeout(focused, 0.05)
        if let requirePid {
            var pid: pid_t = 0
            guard AXUIElementGetPid(focused, &pid) == .success, pid == requirePid else { return nil }
        }
        var rangeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(focused, "AXTextInputMarkedRange" as CFString, &rangeRef) == .success,
            let rangeRef, CFGetTypeID(rangeRef) == AXValueGetTypeID()
        else { return nil }
        var range = CFRange(location: 0, length: 0)
        guard AXValueGetValue(rangeRef as! AXValue, .cfRange, &range) else { return nil }
        return range.length
    }
}

/// S8 comparison arm. Permanently excluded from the product (FINDINGS E7: Return became a newline for
/// Korean/Vietnamese); bench comparison only, and it can only be built with a target pid.
/// If AX reports a composition in the guard app's focused element, post one Return
/// (flags cleared, at most once), wait until the marked length is 0, then run S5a. Useless in Terminal/Electron.
public final class AXReturnStrategy: SwitchStrategy {
    public let name = "S8-AXReturn"
    public let guardPid: pid_t
    public init(guardPid: pid_t) { self.guardPid = guardPid }

    public func switchTo(
        _ target: SourceInfo, from origin: SourceInfo?, catalog: InputSourceCatalog,
        completion: @escaping (SwitchOutcome) -> Void
    ) {
        dispatchPrecondition(condition: .onQueue(.main))
        let start = CFAbsoluteTimeGetCurrent()
        let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
        guard guardPid > 0, GuardPolicy.shouldPost(.pid(guardPid), frontmostPid: front) else {
            completion(SwitchOutcome(tisLanded: false, tisLatencyMs: 0, notes: "guard_blocked"))
            return
        }
        let len = AXComposition.focusedMarkedLength(requirePid: guardPid)
        let axNote = len.map(String.init) ?? "nil"

        func secondLeg(returns: Int, cleared: Bool) {
            TempWindowStrategy(holdMs: 1).switchTo(target, from: origin, catalog: catalog) { inner in
                completion(SwitchOutcome(
                    tisLanded: inner.tisLanded, tisLatencyMs: (CFAbsoluteTimeGetCurrent() - start) * 1000,
                    notes: "returns=\(returns) ax=\(axNote) cleared=\(cleared) then: \(inner.notes)"))
            }
        }

        guard let len, len > 0 else {
            secondLeg(returns: 0, cleared: false)
            return
        }
        SyntheticKeys.tap(keyCode: 36, flags: [])
        let pollStart = CFAbsoluteTimeGetCurrent()
        let timer = Timer(timeInterval: 0.005, repeats: true) { t in
            let now = AXComposition.focusedMarkedLength(requirePid: self.guardPid)
            let elapsed = (CFAbsoluteTimeGetCurrent() - pollStart) * 1000
            if now == 0 {
                t.invalidate()
                secondLeg(returns: 1, cleared: true)
            } else if elapsed >= 50 {
                t.invalidate()
                secondLeg(returns: 1, cleared: false)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
    }
}
