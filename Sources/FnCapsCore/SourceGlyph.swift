import Foundation

/// 입력 소스 타일에 쓰는 1~2자 글자 기호. TIS 아이콘을 쓸 수 없을 때의 대체 기호다(재설계 §3).
/// 순서: (1) ID 조각 표 (2) 첫 언어 코드 표 (3) 언어 코드 앞 두 글자 대문자 (4) 이름 첫 글자 (5) "•".
public enum SourceGlyph {
    /// ID에 이 조각이 들어 있으면 그 기호. 위에서부터 먼저 맞는 것을 쓴다.
    private static let idFragments: [(fragment: String, glyph: String)] = [
        ("Katakana", "ア"),
        ("SCIM.ITABC", "拼"),
        ("Pinyin", "拼"),
        ("Zhuyin", "注"),
        ("Cangjie", "倉"),
        ("Wubi", "五"),
        ("UnicodeHexInput", "U+"),
        ("keylayout.Dvorak", "Dv"),
    ]

    /// 언어 코드 표. 지역·문자 꼬리를 포함한 값(zh-Hans)을 먼저 보고, 그다음 `-` 앞 부분을 본다.
    /// 근거: 04.1-UAT.md UAT-A(macOS 메뉴 막대 아이콘 글자). 국기는 그리지 않는다(D-14).
    /// uk·ru는 macOS처럼 키릴 대문자 두 글자(УК·РУ). fr·es·de는 표에 넣지 않고
    /// 두 글자 대체 규칙(대문자 두 글자, FR·ES·DE)을 쓴다. vi는 UAT-A에서 보지 않아 그대로 둔다.
    private static let languages: [String: String] = [
        "en": "A", "ko": "한", "ja": "あ",
        "zh-hans": "简", "zh-hant": "繁",
        "vi": "Vi", "hi": "हि", "ar": "ع", "he": "א",
        "uk": "УК", "ru": "РУ", "el": "Ω", "th": "ก",
    ]

    public static func text(id: SourceID, languages: [String], name: String) -> String {
        if let hit = idFragments.first(where: { id.contains($0.fragment) }) { return hit.glyph }
        if let first = languages.first, !first.isEmpty {
            let full = first.replacingOccurrences(of: "_", with: "-").lowercased()
            if let glyph = Self.languages[full] { return glyph }
            let base = String(full.split(separator: "-").first ?? "")
            if let glyph = Self.languages[base] { return glyph }
            let letters = base.filter { $0.isLetter }.prefix(2)
            if !letters.isEmpty { return letters.uppercased() }
        }
        if let ch = name.trimmingCharacters(in: .whitespacesAndNewlines).first { return String(ch) }
        return "•"
    }
}
