import Foundation

/// 자물쇠 프롬프트를 이미 띄웠는지 UserDefaults에 남긴다(앱 재시작을 넘어 유지).
public struct PromptMemory {
    public static let key = "permissionPromptShown"
    public static let launchedKey = "hasLaunchedBefore"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults) { self.defaults = defaults }

    /// 키에 Bool이 있으면 그 값. 없으면 hasLaunchedBefore를 따른다.
    /// 이주 이유: 02-12~02-14 빌드는 첫 클릭에 프롬프트를 띄웠으므로 이미 실행해 본 설치는 TCC 항목이 있을 가능성이 높다(추정, 02-14 A4).
    public var shown: Bool {
        if let v = defaults.object(forKey: Self.key) as? Bool { return v }
        return defaults.object(forKey: Self.launchedKey) as? Bool ?? false
    }

    public func markShown() { defaults.set(true, forKey: Self.key) }
}
