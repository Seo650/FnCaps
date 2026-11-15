import Foundation

/// 입력 소스가 들어갈 수 있는 네 목록. assigned는 D-46 「지정 단축키」 목록이다.
public enum SourceList: String, Codable, Sendable, CaseIterable {
    case caps, fn
    case assigned
    case excluded

    /// 엔진이 판정에 쓰는 목록. 한 소스는 여러 엔진 목록에 함께 있을 수 있다(복제, 2026-11-11).
    public static let engineLists: [SourceList] = [.caps, .fn, .assigned]
}

/// Caps·fn·지정 목록과 「사용 안 함」의 저장 모델(D-04~D-10, D-22, D-25, D-46).
/// 목록의 한 칸은 입력 소스 하나다. 꺼진 소스도 지우지 않고 보존한다.
/// 복제(2026-11-11, M-5를 바꿈): 한 소스는 Caps·fn·지정 가운데 여러 목록에 함께 있을 수 있다.
/// 같은 목록 안에는 한 번만 있고, 엔진 목록에 하나라도 있으면 「사용 안 함」에는 없다.
public struct KeyLists: Equatable, Codable, Sendable {
    public var caps: [SourceID]
    public var fn: [SourceID]
    /// 지정 단축키를 쓰는 소스 목록(D-46). 단축키가 없는 소스도 자리를 지킨다.
    public var assigned: [SourceID]
    public var excluded: [SourceID]
    /// 꺼진 소스 이름 표시용 캐시.
    public var names: [SourceID: String]
    /// 지정 소스의 단축키. assigned 밖으로 나가면 지운다(D-46 「뺐다가 다시 넣으면 다시 녹화」).
    public var chords: [SourceID: KeyChord]
    /// 04.3: 키별 진입 언어(D-01). 목록과 같은 JSON에 저장한다(원자적 저장, T-04.3-08).
    /// 목록에서 빠진 `.source`는 `.next`로 정리된다(D-08, `pruningEntries`).
    public var entry: EntryChoices

    public init(caps: [SourceID], fn: [SourceID], assigned: [SourceID] = [],
                excluded: [SourceID], names: [SourceID: String] = [:],
                chords: [SourceID: KeyChord] = [:],
                entry: EntryChoices = EntryChoices()) {
        self.caps = caps
        self.fn = fn
        self.assigned = assigned
        self.excluded = excluded
        self.names = names
        self.chords = chords
        self.entry = entry
    }

    /// 한 키(Caps, fn, 지정) 목록에 들어갈 수 있는 켜진 입력 소스 최대 개수(D-30).
    public static let maxPerKey = 6

    public static let defaultsKey = "keyLists.v1"
    public static let corruptKey = "keyLists.v1.corrupt"

    public var known: Set<SourceID> { Set(caps).union(fn).union(assigned).union(excluded) }

    public func ids(_ list: SourceList) -> [SourceID] {
        switch list {
        case .caps: return caps
        case .fn: return fn
        case .assigned: return assigned
        case .excluded: return excluded
        }
    }

    /// 이 소스가 든 엔진 목록(caps, fn, assigned 순서). 비면 「사용 안 함」이거나 모르는 소스다.
    public func lists(of id: SourceID) -> [SourceList] {
        SourceList.engineLists.filter { ids($0).contains(id) }
    }

    /// 이 소스가 든 첫 목록(caps > fn > assigned > excluded). 복제된 소스는 앞 목록 하나만 나온다.
    public func list(of id: SourceID) -> SourceList? {
        if caps.contains(id) { return .caps }
        if fn.contains(id) { return .fn }
        if assigned.contains(id) { return .assigned }
        if excluded.contains(id) { return .excluded }
        return nil
    }

    /// caps·fn·assigned 목록이 꽉 찼는지. live가 있으면 그 안에 든(켜진) 소스만 센다.
    /// excluded는 꽉 차지 않는다.
    public func isFull(_ list: SourceList, live: Set<SourceID>? = nil) -> Bool {
        guard list != .excluded else { return false }
        let current = ids(list)
        let count = live.map { l in current.filter { l.contains($0) }.count } ?? current.count
        return count >= Self.maxPerKey
    }

    private func with(_ list: SourceList, _ ids: [SourceID]) -> KeyLists {
        var copy = self
        switch list {
        case .caps: copy.caps = ids
        case .fn: copy.fn = ids
        case .assigned: copy.assigned = ids
        case .excluded: copy.excluded = ids
        }
        return copy
    }

    // MARK: 저장

    private enum CodingKeys: String, CodingKey {
        case caps, fn, assigned, excluded, names, chords, entry
    }

    /// 옛 전역 `outsideRule` 값을 디코더에 넘기는 키(D-03). `decoded`가 채운다.
    public static let legacyEntryKey = CodingUserInfoKey(rawValue: "fncaps.legacyEntry")!

    /// T-04-61, T-04-62: caps·fn·excluded·names가 없으면 지금처럼 깨짐(throw)이다.
    /// assigned·chords·entry는 decodeIfPresent로 읽는다 — 옛 keyLists.v1 JSON에 그 키가 없어도
    /// 사용자 목록을 잃지 않는다(04-RESEARCH-SHORTCUTS §6-2).
    /// entry가 없으면 넘겨받은 옛 전역 값(legacyEntry)으로 두 키를 채운다(D-03).
    /// T-04.3-05: entry가 깨져도 `try?`로 감싸 목록 전체가 `.corrupt`가 되지 않게 한다.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        caps = try c.decode([SourceID].self, forKey: .caps)
        fn = try c.decode([SourceID].self, forKey: .fn)
        assigned = try c.decodeIfPresent([SourceID].self, forKey: .assigned) ?? []
        excluded = try c.decode([SourceID].self, forKey: .excluded)
        names = try c.decode([SourceID: String].self, forKey: .names)
        chords = try c.decodeIfPresent([SourceID: KeyChord].self, forKey: .chords) ?? [:]
        let legacy = (decoder.userInfo[KeyLists.legacyEntryKey] as? EntryLanguage) ?? .next
        entry = ((try? c.decodeIfPresent(EntryChoices.self, forKey: .entry)) ?? nil) ?? .both(legacy)
    }

    public func encoded() -> Data? { try? JSONEncoder().encode(self) }

    public enum DecodeResult: Equatable {
        case missing
        case valid(KeyLists)
        case corrupt
    }

    /// legacyEntry는 entry 키가 없는 옛 JSON에만 쓰인다(D-03). 기본값 `.next`는 옛 동작 그대로다.
    public static func decoded(
        _ data: Data?, legacyEntry: EntryLanguage = .next
    ) -> DecodeResult {
        guard let data else { return .missing }
        let decoder = JSONDecoder()
        decoder.userInfo[legacyEntryKey] = legacyEntry
        guard let value = try? decoder.decode(KeyLists.self, from: data) else { return .corrupt }
        return .valid(value.normalized())
    }

    /// 같은 목록 안 중복과 빈 ID를 지우고, 엔진 목록에 있는 소스는 excluded에서 뺀다(복제 허용).
    /// 조합은 남은 assigned 소스 것만, 같은 조합이 겹치면 assigned 순서상 앞 소스 것만 남긴다.
    /// 진입 언어는 그대로 넘기고 마지막에 정리한다(T-04.3-06: 목록에 없는 ghost 소스 → `.next`).
    public func normalized() -> KeyLists {
        var seen = Set<SourceID>()
        func clean(_ list: [SourceID], skip: Set<SourceID> = []) -> [SourceID] {
            var mine = Set<SourceID>()
            var out: [SourceID] = []
            for id in list where !id.isEmpty && !skip.contains(id) && mine.insert(id).inserted {
                seen.insert(id)
                out.append(id)
            }
            return out
        }
        let c = clean(caps)
        let f = clean(fn)
        let a = clean(assigned)
        let e = clean(excluded, skip: seen)
        var keptChords: [SourceID: KeyChord] = [:]
        var usedChords = Set<KeyChord>()
        for id in a {
            guard let chord = chords[id], usedChords.insert(chord).inserted else { continue }
            keptChords[id] = chord
        }
        return KeyLists(caps: c, fn: f, assigned: a, excluded: e,
                        names: names.filter { seen.contains($0.key) }, chords: keptChords,
                        entry: entry)
            .pruningEntries()
    }

    /// D-08: `entry[key] == .source(id)`이고 `id`가 그 키 목록(`ids(key.list)`)에 없으면 `.next`.
    /// live가 있으면 켜진 소스 목록도 함께 본다(꺼진 소스의 진입 언어는 보존하지 않는다).
    /// 멤버십 기준이라 같은 목록 안 순서 변경(D-12)과 복제 소스 하나만 빼기는 값을 그대로 지킨다.
    public func pruningEntries(live: Set<SourceID>? = nil) -> KeyLists {
        var copy = self
        for key in [TriggerKey.caps, .fn] {
            guard case .source(let id) = copy.entry[key] else { continue }
            if !ids(key.list).contains(id) || (live.map { !$0.contains(id) } ?? false) {
                copy.entry[key] = .next
            }
        }
        return copy
    }

    /// 진입 언어를 정한다. `.source`는 그 키 목록에 있는 소스만 받는다(목록 밖은 엔진이 `.next`로
    /// 낮추므로 저장도 하지 않는다). `.next`·`.last`는 언제나 받는다.
    public func settingEntry(_ value: EntryLanguage, for key: TriggerKey) -> KeyLists {
        if case .source(let id) = value, !ids(key.list).contains(id) { return self }
        var copy = self
        copy.entry[key] = value
        return copy
    }

    // MARK: 만들기

    /// 새 설치의 첫 배치. macOS 기본과 비슷하게 Caps에 영어, fn에 외국어를 모두 두고, fn 끝에
    /// 영어(Caps의 첫 소스)를 하나 더 둔다. 🌐가 영어까지 도는 macOS와 같은 모양이라 처음 설정의
    /// 권장 배치(fn에 영어를 두지 않는다)와 겹치지 않는다(04.5 UAT, 2026-11-15 사용자 결정).
    /// 외국어가 없거나 fn이 이미 상한이면 복제하지 않는다.
    public static func initial(for sources: [SourceInfo]) -> KeyLists {
        let base = migrated(sources: sources, legacyCapsSourceID: nil, legacyFnModeKeys: nil)
        guard let english = base.caps.first, !base.fn.isEmpty, base.fn.count < maxPerKey else { return base }
        return base.with(.fn, base.fn + [english])
    }

    /// 옛 설정(capsSourceID, fnCycleOrder, outsideRule)을 새 목록으로 옮긴다. 옛 키는 지우지 않는다.
    /// D-03: entry가 없는 새 설치는 legacyEntry를 두 키에 채운다(없으면 `.next`).
    public static func migrated(
        sources: [SourceInfo], legacyCapsSourceID: SourceID?, legacyFnModeKeys: [String]?,
        legacyEntry: EntryLanguage = .next
    ) -> KeyLists {
        let chosen = legacyCapsSourceID.flatMap { id in sources.first { $0.id == id } }
        let caps: [SourceID]
        let candidates: [SourceInfo]
        if let chosen {
            caps = [chosen.id]
            candidates = sources.filter { $0.id != chosen.id && SourceClassifier.role(of: $0) != .unclassified }
        } else {
            caps = sources.filter { SourceClassifier.role(of: $0) == .base }.map(\.id)
            candidates = sources.filter { SourceClassifier.role(of: $0) == .foreign }
        }
        var groups: [String: [SourceID]] = [:]
        var firstSeen: [String] = []
        for source in candidates {
            guard let key = SourceClassifier.modeKey(of: source) else { continue }
            if groups[key] == nil { firstSeen.append(key) }
            groups[key, default: []].append(source.id)
        }
        var orderedKeys: [String] = []
        for key in (legacyFnModeKeys ?? []) where groups[key] != nil && !orderedKeys.contains(key) {
            orderedKeys.append(key)
        }
        for key in firstSeen where !orderedKeys.contains(key) { orderedKeys.append(key) }
        let fn = orderedKeys.flatMap { groups[$0] ?? [] }
        let excluded = sources.filter { SourceClassifier.role(of: $0) == .unclassified }.map(\.id)
        var names: [SourceID: String] = [:]
        for s in sources { names[s.id] = s.localizedName }
        // D-30 상한(1/2): 이전 시점 sources는 켜진 소스뿐이라 전체 개수 = 켜진 개수다.
        var result = KeyLists(caps: caps, fn: fn, excluded: excluded, names: names,
                              entry: .both(legacyEntry)).normalized()
        for list in [SourceList.caps, .fn] {
            let current = result.ids(list)
            guard current.count > maxPerKey else { continue }
            result.excluded.append(contentsOf: current[maxPerKey...])
            result = result.with(list, Array(current.prefix(maxPerKey)))
        }
        return result.pruningEntries()
    }

    /// 새로 켠 소스만 붙인다. 아무것도 지우지 않는다. 바뀐 것이 없으면 self와 같은 값.
    /// 대상 목록이 켜진 소스 기준으로 꽉 찼으면 excluded 끝에 넣는다(D-30, M1).
    /// 다시 켜진 소스는 제자리에 둔다(M2). 그래서 켜진 소스가 maxPerKey를 넘으면
    /// 목록 맨 뒤의 켜진 소스부터 excluded 끝으로 옮긴다(R4). 이렇게 밀려난 소스도 added에 넣는다.
    public func reconciled(with sources: [SourceInfo]) -> (lists: KeyLists, added: [SourceID]) {
        var result = self
        var added: [SourceID] = []
        var knownNow = known
        let live = Set(sources.map(\.id))
        for s in sources where !knownNow.contains(s.id) {
            knownNow.insert(s.id)
            switch SourceClassifier.role(of: s) {
            case .base:
                if result.isFull(.caps, live: live) { result.excluded.append(s.id) } else { result.caps.append(s.id) }
                added.append(s.id)
            case .foreign:
                if result.isFull(.fn, live: live) { result.excluded.append(s.id) } else { result.fn.append(s.id) }
                added.append(s.id)
            case .unclassified:
                result.excluded.append(s.id)
            }
        }
        // D-30 상한(2/2): 켜진 소스 기준 넘침. 꺼진 소스는 지우지도 옮기지도 않는다.
        for list in [SourceList.caps, .fn, .assigned] {
            var current = result.ids(list)
            var liveCount = current.filter { live.contains($0) }.count
            var pushed: [SourceID] = []
            var index = current.count - 1
            while liveCount > Self.maxPerKey, index >= 0 {
                if live.contains(current[index]) {
                    pushed.insert(current.remove(at: index), at: 0)
                    liveCount -= 1
                }
                index -= 1
            }
            guard !pushed.isEmpty else { continue }
            result = result.with(list, current)
            // 다른 엔진 목록에 복제가 남은 소스는 「사용 안 함」에 넣지 않는다.
            result.excluded.append(contentsOf: pushed.filter { result.lists(of: $0).isEmpty })
            // 지정 상자에서 밀려난 소스는 단축키도 잃는다(D-46).
            if list == .assigned {
                for id in pushed { result.chords[id] = nil }
            }
            added.append(contentsOf: pushed.filter { !added.contains($0) })
        }
        for s in sources where result.names[s.id] != s.localizedName {
            result.names[s.id] = s.localizedName
        }
        // D-08: 상한 밀어내기로 목록에서 빠진 소스의 진입 언어는 .next로 돌린다.
        return (result.pruningEntries(), added)
    }

    /// A3: 진입 언어 정리는 `enabled`(선택 실패를 적용하기 **이전**에 읽은 켜진 소스 목록)로 한다.
    /// 선택 실패로 `sources`에서 잠깐 빠진(rejected) 소스는 `enabled`에 남아 있으므로 진입 언어를
    /// 지우지 않는다. `enabled`가 비면 카탈로그 읽기 실패로 보고 진입 정리를 건너뛴다(T-04.3-07).
    public func reconciled(
        with sources: [SourceInfo], enabled: [SourceInfo]
    ) -> (lists: KeyLists, added: [SourceID]) {
        let base = reconciled(with: sources)
        let live = enabled.isEmpty ? nil : Set(enabled.map(\.id))
        return (base.lists.pruningEntries(live: live), base.added)
    }

    // MARK: 이동

    /// SwiftUI onMove 규칙. toOffset은 이동 전 기준 위치다.
    public func moving(_ list: SourceList, fromOffsets: IndexSet, toOffset: Int) -> KeyLists {
        let current = ids(list)
        let offsets = fromOffsets.filter { current.indices.contains($0) }
        let target = min(max(toOffset, 0), current.count)
        let movingIDs = offsets.map { current[$0] }
        var rest = current
        for offset in offsets.reversed() { rest.remove(at: offset) }
        rest.insert(contentsOf: movingIDs, at: target - offsets.filter { $0 < target }.count)
        return with(list, rest)
    }

    /// id를 다른 목록 끝으로 옮긴다. 이미 그 목록에 있으면 self. 모르는 id도 대상 끝에 붙인다.
    /// from이 없으면 모든 목록에서 빼고 옮긴다(복제가 하나로 합쳐진다).
    public func moved(_ id: SourceID, to list: SourceList) -> KeyLists {
        moved(id, to: list, live: nil).pruningEntries()
    }

    /// moved(_:to:)에 상한을 더한다. 대상 caps·fn·assigned가 켜진 소스 기준으로 꽉 찼으면 self(D-30).
    /// 지정 상자 밖으로 나가면 그 소스의 단축키를 지운다(D-46 「뺐다가 다시 넣으면 다시 녹화」, W2).
    public func moved(_ id: SourceID, to list: SourceList, live: Set<SourceID>?) -> KeyLists {
        if lists(of: id) == [list] || (list == .excluded && self.list(of: id) == .excluded) { return self }
        let copy = removing(id)
        if copy.isFull(list, live: live) { return self }
        var next = copy.with(list, copy.ids(list) + [id])
        if list != .assigned { next.chords[id] = nil }
        return next.pruningEntries()
    }

    /// id를 모든 목록에서 빼고 대상 목록의 index 자리에 넣는다. 같은 목록 안 옮기기도 된다.
    /// live가 없으면 index는 id를 뺀 대상 목록 기준이고 0...count로 자른다.
    /// live가 있으면 index는 화면에 보이는(켜진) 소스 기준 자리다. 보이는 소스 V[index] 앞에 넣고,
    /// index가 보이는 개수 이상이면 마지막 보이는 소스 바로 뒤(보이는 소스가 없으면 끝)에 넣는다.
    /// 대상이 꽉 찼으면 self(D-30).
    public func moved(_ id: SourceID, to list: SourceList, at index: Int, live: Set<SourceID>? = nil) -> KeyLists {
        let copy = removing(id)
        if copy.isFull(list, live: live) { return self }
        var next = copy.inserting(id, into: list, at: index, live: live)
        // 지정 상자 안 재배치는 단축키를 유지하고, 밖으로 나갈 때만 지운다(D-46, W2).
        if list != .assigned { next.chords[id] = nil }
        return next.pruningEntries()
    }

    // MARK: 복제(2026-11-11)

    /// from 목록의 id 한 칸만 to 목록으로 옮긴다. 다른 목록의 복제는 그대로 둔다.
    /// to에 이미 복제가 있으면 둘을 하나로 합쳐 index 자리에 둔다. to가 excluded면 removed(_:from:)과 같다.
    /// index가 nil이면 끝에 넣는다. from == to면 같은 목록 안 자리 바꾸기다. 꽉 찼으면 self(D-30).
    public func moved(_ id: SourceID, from: SourceList, to list: SourceList, at index: Int? = nil,
                      live: Set<SourceID>? = nil) -> KeyLists {
        guard ids(from).contains(id) else { return self }
        if list == .excluded { return removed(id, from: from) }
        if from == .excluded { return copied(id, to: list, at: index, live: live).pruningEntries() }
        var copy = with(from, ids(from).filter { $0 != id })
        copy = copy.with(list, copy.ids(list).filter { $0 != id })
        if copy.isFull(list, live: live) { return self }
        var next = copy.inserting(id, into: list, at: index ?? Int.max, live: live)
        if from == .assigned && list != .assigned { next.chords[id] = nil }
        return next.pruningEntries()
    }

    /// id를 to 목록에 하나 더 넣는다(복제). 다른 목록의 자리는 그대로이고 「사용 안 함」에서는 빠진다.
    /// to가 excluded이거나 이미 to에 있거나 꽉 찼으면 self.
    public func copied(_ id: SourceID, to list: SourceList, at index: Int? = nil,
                       live: Set<SourceID>? = nil) -> KeyLists {
        guard list != .excluded, !ids(list).contains(id), !isFull(list, live: live) else { return self }
        var next = inserting(id, into: list, at: index ?? Int.max, live: live)
        next.excluded.removeAll { $0 == id }
        return next
    }

    /// from 목록에서만 뺀다. 다른 엔진 목록에 남은 복제가 없으면 「사용 안 함」 끝에 넣는다.
    /// 지정 상자에서 빼면 단축키도 지운다(D-46).
    public func removed(_ id: SourceID, from list: SourceList) -> KeyLists {
        guard list != .excluded, ids(list).contains(id) else { return self }
        var next = with(list, ids(list).filter { $0 != id })
        if list == .assigned { next.chords[id] = nil }
        if next.lists(of: id).isEmpty && !next.excluded.contains(id) { next.excluded.append(id) }
        return next.pruningEntries()
    }

    /// id를 list의 index 자리에 넣는다. index 해석은 moved(_:to:at:live:)와 같다. 이미 있는지는 보지 않는다.
    private func inserting(_ id: SourceID, into list: SourceList, at index: Int,
                           live: Set<SourceID>?) -> KeyLists {
        var target = ids(list)
        let position: Int
        if let live {
            let visible = target.indices.filter { live.contains(target[$0]) }
            let i = max(index, 0)
            if i < visible.count {
                position = visible[i]
            } else if let last = visible.last {
                position = last + 1
            } else {
                position = target.count
            }
        } else {
            position = min(max(index, 0), target.count)
        }
        target.insert(id, at: position)
        return with(list, target)
    }

    /// 지정 소스의 단축키를 정한다. 지정 목록에 없는 소스면 self. 같은 조합을 가진 다른 지정
    /// 소스가 있으면 그 소스의 조합을 지우고 이 소스에 준다(W4 「빼앗기」, 겹침은 막지 않는다).
    /// nil이면 지운다. 「지정 상자 안 순서 바꾸기」와 달리 명시적 녹화 결과라 조합을 바꾼다.
    public func settingChord(_ chord: KeyChord?, for id: SourceID) -> KeyLists {
        guard assigned.contains(id) else { return self }
        var copy = self
        guard let chord else {
            copy.chords[id] = nil
            return copy
        }
        for (other, value) in copy.chords where other != id && value == chord {
            copy.chords[other] = nil
        }
        copy.chords[id] = chord
        return copy
    }

    /// 이 조합을 이미 가진 다른 지정 소스(화면 알림용). 없으면 nil.
    public func chordOwner(of chord: KeyChord, excluding id: SourceID) -> SourceID? {
        assigned.first { $0 != id && chords[$0] == chord }
    }

    /// 엔진 맞춤 표: 켜진 지정 소스 중 단축키가 있는 것만 [`KeyChord`: 소스].
    public func chordTable(live: Set<SourceID>) -> [KeyChord: SourceID] {
        var table: [KeyChord: SourceID] = [:]
        for id in assigned where live.contains(id) {
            if let chord = chords[id] { table[chord] = id }
        }
        return table
    }

    /// 목록에서만 뺀다. 조합 삭제는 moved*가 대상 목록을 보고 정한다(W2).
    private func removing(_ id: SourceID) -> KeyLists {
        var copy = self
        copy.caps.removeAll { $0 == id }
        copy.fn.removeAll { $0 == id }
        copy.assigned.removeAll { $0 == id }
        copy.excluded.removeAll { $0 == id }
        return copy
    }

    /// 자기 목록 안에서 delta칸 옮긴다. 범위를 넘으면 그대로. 복제된 소스는 첫 목록에서 옮긴다.
    public func nudged(_ id: SourceID, by delta: Int) -> KeyLists {
        guard let list = list(of: id) else { return self }
        return nudged(id, in: list, by: delta)
    }

    /// list 안에서 delta칸 옮긴다. 범위를 넘거나 list에 없으면 그대로.
    public func nudged(_ id: SourceID, in list: SourceList, by delta: Int) -> KeyLists {
        guard let index = ids(list).firstIndex(of: id) else { return self }
        let newIndex = index + delta
        var current = ids(list)
        guard current.indices.contains(newIndex) else { return self }
        current.swapAt(index, newIndex)
        return with(list, current)
    }
}
