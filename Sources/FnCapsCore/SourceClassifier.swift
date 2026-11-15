import Foundation

public enum SourceRole: String, Codable, Sendable {
    case base
    case foreign
    case unclassified
}

/// One language mode: all enabled foreign sources of the same language, in catalog order.
public struct LanguageMode: Equatable, Codable, Sendable {
    public let key: String
    public let sources: [SourceID]

    public init(key: String, sources: [SourceID]) {
        self.key = key
        self.sources = sources
    }
}

public struct ClassifiedSources: Equatable, Codable, Sendable {
    public let base: [SourceID]
    public let foreign: [SourceID]
    public let unclassified: [SourceID]
    public let modes: [LanguageMode]

    public init(
        base: [SourceID], foreign: [SourceID], unclassified: [SourceID],
        modes: [LanguageMode]
    ) {
        self.base = base
        self.foreign = foreign
        self.unclassified = unclassified
        self.modes = modes
    }

    public func role(of id: SourceID) -> SourceRole? {
        if base.contains(id) { return .base }
        if foreign.contains(id) { return .foreign }
        if unclassified.contains(id) { return .unclassified }
        return nil
    }

    public func contains(_ id: SourceID) -> Bool { role(of: id) != nil }

    public func modeKey(of id: SourceID) -> String? {
        modes.first(where: { $0.sources.contains(id) })?.key
    }

    public func mode(forKey key: String) -> LanguageMode? {
        modes.first(where: { $0.key == key })
    }
}

public enum SourceClassifier {
    /// Splits a language tag into components at "-" or "_".
    private static func components(of info: SourceInfo) -> [Substring] {
        guard let first = info.languages.first else { return [] }
        return first.split(whereSeparator: { $0 == "-" || $0 == "_" })
    }

    /// Language part of the FIRST language only, lowercased (e.g. "zh").
    public static func primaryLanguage(of info: SourceInfo) -> String? {
        guard let lang = components(of: info).first else { return nil }
        return lang.lowercased()
    }

    /// Language plus a 4-letter script subtag when present ("zh-Hans"); otherwise the language.
    public static func modeKey(of info: SourceInfo) -> String? {
        guard let lang = primaryLanguage(of: info) else { return nil }
        let parts = components(of: info)
        if parts.count > 1, parts[1].count == 4, parts[1].allSatisfy({ $0.isLetter }) {
            let script = parts[1].prefix(1).uppercased() + parts[1].dropFirst().lowercased()
            return "\(lang)-\(script)"
        }
        return lang
    }

    public static func role(of info: SourceInfo) -> SourceRole {
        guard let lang = primaryLanguage(of: info) else { return .unclassified }
        return lang == "en" ? .base : .foreign
    }

    /// 길게 누르기와 기본 구성의 영어계 판정에 쓰는 역할 분류. 키별 목록 결정은 KeyLayout이 한다.
    public static func classify(_ sources: [SourceInfo]) -> ClassifiedSources {
        var base: [SourceID] = []
        var foreign: [SourceID] = []
        var unclassified: [SourceID] = []
        var keys: [String] = []
        var grouped: [String: [SourceID]] = [:]
        for s in sources {
            switch role(of: s) {
            case .base: base.append(s.id)
            case .unclassified: unclassified.append(s.id)
            case .foreign:
                foreign.append(s.id)
                let key = modeKey(of: s) ?? ""
                if grouped[key] == nil { keys.append(key) }
                grouped[key, default: []].append(s.id)
            }
        }
        let modes = keys.map { LanguageMode(key: $0, sources: grouped[$0] ?? []) }
        return ClassifiedSources(
            base: base, foreign: foreign, unclassified: unclassified, modes: modes)
    }
}
