import Foundation

/// One AppleInputSourceHistory entry, already cast to plain strings.
public struct HistoryEntry: Equatable, Sendable {
    public let inputMode: String?
    public let bundleID: String?
    public let layoutName: String?

    public init(inputMode: String?, bundleID: String?, layoutName: String?) {
        self.inputMode = inputMode
        self.bundleID = bundleID
        self.layoutName = layoutName
    }
}

/// Pure matching of history entries to enabled sources (L-05): ID first, name only when unique.
public enum InputSourceHistoryMatcher {
    public static let layoutPrefix = "com.apple.keylayout."

    public static func match(_ entries: [HistoryEntry], among sources: [SourceInfo]) -> [SourceID] {
        var out: [SourceID] = []
        for entry in entries {
            guard let found = find(entry, in: sources), !out.contains(found.id) else { continue }
            out.append(found.id)
        }
        return out
    }

    private static func find(_ entry: HistoryEntry, in sources: [SourceInfo]) -> SourceInfo? {
        if let mode = entry.inputMode, let s = sources.first(where: { $0.inputModeID == mode }) {
            return s
        }
        if entry.inputMode == nil, let bundle = entry.bundleID,
            let s = sources.first(where: { $0.inputModeID == nil && $0.bundleID == bundle })
        {
            return s
        }
        guard let layout = entry.layoutName else { return nil }
        if let s = sources.first(where: { $0.id == layoutPrefix + layout }) { return s }
        let stripped = String(layout.filter { $0.isLetter || $0.isNumber })
        if !stripped.isEmpty, let s = sources.first(where: { $0.id == layoutPrefix + stripped }) {
            return s
        }
        let named = sources.filter { $0.type == "TISTypeKeyboardLayout" && $0.localizedName == layout }
        return named.count == 1 ? named[0] : nil
    }
}
