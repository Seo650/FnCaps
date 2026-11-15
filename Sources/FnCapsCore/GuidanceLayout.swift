import Foundation

/// 화면(도움말 > 일반 설정법)이 그릴 값을 계산하는 입력 스냅숏.
/// `sources`는 켜 둔 선택 가능 키보드 소스 전체다(사용 안 함 포함). 화면이 채운다(D-26).
public struct GuidanceInput: Equatable, Sendable {
    public var sources: [SourceInfo]
    public var caps: [SourceID]
    public var fn: [SourceID]
    public var assigned: [SourceID]
    /// D-14: 사용자의 키별 진입 언어. 권장 배치는 `.ruleOnly`로 계산한다(특정 언어 진입 무시).
    public var entry: EntryChoices
    /// macOS 시스템 언어(`Locale.preferredLanguages.first` 등). D-27 중심 언어 판정에 쓴다.
    public var systemLanguage: String?

    public init(
        sources: [SourceInfo], caps: [SourceID], fn: [SourceID], assigned: [SourceID] = [],
        entry: EntryChoices = EntryChoices(), systemLanguage: String?
    ) {
        self.sources = sources
        self.caps = caps
        self.fn = fn
        self.assigned = assigned
        self.entry = entry
        self.systemLanguage = systemLanguage
    }
}

/// 화면에 그리는 배치 하나. `maxPresses`·`onePressPercent`는 `PressReach` 계산값이다(D-23).
/// 04.4 UAT U-4: 후보의 모양. 도움말 개요 줄(어떤 배치인지 + 장점)을 고르는 데 쓴다.
public enum CandidateKind: Equatable, Sendable {
    /// 2개 국어: Caps 하나에 두 언어 순환, fn은 비운다.
    case capsOnly
    /// Caps [영어](macOS 기본 Caps) + fn, 단축키 없음.
    case macOSCaps
    /// 3개 국어: 중심 언어를 Caps와 fn 양쪽에 둔다(옛 D-52 「같은 언어를 여러 키에」).
    case duplicate
    /// Caps [중심, 영어] + fn 순환, 단축키 없음.
    case cycles
    /// Caps [중심, 영어] + fn 순환 + 남는 언어만 단축키.
    case cyclesShortcuts
    /// Caps [영어] + fn 2칸 + 나머지 단축키.
    case macOSShortcuts
    /// 모든 언어 최대 1번: Caps [영어] + fn 하나 + 나머지 단축키.
    case fast
    /// 영어계 소스가 없을 때의 옛 탐색 결과나 폴백.
    case other
}

public struct GuidancePlan: Equatable, Sendable {
    public var caps: [SourceID]
    public var fn: [SourceID]
    public var assigned: [SourceID]
    /// D-06: 이 배치로 눌렀을 때의 키별 진입 언어. 후보는 고정 진입 언어를 쓴다.
    public var entry: EntryChoices
    public var maxPresses: Int
    /// 지배 판정에 쓰는 1번 도달 비율(D-05 ②와 ③을 가르는 값). 옛 호출은 0으로 둔다.
    public var onePressPercent: Int
    public var languageCount: Int
    public var kind: CandidateKind

    public init(
        caps: [SourceID], fn: [SourceID], assigned: [SourceID],
        entry: EntryChoices = EntryChoices(),
        maxPresses: Int, onePressPercent: Int = 0, languageCount: Int,
        kind: CandidateKind = .other
    ) {
        self.kind = kind
        self.caps = caps
        self.fn = fn
        self.assigned = assigned
        self.entry = entry
        self.maxPresses = maxPresses
        self.onePressPercent = onePressPercent
        self.languageCount = languageCount
    }

    /// D-12 「사용 중」 판정: caps·fn은 순서까지 같고, 지정은 개수와 집합이 같으면 같은 배치다
    /// (UAT B1). 진입 언어는 목록이 2개 이상일 때만 엔진에서 뜻이 있으므로 그때만 비교한다.
    public func matches(caps: [SourceID], fn: [SourceID], assigned: [SourceID],
                        entry: EntryChoices) -> Bool {
        func effective(_ value: EntryLanguage, _ list: [SourceID]) -> EntryLanguage? {
            list.count >= 2 ? value : nil
        }
        return caps == self.caps
            && fn == self.fn
            && assigned.count == self.assigned.count
            && Set(assigned) == Set(self.assigned)
            && effective(entry.caps, caps) == effective(self.entry.caps, self.caps)
            && effective(entry.fn, fn) == effective(self.entry.fn, self.fn)
    }
}

/// D-21~D-28: 켜 둔 언어 수·중심 언어·권장 배치·지금 배치를 계산한다. 순수 로직이다
/// (SwiftUI·AppKit을 import하지 않는다). 숫자는 전부 `PressReach`(실제 `ListSwitcher`) 계산값이다.
public enum GuidanceLayout: Equatable, Sendable {
    /// 켜 둔 언어가 1개 이하(D-28). 화면은 빈 상태 한 줄을 보인다.
    case single
    case ready(Ready)

    public struct Ready: Equatable, Sendable {
        /// 영어계 1(있으면) + 외국어 언어 모드 수(D-21). 같은 언어의 여러 소스는 1개다.
        public var languageCount: Int
        public var english: SourceID?
        /// D-27 중심 언어. 같은 언어를 여러 키에 두기(H3)와 권장 배치의 첫 외국어다.
        public var center: SourceID
        /// D-02·D-04: 추천 순서대로 정렬한 후보(최대 3개). 비어 있지 않다.
        public var candidates: [GuidancePlan]
        /// D-12 「사용 중」: 후보마다 지금 배치가 그 후보인지. `candidates`와 같은 길이다.
        public var inUse: [Bool]
        /// 외국어 대표 소스 순서: [중심] + 나머지(사용자 fn 순서, 그다음 카탈로그 순서).
        public var foreignOrder: [SourceID]
        /// D-48 macOS 기본 그림: 켜 둔 선택 가능 소스(최대 `KeyLists.maxPerKey`). 순서는 최근 순서
        /// (MRU)라 뜻이 없고, 그림은 「켜 둔 것 전부를 돈다」만 보인다.
        public var macOSGlobe: [SourceID]

        public init(
            languageCount: Int, english: SourceID?, center: SourceID,
            candidates: [GuidancePlan], inUse: [Bool], foreignOrder: [SourceID],
            macOSGlobe: [SourceID] = []
        ) {
            self.languageCount = languageCount
            self.english = english
            self.center = center
            self.candidates = candidates
            self.inUse = inUse
            self.foreignOrder = foreignOrder
            self.macOSGlobe = macOSGlobe
        }
    }

    // MARK: - 만들기

    public static func make(_ input: GuidanceInput) -> GuidanceLayout {
        let classified = SourceClassifier.classify(input.sources)
        let infoByID = infoMap(input.sources)
        let reps = representatives(classified, fn: input.fn)
        let english = classified.base.first
        let languageCount = (english != nil ? 1 : 0) + reps.count
        guard languageCount >= 2, !reps.isEmpty else { return .single }

        let center = centerSource(
            reps: reps, fn: input.fn, systemLanguage: input.systemLanguage, infoByID: infoByID)
        let order = foreignOrder(reps: reps, center: center, fn: input.fn)
        let generated = CandidateGenerator.generate(
            english: english, foreign: order, sources: input.sources,
            languageCount: languageCount)
        // 폴백: 언어가 매우 많아 2번 안 후보가 하나도 없을 때(연구 A7). 옛 규칙으로 1개만 보인다.
        let candidates = generated.isEmpty
            ? [recommendedPlan(
                english: english, foreign: order, entry: input.entry.ruleOnly,
                sources: input.sources, languageCount: languageCount)]
            : generated
        // D-12 「사용 중」: 후보마다 지금 배치와 비교한다(지정은 집합 비교, UAT B1).
        let inUse = candidates.map { plan in
            plan.matches(
                caps: input.caps, fn: input.fn, assigned: input.assigned, entry: input.entry)
        }
        let globe = input.sources
            .filter { $0.isEnabled && $0.isSelectCapable }
            .map(\.id)
        return .ready(Ready(
            languageCount: languageCount, english: english, center: center,
            candidates: candidates, inUse: inUse, foreignOrder: order,
            macOSGlobe: Array(globe.prefix(KeyLists.maxPerKey))))
    }

    // MARK: - 부품

    private static func infoMap(_ sources: [SourceInfo]) -> [SourceID: SourceInfo] {
        var map: [SourceID: SourceInfo] = [:]
        for source in sources { map[source.id] = source }
        return map
    }

    /// 외국어 언어 모드마다 대표 소스 1개(D-21). 사용자의 fn 목록에 먼저 나오는 소스,
    /// 없으면 모드 첫 소스. 사용 안 함 소스는 fn 목록에 없으므로 자연히 뒤로 밀린다.
    private static func representatives(_ classified: ClassifiedSources, fn: [SourceID]) -> [SourceID] {
        classified.modes.compactMap { mode in
            fn.first(where: { mode.sources.contains($0) }) ?? mode.sources.first
        }
    }

    /// D-27 중심 언어: 시스템 언어가 켜 둔 외국어 안에 있으면 그것, 아니면 fn 목록의 첫 외국어,
    /// 그것도 없으면 첫 외국어 대표 소스.
    private static func centerSource(
        reps: [SourceID], fn: [SourceID], systemLanguage: String?,
        infoByID: [SourceID: SourceInfo]
    ) -> SourceID {
        if let key = systemModeKey(systemLanguage),
           let hit = reps.first(where: { id in
               infoByID[id].flatMap(SourceClassifier.modeKey(of:)) == key
           }) {
            return hit
        }
        if let firstInFn = fn.first(where: { reps.contains($0) }) { return firstInFn }
        return reps[0]
    }

    /// [중심] + 나머지(사용자 fn 순서, 그다음 카탈로그 순서).
    private static func foreignOrder(
        reps: [SourceID], center: SourceID, fn: [SourceID]
    ) -> [SourceID] {
        let catalog = Dictionary(reps.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        let fnIndex = Dictionary(fn.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        let rest = reps.filter { $0 != center }.sorted { a, b in
            let fa = fnIndex[a] ?? Int.max
            let fb = fnIndex[b] ?? Int.max
            if fa != fb { return fa < fb }
            return (catalog[a] ?? 0) < (catalog[b] ?? 0)
        }
        return [center] + rest
    }

    /// 시스템 언어("ja-JP", "zh-Hans-CN")의 모드 키. `SourceClassifier.modeKey`와 같은 규칙이다.
    private static func systemModeKey(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        let parts = raw.split(whereSeparator: { $0 == "-" || $0 == "_" })
        guard let first = parts.first else { return nil }
        let lang = first.lowercased()
        if parts.count > 1, parts[1].count == 4, parts[1].allSatisfy({ $0.isLetter }) {
            let script = parts[1].prefix(1).uppercased() + parts[1].dropFirst().lowercased()
            return "\(lang)-\(script)"
        }
        return lang
    }

    // MARK: - 권장 배치(폴백)

    /// D-24는 04.4 D-02로 바뀜. 폴백 전용: 후보 생성기가 빈 결과를 낼 때만 쓰는 옛 규칙이다.
    /// 후보 중 최대 누름 수가 가장 작은 것, 같으면 앞의 것(지정 단축키가 적은 것)을 고른다.
    /// `foreign`은 [중심] + 나머지 순서다.
    /// D-14·A2: 권장 배치는 사용자의 특정 언어 진입을 쓰지 않는다(`entry.ruleOnly`를 넘긴다).
    private static func recommendedPlan(
        english: SourceID?, foreign: [SourceID], entry: EntryChoices,
        sources: [SourceInfo], languageCount: Int
    ) -> GuidancePlan {
        let candidates = candidatesFor(english: english, foreign: foreign)
        var best: GuidancePlan?
        for candidate in candidates {
            let layout = KeyLayout(
                caps: candidate.caps, fn: candidate.fn, assigned: candidate.assigned,
                sources: sources, entry: entry)
            guard let measured = PressReach.measure(layout) else { continue }
            if best == nil || measured.maxPresses < best!.maxPresses {
                best = GuidancePlan(
                    caps: candidate.caps, fn: candidate.fn, assigned: candidate.assigned,
                    maxPresses: measured.maxPresses, languageCount: languageCount)
            }
        }
        if let best { return best }
        // 언어 2개 이상이면 후보는 항상 잰다. 방어적으로 첫 후보를 빈 횟수로 돌려준다.
        let fallback = candidates.first ?? ([], [], [])
        return GuidancePlan(
            caps: fallback.0, fn: fallback.1, assigned: fallback.2,
            maxPresses: 0, languageCount: languageCount)
    }

    private typealias Candidate = (caps: [SourceID], fn: [SourceID], assigned: [SourceID])

    /// 후보는 지정 단축키가 적은 것부터 놓는다(동률이면 앞의 것을 고르므로 D-24와 맞는다).
    private static func candidatesFor(english: SourceID?, foreign: [SourceID]) -> [Candidate] {
        guard let a = foreign.first else { return [] }
        if let english {
            if foreign.count == 1 { return [([english], [a], [])] }
            if foreign.count == 2 {
                return [([english], [a, foreign[1]], []),
                        ([english], [a], [foreign[1]])]
            }
            return [
                ([english], foreign, []),
                ([english], [a, foreign[1]], Array(foreign[2...])),
                ([english], [a], Array(foreign[1...])),
            ]
        }
        if foreign.count <= 1 { return [([a], [], [])] }
        if foreign.count == 2 { return [([a], [foreign[1]], [])] }
        if foreign.count == 3 {
            return [([a], [foreign[1], foreign[2]], []),
                    ([a], [foreign[1]], [foreign[2]])]
        }
        return [
            ([a], Array(foreign[1...]), []),
            ([a], [foreign[1], foreign[2]], Array(foreign[3...])),
            ([a], [foreign[1]], Array(foreign[2...])),
        ]
    }
}
