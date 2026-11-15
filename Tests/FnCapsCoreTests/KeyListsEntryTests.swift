import Foundation
import Testing
@testable import FnCapsCore

// D-03, D-08, D-12, D-13, 04.3-03: 진입 언어(`EntryChoices`)가 `keyLists.v1` JSON에 저장되고,
// 옛 `outsideRule`에서 이전되며, 목록 변경 경로마다 정리되는지 시험한다.
//
// 정리 규칙 하나: `entry[key] == .source(id)`이고 `id`가 `ids(key.list)`에 없으면 `.next`.
// 멤버십 기준이므로 같은 목록 안 순서 변경(D-12)은 유지되고 복제 소스 하나만 빼도 다른 키는 산다.

private enum EFx {
    static let e = makeSource("e", ["en"])
    static let k = makeSource("k", ["ko"])
    static let j = makeSource("j", ["ja"])
    static let z = makeSource("z", ["zh-Hans"])

    static func entries(caps: EntryLanguage = .next, fn: EntryLanguage = .next) -> EntryChoices {
        EntryChoices(caps: caps, fn: fn)
    }

    static func json(_ text: String) -> Data { Data(text.utf8) }
}

@Suite struct KeyListsEntryTests {
    // MARK: - 저장·이전(D-03)

    /// 옛 keyLists.v1 JSON에는 entry 키가 없다. 넘겨받은 옛 전역 값으로 두 키를 채운다.
    @Test func missingEntryFillsFromLegacy() {
        let data = EFx.json(#"{"caps":["e"],"fn":["k","j"],"excluded":[],"names":{}}"#)

        guard case .valid(let last) = KeyLists.decoded(data, legacyEntry: .last) else {
            Issue.record("entry 없는 옛 JSON은 .valid여야 한다")
            return
        }
        #expect(last.entry == .both(.last))

        guard case .valid(let def) = KeyLists.decoded(data) else {
            Issue.record("legacyEntry 생략도 .valid여야 한다")
            return
        }
        #expect(def.entry == .both(.next))
    }

    /// entry가 이미 있으면 legacyEntry를 무시한다(멱등). 저장 전까지 매 실행 같은 결과.
    @Test func existingEntryIgnoresLegacy() {
        let data = EFx.json(
            #"{"caps":["e","k"],"fn":["j"],"excluded":[],"names":{},"entry":{"caps":"id:k","fn":"next"}}"#)
        guard case .valid(let lists) = KeyLists.decoded(data, legacyEntry: .last) else {
            Issue.record(".valid여야 한다")
            return
        }
        #expect(lists.entry == EFx.entries(caps: .source("k"), fn: .next))
    }

    /// T-04.3-05: entry 값이 깨져도 목록 전체가 `.corrupt`가 되지 않는다.
    @Test func brokenEntryIsLenient() {
        // 객체가 아닌 값(숫자)은 EntryChoices가 못 읽는다 → legacy로 채운다.
        let numeric = EFx.json(
            #"{"caps":["e"],"fn":["k"],"excluded":[],"names":{},"entry":7}"#)
        guard case .valid(let fromNumber) = KeyLists.decoded(numeric, legacyEntry: .last) else {
            Issue.record("entry:7도 .valid여야 한다")
            return
        }
        #expect(fromNumber.entry == .both(.last))
        #expect(fromNumber.caps == ["e"])
        #expect(fromNumber.fn == ["k"])

        // 객체 안의 모르는 문자열은 EntryLanguage 관대 디코더가 .next로 읽는다.
        let unknown = EFx.json(
            #"{"caps":["e"],"fn":["k"],"excluded":[],"names":{},"entry":{"caps":"foo"}}"#)
        guard case .valid(let fromUnknown) = KeyLists.decoded(unknown) else {
            Issue.record("모르는 문자열도 .valid여야 한다")
            return
        }
        #expect(fromUnknown.entry == .both(.next))
        #expect(fromUnknown.caps == ["e"])

        // 빈 ID("id:")는 소스가 아니므로 .next.
        let empty = EFx.json(
            #"{"caps":["e"],"fn":["k"],"excluded":[],"names":{},"entry":{"caps":"id:"}}"#)
        guard case .valid(let fromEmpty) = KeyLists.decoded(empty) else {
            Issue.record("id: 도 .valid여야 한다")
            return
        }
        #expect(fromEmpty.entry == .both(.next))
    }

    @Test func entryRoundTrips() {
        let lists = KeyLists(
            caps: ["e"], fn: ["k", "j"], excluded: [],
            entry: EFx.entries(caps: .source("e"), fn: .last))
        guard case .valid(let back) = KeyLists.decoded(lists.encoded()) else {
            Issue.record("왕복은 .valid여야 한다")
            return
        }
        #expect(back.entry == lists.entry)
        #expect(back == lists)
    }

    // MARK: - 만들기(D-13)

    @Test func migratedCarriesLegacyEntry() {
        let lists = KeyLists.migrated(
            sources: [EFx.e, EFx.k, EFx.j], legacyCapsSourceID: nil,
            legacyFnModeKeys: nil, legacyEntry: .last)
        #expect(lists.entry == .both(.last))
    }

    @Test func initialIsNextOnBothKeys() {
        #expect(KeyLists.initial(for: [EFx.e, EFx.k, EFx.j]).entry == .both(.next))
    }

    // MARK: - D-08: 멤버십이 줄면 .next

    /// 목록 밖으로 옮기면(moved 3종) 그 키의 진입 언어는 .next.
    @Test func movingSourceOutResetsCapsEntry() {
        let base = KeyLists(
            caps: ["e", "k"], fn: ["j", "z"], excluded: [],
            entry: EFx.entries(caps: .source("k")))

        #expect(base.moved("k", to: .fn).entry.caps == .next)
        #expect(base.moved("k", to: .fn, at: 0).entry.caps == .next)
        #expect(base.moved("k", from: .caps, to: .fn).entry.caps == .next)
        #expect(base.moved("k", from: .caps, to: .fn).fn.contains("k"))

        // WR-02(wave 2 검토): live 집합을 받는 moved 경로도 따로 확인한다.
        let live = base.moved("k", to: .fn, live: ["e", "k", "j", "z"])
        #expect(live.caps == ["e"])
        #expect(live.fn == ["j", "z", "k"])
        #expect(live.entry.caps == .next)
    }

    /// 지우거나 사용 안 함으로 보내면 .next. 다시 넣어도 자동 복원되지 않는다.
    @Test func removingSourceResetsAndDoesNotRestore() {
        let base = KeyLists(
            caps: ["e", "k"], fn: ["j", "z"], excluded: [],
            entry: EFx.entries(caps: .source("k")))

        #expect(base.removed("k", from: .caps).entry.caps == .next)
        #expect(base.moved("k", from: .caps, to: .excluded).entry.caps == .next)
        #expect(base.moved("k", to: .excluded).entry.caps == .next)

        let readded = base.removed("k", from: .caps).copied("k", to: .caps)
        #expect(readded.caps.contains("k"))
        #expect(readded.entry.caps == .next)
    }

    /// 상한 밀어내기(R4)로 목록에서 빠져도 .next.
    @Test func capacityPushOutResetsEntry() {
        let base = KeyLists(
            caps: ["a", "b", "c", "d", "e", "f", "k"], fn: [], excluded: [],
            entry: EFx.entries(caps: .source("k")))
        let live = ["a", "b", "c", "d", "e", "f", "k"].map { makeSource($0, ["en"]) }
        let result = base.reconciled(with: live).lists
        #expect(!result.caps.contains("k"))
        #expect(result.excluded.contains("k"))
        #expect(result.entry.caps == .next)
    }

    // MARK: - D-12: 같은 목록 안 순서 변경은 유지

    @Test func reorderingKeepsEntry() {
        let base = KeyLists(
            caps: ["e", "k"], fn: ["j", "z"], excluded: [],
            entry: EFx.entries(caps: .source("k")))

        #expect(base.moving(.caps, fromOffsets: [1], toOffset: 0).entry.caps == .source("k"))
        #expect(base.nudged("k", by: -1).entry.caps == .source("k"))
        #expect(base.moved("k", from: .caps, to: .caps, at: 0).entry.caps == .source("k"))
    }

    /// 복제된 소스를 다른 키에서만 빼도 이 키의 진입 언어는 산다.
    @Test func duplicateRemovalElsewhereKeepsEntry() {
        let base = KeyLists(
            caps: ["e", "k"], fn: ["k", "z"], excluded: [],
            entry: EFx.entries(caps: .source("k")))
        let after = base.removed("k", from: .fn)
        #expect(!after.fn.contains("k"))
        #expect(after.entry.caps == .source("k"))
    }

    /// fn 진입도 같은 규칙(대칭).
    @Test func fnEntryFollowsSameRules() {
        let base = KeyLists(
            caps: ["e"], fn: ["j", "k"], excluded: [],
            entry: EFx.entries(fn: .source("k")))

        #expect(base.moved("k", from: .fn, to: .caps).entry.fn == .next)
        #expect(base.removed("k", from: .fn).entry.fn == .next)
        #expect(base.nudged("k", in: .fn, by: -1).entry.fn == .source("k"))
        #expect(base.moved("k", from: .fn, to: .fn, at: 0).entry.fn == .source("k"))
    }

    // MARK: - settingEntry

    @Test func settingEntryRequiresMembershipForSource() {
        let base = KeyLists(caps: ["e"], fn: ["j"], excluded: [])

        let set = base.settingEntry(.source("e"), for: .caps)
        #expect(set.entry.caps == .source("e"))

        // 목록에 없는 소스는 넣지 않는다(엔진 규칙: 목록 밖은 .next).
        #expect(base.settingEntry(.source("k"), for: .caps) == base)

        // .next·.last는 멤버십과 무관하게 항상 설정한다.
        #expect(base.settingEntry(.last, for: .fn).entry.fn == .last)
        #expect(base.settingEntry(.next, for: .fn).entry.fn == .next)
    }

    // MARK: - pruningEntries

    @Test func pruningEntriesUsesLiveSet() {
        let base = KeyLists(
            caps: ["e", "k"], fn: ["j", "z"], excluded: [],
            entry: EFx.entries(caps: .source("k"), fn: .source("j")))

        // live에 없으면 .next.
        let pruned = base.pruningEntries(live: ["e", "j"])
        #expect(pruned.entry.caps == .next)
        #expect(pruned.entry.fn == .source("j"))

        // live가 없으면 멤버십만 본다.
        #expect(base.pruningEntries().entry.caps == .source("k"))
    }

    /// T-04.3-06: 디코드 때 목록에 없는 ghost 소스는 .next로 정리된다.
    @Test func normalizedDropsGhostSource() {
        let data = EFx.json(
            #"{"caps":["e"],"fn":["k"],"excluded":[],"names":{},"entry":{"caps":"id:ghost","fn":"last"}}"#)
        guard case .valid(let lists) = KeyLists.decoded(data) else {
            Issue.record(".valid여야 한다")
            return
        }
        #expect(lists.entry.caps == .next)
        #expect(lists.entry.fn == .last)
    }

    // MARK: - reconciled(with:enabled:) A3

    @Test func reconciledEnabledKeepsTemporarilyRejectedSource() {
        let base = KeyLists(
            caps: ["e", "k"], fn: ["j"], excluded: [],
            entry: EFx.entries(caps: .source("k")))
        // K가 선택 실패로 sources에는 없지만 켜진 목록(enabled)에는 있다 → 유지.
        let kept = base.reconciled(with: [EFx.e, EFx.j], enabled: [EFx.e, EFx.k, EFx.j]).lists
        #expect(kept.entry.caps == .source("k"))

        // enabled에도 없으면(진짜 꺼짐) .next.
        let dropped = base.reconciled(with: [EFx.e, EFx.j], enabled: [EFx.e, EFx.j]).lists
        #expect(dropped.entry.caps == .next)
    }

    /// 카탈로그 읽기 실패로 enabled가 비면 진입 정리를 건너뛴다(T-04.3-07).
    @Test func reconciledEmptyEnabledSkipsPruning() {
        let base = KeyLists(
            caps: ["e", "k"], fn: ["j"], excluded: [],
            entry: EFx.entries(caps: .source("k")))
        let kept = base.reconciled(with: [EFx.e, EFx.j], enabled: []).lists
        #expect(kept.entry.caps == .source("k"))
    }
}
