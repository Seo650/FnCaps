import Foundation

public extension TriggerKey {
    /// 이 키가 돌리는 목록. 지정 목록(assigned)은 TriggerKey가 아니다(D-46).
    var list: SourceList { self == .caps ? .caps : .fn }
}

/// D-04, D-05, D-09, D-25, D-46: 키별 목록을 켜진 입력 소스로 푼 것. 한 칸은 입력 소스 하나다.
/// 저장된 목록은 그대로 두고(꺼진 소스를 다시 켜면 제자리), 엔진은 이 풀이만 본다.
/// T-04-04: 켜진 소스에 없는 ID는 버리고, 같은 목록 안 중복은 한 번만 남긴다.
/// 복제(2026-11-11): 한 소스가 여러 목록에 함께 있을 수 있다. 목록마다 따로 판정한다.
/// 04.3: 키별 진입 언어(D-01). `rule:` 편의 init은 두 키에 같은 값을 넣는다.
public struct KeyLayout: Equatable, Sendable {
    public static let empty = KeyLayout(caps: [], fn: [], sources: [], rule: .nextAfterLast)

    public let entry: EntryChoices
    /// engineLists만 담는다(사용 안 함은 엔진 목록이 아니다).
    private let lists: [SourceList: [SourceID]]

    public init(caps: [SourceID], fn: [SourceID], assigned: [SourceID] = [],
                sources: [SourceInfo], entry: EntryChoices) {
        var infoByID: [SourceID: SourceInfo] = [:]
        for s in sources { infoByID[s.id] = s }
        let given: [SourceList: [SourceID]] = [.caps: caps, .fn: fn, .assigned: assigned]
        var built: [SourceList: [SourceID]] = [:]
        for list in SourceList.engineLists {
            var seen = Set<SourceID>()
            var out: [SourceID] = []
            for id in given[list] ?? [] where infoByID[id] != nil && seen.insert(id).inserted {
                out.append(id)
            }
            built[list] = out
        }
        // T-04.3-02: 그 키 목록에 없는 .source(id)는 실행할 때만 .next로 낮춘다(저장값은 그대로).
        var pruned = entry
        for key in [TriggerKey.caps, .fn] {
            if case .source(let id) = entry[key], !(built[key.list] ?? []).contains(id) {
                pruned[key] = .next
            }
        }
        self.entry = pruned
        self.lists = built
    }

    /// 옛 시그니처. 두 키에 같은 `OutsideRule`을 넣는다(04.3 전 동작).
    public init(caps: [SourceID], fn: [SourceID], assigned: [SourceID] = [],
                sources: [SourceInfo], rule: OutsideRule) {
        self.init(caps: caps, fn: fn, assigned: assigned, sources: sources,
                  entry: .both(EntryLanguage(rule)))
    }

    public func entry(for key: TriggerKey) -> EntryLanguage { entry[key] }

    public func sources(in list: SourceList) -> [SourceID] { lists[list] ?? [] }

    public func sources(for key: TriggerKey) -> [SourceID] { sources(in: key.list) }

    /// 이 소스가 든 엔진 목록 모두(caps, fn, assigned 순서).
    public func lists(of id: SourceID) -> [SourceList] {
        SourceList.engineLists.filter { lists[$0]?.contains(id) ?? false }
    }

    /// 이 소스가 든 첫 목록(caps > fn > assigned). 복제된 소스는 앞 목록 하나만 나온다.
    public func list(of id: SourceID) -> SourceList? {
        SourceList.engineLists.first { lists[$0]?.contains(id) ?? false }
    }

    public func key(of id: SourceID) -> TriggerKey? {
        guard let list = list(of: id) else { return nil }
        switch list {
        case .caps: return .caps
        case .fn: return .fn
        case .assigned, .excluded: return nil
        }
    }

    public func isListed(_ id: SourceID) -> Bool { list(of: id) != nil }

    public var capsListActive: Bool { !sources(in: .caps).isEmpty }
    public var fnListActive: Bool { !sources(in: .fn).isEmpty }
    /// 지정 목록에 켜진 소스가 있는지. 탭 설치는 조합 유무가 정한다(04-23).
    public var assignedActive: Bool { !sources(in: .assigned).isEmpty }
    public var hasActiveList: Bool { capsListActive || fnListActive }
}
