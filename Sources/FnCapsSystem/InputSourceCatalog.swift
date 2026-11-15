import Carbon
import Foundation
import FnCapsCore

/// Reads enabled keyboard input sources from TIS. Main thread only.
/// All property reads use `as?` casts; missing values become nil/empty.
public final class InputSourceCatalog {
    public init() {}

    public func loadEnabled() -> [SourceInfo] {
        dispatchPrecondition(condition: .onQueue(.main))
        let filter: [CFString: Any] = [
            kTISPropertyInputSourceIsEnabled: true,
            kTISPropertyInputSourceIsSelectCapable: true,
            kTISPropertyInputSourceCategory: kTISCategoryKeyboardInputSource as Any,
        ]
        guard
            let unmanaged = TISCreateInputSourceList(filter as CFDictionary, false),
            let list = unmanaged.takeRetainedValue() as? [TISInputSource]
        else { return [] }
        return list.compactMap(info(from:))
    }

    public func currentID() -> SourceID? {
        dispatchPrecondition(condition: .onQueue(.main))
        guard let src = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else { return nil }
        return string(src, kTISPropertyInputSourceID)
    }

    /// 앱 안 TIS가 새로 추가된 소스를 아직 못 볼 수 있어(02-20 1부) 설치된 소스까지 한 번 더 찾는다.
    /// 켜짐 여부는 여기서 판단하지 않는다. 앱에서는 새 프로세스 목록이 기준이다.
    public func tisSource(for id: SourceID) -> TISInputSource? {
        dispatchPrecondition(condition: .onQueue(.main))
        let filter: [CFString: Any] = [kTISPropertyInputSourceID: id]
        for includeAllInstalled in [false, true] {
            if let unmanaged = TISCreateInputSourceList(filter as CFDictionary, includeAllInstalled),
                let list = unmanaged.takeRetainedValue() as? [TISInputSource],
                let first = list.first
            {
                return first
            }
        }
        return nil
    }

    /// Most-recently-used first, matched against `sources`, no duplicates.
    public func historySourceIDs(among sources: [SourceInfo]) -> [SourceID] {
        dispatchPrecondition(condition: .onQueue(.main))
        CFPreferencesAppSynchronize("com.apple.HIToolbox" as CFString)
        let raw = CFPreferencesCopyAppValue(
            "AppleInputSourceHistory" as CFString, "com.apple.HIToolbox" as CFString)
        guard let entries = raw as? [[String: Any]] else { return [] }
        let history = entries.map {
            HistoryEntry(
                inputMode: $0["Input Mode"] as? String, bundleID: $0["Bundle ID"] as? String,
                layoutName: $0["KeyboardLayout Name"] as? String)
        }
        return InputSourceHistoryMatcher.match(history, among: sources)
    }

    /// Raw identifiers from AppleEnabledInputSources (log-only cross-check).
    public func enabledPrefIDs() -> [String] {
        dispatchPrecondition(condition: .onQueue(.main))
        let raw = CFPreferencesCopyAppValue(
            "AppleEnabledInputSources" as CFString, "com.apple.HIToolbox" as CFString)
        guard let entries = raw as? [[String: Any]] else { return [] }
        return entries.compactMap {
            ($0["Input Mode"] as? String) ?? ($0["Bundle ID"] as? String)
                ?? ($0["KeyboardLayout Name"] as? String)
        }
    }

    // MARK: - Property helpers

    private func info(from src: TISInputSource) -> SourceInfo? {
        guard let id = string(src, kTISPropertyInputSourceID) else { return nil }
        var languages: [String] = []
        if let ptr = TISGetInputSourceProperty(src, kTISPropertyInputSourceLanguages),
            let arr = Unmanaged<AnyObject>.fromOpaque(ptr).takeUnretainedValue() as? [String]
        {
            languages = arr
        }
        return SourceInfo(
            id: id,
            localizedName: string(src, kTISPropertyLocalizedName) ?? id,
            languages: languages,
            type: string(src, kTISPropertyInputSourceType) ?? "",
            bundleID: string(src, kTISPropertyBundleID),
            inputModeID: string(src, kTISPropertyInputModeID),
            isSelectCapable: bool(src, kTISPropertyInputSourceIsSelectCapable),
            isEnabled: bool(src, kTISPropertyInputSourceIsEnabled))
    }

    private func string(_ src: TISInputSource, _ key: CFString) -> String? {
        guard let ptr = TISGetInputSourceProperty(src, key) else { return nil }
        return Unmanaged<AnyObject>.fromOpaque(ptr).takeUnretainedValue() as? String
    }

    private func bool(_ src: TISInputSource, _ key: CFString) -> Bool {
        guard let ptr = TISGetInputSourceProperty(src, key) else { return false }
        return (Unmanaged<AnyObject>.fromOpaque(ptr).takeUnretainedValue() as? Bool) ?? false
    }
}
