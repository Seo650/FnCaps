import Foundation

/// D-01, D-08, 04.3: 키가 「목록 밖」에서 눌렸을 때 어디로 갈지의 값. 키마다 하나씩 둔다.
/// - `.next`: 그 목록에서 마지막으로 쓴 소스의 다음 (기본, 옛 `.nextAfterLast`)
/// - `.last`: 그 목록에서 마지막으로 쓴 소스 (옛 `.last`)
/// - `.source(id)`: 그 키 목록의 한 입력 소스로 바로 (진입 언어)
///
/// `OutsideRule`을 넓히지 않고 새 타입을 둔다. 연관값이 있는 enum은 `String` raw·`CaseIterable`이
/// 될 수 없기 때문이다. `OutsideRule`은 옛 `outsideRule` 키 읽기와 시험 편의로 남긴다.
/// 목록에 없는 `.source(id)`는 `KeyLayout`이 실행할 때 `.next`로 낮춘다(T-04-04 선례).
public enum EntryLanguage: Equatable, Hashable, Sendable {
    case next
    case last
    case source(SourceID)

    public init(_ rule: OutsideRule) {
        self = rule == .last ? .last : .next
    }

    /// 저장·로그·진단에 같이 쓰는 한 줄 표기: "next" | "last" | "id:<SourceID>".
    public var storageText: String {
        switch self {
        case .next: return "next"
        case .last: return "last"
        case .source(let id): return "id:" + id
        }
    }

    /// `.source`를 `.next`로 낮춘 값. 권장 배치 계산처럼 특정 언어 선택을 쓰지 않는 곳에서 쓴다.
    /// `.next`·`.last`는 그대로다.
    public var ruleOnly: EntryLanguage {
        if case .source = self { return .next }
        return self
    }
}

/// T-04.3-01, Pitfall 1: 모르는 값·빈 ID·숫자·null도 throw 없이 `.next`로 읽는다.
/// 이 디코더가 throw하면 `KeyLists` 전체가 `.corrupt`가 되어 사용자의 목록이 초기화된다.
extension EntryLanguage: Codable {
    public init(from decoder: Decoder) throws {
        let raw = (try? decoder.singleValueContainer().decode(String.self)) ?? "next"
        switch raw {
        case "last":
            self = .last
        case let s where s.hasPrefix("id:") && s.count > 3:
            self = .source(String(s.dropFirst(3)))
        default:
            self = .next
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(storageText)
    }
}

/// D-01: 두 키의 진입 언어 한 쌍. 화면·저장·엔진이 같은 값을 쓴다.
///
/// 저장 계약(04.3-03 `KeyLists`가 쓴다): `{"caps": "...", "fn": "..."}`.
/// 각 값은 `EntryLanguage`의 관대한 디코더를 지나므로 키가 없거나 값이 깨져도 `.next`이고 throw하지 않는다.
/// 컨테이너 자체가 keyed가 아니면(예: `7`) throw할 수 있으므로 호출자는 `try?`로 감싼다.
public struct EntryChoices: Equatable, Hashable, Codable, Sendable {
    public var caps: EntryLanguage
    public var fn: EntryLanguage

    public init(caps: EntryLanguage = .next, fn: EntryLanguage = .next) {
        self.caps = caps
        self.fn = fn
    }

    public static func both(_ entry: EntryLanguage) -> EntryChoices {
        EntryChoices(caps: entry, fn: entry)
    }

    public subscript(key: TriggerKey) -> EntryLanguage {
        get { key == .caps ? caps : fn }
        set {
            if key == .caps { caps = newValue } else { fn = newValue }
        }
    }

    /// `.source`를 `.next`로 낮춘 쌍. `EntryLanguage.ruleOnly`를 두 키에 적용한다.
    public var ruleOnly: EntryChoices {
        EntryChoices(caps: caps.ruleOnly, fn: fn.ruleOnly)
    }

    /// SwitchService 로그용: "caps:<...>,fn:<...>".
    public var storageText: String { "caps:\(caps.storageText),fn:\(fn.storageText)" }

    private enum CodingKeys: String, CodingKey {
        case caps, fn
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        caps = (try? c.decodeIfPresent(EntryLanguage.self, forKey: .caps)) ?? nil ?? .next
        fn = (try? c.decodeIfPresent(EntryLanguage.self, forKey: .fn)) ?? nil ?? .next
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(caps, forKey: .caps)
        try c.encode(fn, forKey: .fn)
    }
}
