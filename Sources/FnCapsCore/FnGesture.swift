import Foundation

/// Pure state machine that decides what the event tap does with fn (Globe) events.
///
/// Only the keycode 63 flagsChanged transition is used to detect fn press/release (the tap
/// interprets it and feeds `.fnFlags`). Keycode 179 is always consumed while the tap is
/// installed (Phase 1 E2d). Time is injected (callback passes `ProcessInfo.processInfo.systemUptime`);
/// only `downAt` and `used` are stored, no key history.
public struct FnGesture: Equatable {
    public enum Input: Equatable {
        case fnFlags(down: Bool, now: TimeInterval)
        case otherKeyDown(keyCode: UInt16)
        case otherKeyUp
        case otherFlagsChanged
        case systemDefined
        case mouseDown
        case globeKey179
        case reset
    }

    public enum Output: Equatable, Sendable {
        case pass
        case consume
        case consumeAndSwitch
    }

    /// When true, a press held for `longPressThreshold` or longer is cancelled (consumed, no switch).
    public var cancelOnLongPress = false
    public static let longPressThreshold: TimeInterval = 0.5

    public var isFnDown: Bool { downAt != nil }
    private var downAt: TimeInterval?
    private var used = false

    public init() {}

    public mutating func handle(_ input: Input) -> Output {
        switch input {
        case .fnFlags(let down, let now):
            if down {
                if downAt == nil {
                    downAt = now
                    used = false
                }
                return .pass
            }
            guard let start = downAt else { return .pass }
            let duration = now - start
            downAt = nil
            if used { return .pass }
            if cancelOnLongPress && duration >= Self.longPressThreshold { return .consume }
            return .consumeAndSwitch
        case .otherKeyDown, .otherFlagsChanged, .systemDefined, .mouseDown:
            if downAt != nil { used = true }
            return .pass
        case .otherKeyUp:
            return .pass
        case .globeKey179:
            return .consume
        case .reset:
            downAt = nil
            used = false
            return .pass
        }
    }
}
