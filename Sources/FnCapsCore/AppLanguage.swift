import Foundation

/// 앱 언어(D-42). 별도 키 없이 앱 도메인 AppleLanguages 배열 하나에만 저장한다
/// (04-RESEARCH-ADDENDUM §1 L5~L7: 별도 키는 시스템 설정 값과 어긋난다). 적용은 다시 열 때(L1, L3).
///
/// 원시값은 lproj 폴더 이름이다. 저장 값(`[rawValue]`)이 곧 번들 선호 값이라 판별과 해석이 어긋나지 않는다.
public enum AppLanguage: String, CaseIterable, Sendable {
    case system
    case en, ko, ja
    case zhHans = "zh-Hans", zhHant = "zh-Hant"
    case uk, ru, fr, es, de

    /// D-10 팝업 순서. `allCases` 순서를 팝업 순서로 쓰지 않는다.
    public static let menuOrder: [AppLanguage] =
        [.en, .ko, .ja, .zhHans, .zhHant, .uk, .ru, .fr, .es, .de]

    /// 언어 자기 이름. 번역하지 않는다. `system`은 팝업이 번역 문구를 따로 쓴다.
    public var nativeName: String {
        switch self {
        case .system: return ""
        case .en: return "English"
        case .ko: return "한국어"
        case .ja: return "日本語"
        case .zhHans: return "简体中文"
        case .zhHant: return "繁體中文"
        case .uk: return "Українська"
        case .ru: return "Русский"
        case .fr: return "Français"
        case .es: return "Español"
        case .de: return "Deutsch"
        }
    }

    public static let defaultsKey = "AppleLanguages"

    /// 저장할 배열. nil이면 키를 지운다(「시스템 설정 따름」).
    public var appleLanguages: [String]? {
        self == .system ? nil : [rawValue]
    }

    /// 저장 값의 첫 항목을 지원 언어로 판별한다. 모르는 값이면 .system.
    ///
    /// 지역·문자 꼬리(`ja-KR`, `es-419`, `zh-Hant-HK`)를 견디고, Foundation의 번들 해석
    /// (`Bundle.preferredLocalizations`)과 같은 언어를 고른다: `zh`는 문자 꼬리를 먼저 본다
    /// (`hant` 번체, `hans` 간체). 문자 꼬리가 없을 때만 지역 `tw`·`hk`·`mo`면 번체, 아니면 간체다.
    /// 그래서 `zh-Hans-TW`는 간체, `zh-Hant-CN`은 번체다.
    public static func from(stored: [String]?) -> AppLanguage {
        guard let first = stored?.first else { return .system }
        let parts = first.replacingOccurrences(of: "_", with: "-")
            .split(separator: "-").map { $0.lowercased() }
        guard let code = parts.first else { return .system }
        if code == "zh" {
            let tail = parts.dropFirst()
            if tail.contains("hant") { return .zhHant }
            if tail.contains("hans") { return .zhHans }
            let traditionalRegions = ["tw", "hk", "mo"]
            return tail.contains(where: traditionalRegions.contains) ? .zhHant : .zhHans
        }
        guard let lang = allCases.first(where: { $0.rawValue == code }), lang != .system else {
            return .system
        }
        return lang
    }
}
