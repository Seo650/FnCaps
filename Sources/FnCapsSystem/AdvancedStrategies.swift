import AppKit
import Carbon
import Foundation
import FnCapsCore

private func isThirdParty(_ s: SourceInfo?) -> Bool {
    guard let s else { return false }
    return !(s.bundleID ?? "com.apple.").hasPrefix("com.apple.")
}

/// S3: select target, select origin (target becomes "previous"), then post the user's live
/// "previous input source" shortcut (hotkey 60). Zero system mutation.
public final class PrimePulseStrategy: SwitchStrategy {
    public let name = "S3-PrimePulse"
    public init() {}

    public func switchTo(
        _ target: SourceInfo, from origin: SourceInfo?, catalog: InputSourceCatalog,
        completion: @escaping (SwitchOutcome) -> Void
    ) {
        dispatchPrecondition(condition: .onQueue(.main))
        let start = CFAbsoluteTimeGetCurrent()
        let hkStatus = SymbolicHotkeyReader.status(id: 60)
        guard case .usable(let hk) = hkStatus else {
            completion(SwitchOutcome(tisLanded: false, tisLatencyMs: 0, notes: hkStatus.note(id: 60)))
            return
        }
        guard let tsrc = catalog.tisSource(for: target.id) else {
            completion(SwitchOutcome(tisLanded: false, tisLatencyMs: 0, notes: "source not found"))
            return
        }
        guard let origin, origin.id != target.id, catalog.tisSource(for: origin.id) != nil else {
            _ = TISSelectInputSource(tsrc)
            LandingWaiter.wait(for: target.id, catalog: catalog, start: start) { landed, ms in
                completion(SwitchOutcome(tisLanded: landed, tisLatencyMs: ms,
                    notes: "no distinct origin; S1 behavior"))
            }
            return
        }
        let gap = (isThirdParty(target) || isThirdParty(origin) ? 50.0 : 10.0) / 1000
        _ = TISSelectInputSource(tsrc)
        DispatchQueue.main.asyncAfter(deadline: .now() + gap) {
            if let o = catalog.tisSource(for: origin.id) { _ = TISSelectInputSource(o) }
            DispatchQueue.main.asyncAfter(deadline: .now() + gap) {
                let flags = CGEventFlags(rawValue: hk.modifierMask)
                SyntheticKeys.tap(keyCode: CGKeyCode(hk.keyCode), flags: flags)
                LandingWaiter.wait(for: target.id, catalog: catalog, start: start) { landed, ms in
                    completion(SwitchOutcome(tisLanded: landed, tisLatencyMs: ms,
                        notes: "hotkey60 keyCode=\(hk.keyCode) mask=\(hk.modifierMask) gap=\(gap * 1000)ms"))
                }
            }
        }
    }
}

/// S9 (GAP-09 spike): post only the user's "previous input source" shortcut (hotkey 60) so the OS
/// switches natively, without S3's target/origin priming. If the previous source was not the target,
/// fall back to a plain TIS select after `hopTimeoutMs`.
public final class HotkeyOnlyStrategy: SwitchStrategy {
    public let name = "S9-HotkeyOnly"
    public let hopTimeoutMs: Double
    public init(hopTimeoutMs: Double = 150) { self.hopTimeoutMs = hopTimeoutMs }

    public func switchTo(
        _ target: SourceInfo, from origin: SourceInfo?, catalog: InputSourceCatalog,
        completion: @escaping (SwitchOutcome) -> Void
    ) {
        dispatchPrecondition(condition: .onQueue(.main))
        let start = CFAbsoluteTimeGetCurrent()
        let hkStatus = SymbolicHotkeyReader.status(id: 60)
        guard case .usable(let hk) = hkStatus else {
            completion(SwitchOutcome(tisLanded: false, tisLatencyMs: 0, notes: hkStatus.note(id: 60)))
            return
        }
        guard let tsrc = catalog.tisSource(for: target.id) else {
            completion(SwitchOutcome(tisLanded: false, tisLatencyMs: 0, notes: "source not found"))
            return
        }
        // Plain key events with flags only were applied ~450 ms late (S3, first S9 run); send the
        // modifier presses explicitly like a physical chord.
        SyntheticKeys.postHotkey(keyCode: CGKeyCode(hk.keyCode), modifierMask: hk.modifierMask, explicitModifiers: true)
        LandingWaiter.wait(for: target.id, catalog: catalog, timeoutMs: hopTimeoutMs, start: start) { landed, ms in
            if landed {
                completion(SwitchOutcome(tisLanded: true, tisLatencyMs: ms, notes: "path=hotkey"))
                return
            }
            // Previous source was something else; the hotkey moved us there. Go to the target directly.
            _ = TISSelectInputSource(tsrc)
            LandingWaiter.wait(for: target.id, catalog: catalog, start: start) { landed2, ms2 in
                completion(SwitchOutcome(tisLanded: landed2, tisLatencyMs: ms2,
                    notes: "path=fallback hopMs=\(Int(ms))"))
            }
        }
    }
}

/// S4a: mirrors the Karabiner rule (select_input_source then caps_lock press) with a synthetic
/// Caps flagsChanged event. Karabiner posts a real HID caps_lock via its virtual device, so the
/// manual Karabiner baseline in E6 stays the reference.
public final class CapsRefreshEventStrategy: SwitchStrategy {
    public let name = "S4a-CapsRefreshEvent"
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
        let caps = CapsLockController()
        let before = caps.isOn()
        _ = TISSelectInputSource(src)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.010) {
            SyntheticKeys.postFlagsChanged(keyCode: 57, flags: .maskAlphaShift)
            SyntheticKeys.postFlagsChanged(keyCode: 57, flags: [])
            LandingWaiter.wait(for: target.id, catalog: catalog, start: start) { landed, ms in
                var notes = "caps event posted"
                if let before, let after = caps.isOn(), after != before {
                    caps.set(before)
                    notes += "; caps state restored"
                }
                completion(SwitchOutcome(tisLanded: landed, tisLatencyMs: ms, notes: notes))
            }
        }
    }
}

/// S4b: lock-state blip (toggle then restore 15 ms later) instead of a key event.
public final class CapsRefreshLockStrategy: SwitchStrategy {
    public let name = "S4b-CapsRefreshLock"
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
        let caps = CapsLockController()
        guard let current = caps.isOn() else {
            _ = TISSelectInputSource(src)
            LandingWaiter.wait(for: target.id, catalog: catalog, start: start) { landed, ms in
                completion(SwitchOutcome(tisLanded: landed, tisLatencyMs: ms, notes: "caps state unreadable"))
            }
            return
        }
        _ = TISSelectInputSource(src)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.010) {
            caps.set(!current)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.015) {
                caps.set(current)
                LandingWaiter.wait(for: target.id, catalog: catalog, start: start) { landed, ms in
                    completion(SwitchOutcome(tisLanded: landed, tisLatencyMs: ms,
                        notes: "caps lock blip, restored to \(current)"))
                }
            }
        }
    }
}

/// S5: macism-style temporary window to force the system to re-evaluate the input context.
public final class TempWindowStrategy: SwitchStrategy {
    public let name: String
    public let holdMs: Double
    public init(holdMs: Double) {
        self.holdMs = holdMs
        self.name = holdMs >= 100 ? "S5b-TempWindow-150ms" : "S5a-TempWindow-1ms"
    }

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
        let previous = NSWorkspace.shared.frontmostApplication
        _ = TISSelectInputSource(src)
        let mouse = NSEvent.mouseLocation
        let panel = NSPanel(
            contentRect: NSRect(x: mouse.x, y: mouse.y, width: 1, height: 1),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + holdMs / 1000) {
            panel.orderOut(nil)
            panel.close()
            previous?.activate(options: [])
            let finish: (String) -> Void = { restoreNote in
                LandingWaiter.wait(for: target.id, catalog: catalog, start: start) { landed, ms in
                    completion(SwitchOutcome(tisLanded: landed, tisLatencyMs: ms,
                        notes: "restored app=\(previous?.bundleIdentifier ?? "none") hold=\(self.holdMs)ms \(restoreNote)"))
                }
            }
            if let prev = previous, prev.processIdentifier != ProcessInfo.processInfo.processIdentifier {
                FocusWaiter.wait(forPid: prev.processIdentifier) { ok, waited in
                    finish(ok ? "restore_ms=\(Int(waited))" : "restore_ms=\(Int(waited)) restore_timeout")
                }
            } else {
                finish("restore_ms=0")
            }
        }
    }
}
