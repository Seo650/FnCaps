import Foundation

public struct SymbolicHotkey: Equatable {
    public var enabled: Bool
    public var ascii: Int
    public var keyCode: Int
    /// Raw bits identical to CGEventFlags (Shift 131072, Control 262144, Option 524288,
    /// Command 1048576, SecondaryFn 8388608), so callers can use `CGEventFlags(rawValue:)`.
    public var modifierMask: UInt64

    public init(enabled: Bool, ascii: Int, keyCode: Int, modifierMask: UInt64) {
        self.enabled = enabled
        self.ascii = ascii
        self.keyCode = keyCode
        self.modifierMask = modifierMask
    }
}

public enum HotkeyStatus: Equatable {
    case usable(SymbolicHotkey), missing, disabled, unassigned(keyCode: Int)

    public func note(id: Int) -> String {
        switch self {
        case .usable: return "hotkey\(id)_usable"
        case .missing: return "hotkey\(id)_missing"
        case .disabled: return "hotkey\(id)_disabled"
        case .unassigned(let kc): return "hotkey\(id)_unassigned(keyCode=\(kc))"
        }
    }
}

/// Read-only access to AppleSymbolicHotKeys. Never writes preferences.
public enum SymbolicHotkeyReader {
    public static func parse(_ entry: [String: Any]) -> SymbolicHotkey? {
        guard let enabledNum = entry["enabled"] as? NSNumber,
            let value = entry["value"] as? [String: Any],
            let params = value["parameters"] as? [Any], params.count >= 3,
            let a = params[0] as? NSNumber, let k = params[1] as? NSNumber,
            let m = params[2] as? NSNumber
        else { return nil }
        return SymbolicHotkey(
            enabled: enabledNum.boolValue, ascii: a.intValue, keyCode: k.intValue,
            modifierMask: m.uint64Value)
    }

    public static func read(id: Int) -> SymbolicHotkey? {
        guard
            let all = CFPreferencesCopyAppValue(
                "AppleSymbolicHotKeys" as CFString, "com.apple.symbolichotkeys" as CFString)
                as? [String: Any],
            let entry = all[String(id)] as? [String: Any]
        else { return nil }
        return parse(entry)
    }

    /// Usable only when enabled and keyCode is a real virtual key (0...127); 65535 means "unassigned".
    public static func status(of hk: SymbolicHotkey?) -> HotkeyStatus {
        guard let hk else { return .missing }
        guard hk.enabled else { return .disabled }
        guard (0...127).contains(hk.keyCode) else { return .unassigned(keyCode: hk.keyCode) }
        return .usable(hk)
    }

    public static func status(id: Int) -> HotkeyStatus { status(of: read(id: id)) }
}
