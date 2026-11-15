import Foundation

/// Conservative "may be composing" tracker for Phase 2/3. False positives only cost an extra native hop.
/// It never drives a Return (rejected in 01-GAP-RESEARCH). Pure value type, Foundation only.
public struct CompositionHeuristic: Equatable {
    public enum Event: Equatable {
        case keyDown(keyCode: UInt16, command: Bool, control: Bool, sourceIsInputMethod: Bool)
        case sourceChanged
        case mouseDown
    }

    public private(set) var mayBeComposing = false
    public init() {}

    /// Keys that clear a composition (Return, keypad Enter, Escape).
    static let clearing: Set<UInt16> = [36, 76, 53]

    /// ANSI letters/digits/punctuation (0...50 without Return, Tab, Space) plus keypad digits.
    static func isPrintable(_ code: UInt16) -> Bool {
        if code <= 50 { return code != 36 && code != 48 && code != 49 }
        return [65, 67, 69, 75, 78, 81, 82, 83, 84, 85, 86, 87, 88, 89, 91, 92].contains(code)
    }

    public mutating func handle(_ event: Event) {
        switch event {
        case .sourceChanged:
            mayBeComposing = false
        case .mouseDown:
            break
        case let .keyDown(code, command, control, isIM):
            if Self.clearing.contains(code) { mayBeComposing = false; return }
            if command || control { return }
            if isIM && Self.isPrintable(code) { mayBeComposing = true }
        }
    }
}
