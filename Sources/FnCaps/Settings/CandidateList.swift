import FnCapsCore
import SwiftUI

/// 04.4 D-07~D-12: 「FnCaps 권장」의 후보 목록(최대 3개, 추천 순서)과 그 그림 부품.
/// 도움말 「설정하기」와 처음 설정 5단계(04.5-04)가 같은 부품을 쓴다.
/// 확인 창은 창 컨트롤러(04.4-06)가 띄우므로 뷰는 `SettingsUIState.pendingCandidate`만 남긴다.
/// 화면 상태는 전부 `SettingsUIState`에 두고, 크기·글꼴은 `DS` 토큰만 쓴다(새 크기 토큰 없음).

// MARK: - 후보 목록

/// 후보 하나 = 머리 줄(권장 n · 단축키 · 최대 누름) + 「왜」 한 줄 + 축소판 + 버튼 줄.
/// 후보 사이는 `SettingsDivider`로 나누고, 후보가 1개면 구분선이 없다(D-04).
struct CandidateList: View {
    @ObservedObject var ui: SettingsUIState
    let ready: GuidanceLayout.Ready
    let tiles: HelpTiles
    /// 처음 설정 1단계는 그림만 보이므로 버튼 줄을 끈다.
    var showsActions = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(ready.candidates.indices, id: \.self) { index in
                // 후보는 둥근 상자 안 블록이라 구분선을 양쪽 모두 띄운다(오른쪽 끝까지 가면 상자 밖으로
                // 삐져나가 보인다, 04.5 UAT).
                if index > 0 { SettingsDivider().padding(.trailing, DS.rowInset) }
                candidate(index)
            }
        }
    }

    private func candidate(_ index: Int) -> some View {
        let plan = ready.candidates[index]
        return VStack(alignment: .leading, spacing: DS.s(8)) {
            header(index)
            Text(verbatim: whyText(plan))
                .font(DS.caption)
                .foregroundStyle(.secondary)
                .lineSpacing(DS.s(2))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            CandidatePicture(ui: ui, plan: plan, english: ready.english, tiles: tiles)
            if showsActions { actions(index, plan) }
        }
        .padding(.horizontal, DS.rowInset)
        .padding(.vertical, DS.s(12))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// D-07: 순번만 굵게(`DS.bodyEmphasis`), 나머지 사실은 `DS.rowTitle` + `.secondary`.
    /// `help.cand.head` 키는 만들지 않는다 — 두 `Text`로 나눠 굵기를 다르게 그린다.
    private func header(_ index: Int) -> some View {
        HStack(spacing: DS.s(4)) {
            Text(verbatim: rankText(index))
                .font(DS.bodyEmphasis)
            Text(verbatim: " · " + shortcutText(index)
                 + LF("help.cand.maxPress", ready.candidates[index].maxPresses))
                .font(DS.rowTitle)
                .foregroundStyle(.secondary)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.85)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private func rankText(_ index: Int) -> String {
        ready.candidates.count == 1
            ? L("help.cand.rank.only")
            : LF("help.cand.rank", index + 1)
    }

    private func shortcutText(_ index: Int) -> String {
        let count = ready.candidates[index].assigned.count
        // 단축키가 없는 후보는 그 부분을 적지 않는다(05-11 UAT 사용자 결정).
        return count == 0 ? "" : LF("help.cand.shortcuts", count) + " · "
    }

    /// 배치 개요 + 장점 한 줄(UAT U-2·U-4). 모양마다 문구가 하나다.
    private func whyText(_ plan: GuidancePlan) -> String {
        switch plan.kind {
        case .capsOnly: return L("help.cand.why.capsOnly")
        case .macOSCaps: return L("help.cand.why.macOSCaps")
        case .duplicate: return L("help.cand.why.duplicate")
        case .cycles: return L("help.cand.why.cycles")
        case .cyclesShortcuts: return L("help.cand.why.cyclesShortcuts")
        case .macOSShortcuts: return L("help.cand.why.macOSShortcuts")
        case .fast: return L("help.cand.why.fast")
        case .other: return L("help.cand.why.other")
        }
    }

    /// D-12: 지금 배치와 같은 후보는 버튼 대신 checkmark + 「사용 중」. 높이는 버튼 줄과 같게 둔다.
    private func actions(_ index: Int, _ plan: GuidancePlan) -> some View {
        let rank = rankText(index)
        return HStack(spacing: 0) {
            Spacer(minLength: 0)
            if ready.inUse[index] {
                HStack(spacing: DS.s(4)) {
                    Image(systemName: "checkmark")
                        .font(DS.controlFont)
                        .accessibilityHidden(true)
                    Text(verbatim: L("help.cand.inUse"))
                        .font(DS.controlFont)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(Text(verbatim: LF("help.cand.inUse.a11y", rank)))
            } else {
                Button(L("help.cand.use")) { ui.requestCandidate(plan) }
                    .buttonStyle(PillButtonStyle())
                    .disabled(ui.pendingCandidate != nil)
                    .accessibilityLabel(Text(verbatim: LF("help.cand.use.a11y", rank)))
            }
        }
        .frame(height: DS.s(24))
    }
}

// MARK: - 후보 그림

/// D-08: 축소판 한 벌 + 상자별 말. 말은 「어떻게 쓰는지」만 적고 「왜」는 `CandidateList`가 맡는다.
struct CandidatePicture: View {
    @ObservedObject var ui: SettingsUIState
    let plan: GuidancePlan
    let english: SourceID?
    let tiles: HelpTiles

    var body: some View {
        KeysMiniature(
            ui: ui,
            caps: plan.caps.map { tiles.row($0) },
            fn: plan.fn.map { tiles.row($0) },
            assigned: plan.assigned.map { tiles.row($0) },
            capsCaption: capsCaption.map(Self.keepArrow),
            capsNote: capsNote,
            fnCaption: fnCaption.map(Self.keepArrow),
            assignedCaption: assignedCaption,
            capsEntryID: entryID(plan.entry.caps, in: plan.caps),
            fnEntryID: entryID(plan.entry.fn, in: plan.fn))
    }

    /// 04.3 D-07: 진입 언어가 특정 언어일 때만 고리 밖 화살표를 그린다.
    private func entryID(_ value: EntryLanguage, in list: [SourceID]) -> SourceID? {
        if case .source(let id) = value, list.contains(id) { return id }
        return nil
    }

    /// D-08 + UAT U-1·U-7: 누르는 키와 도착. 더블탭은 목록 밖에서 두 번째 칸으로 갈 때만 쓴다.
    var capsCaption: String? {
        guard let first = plan.caps.first else { return nil }
        let key = "Caps Lock"
        // UAT U-7: 목록 밖 언어가 없는 두 칸이면 탭할 때마다 오갈 뿐이라 더블탭을 쓰지 않는다.
        if plan.caps.count == 2, coversAll(plan.caps) {
            return LF("help.cand.toggle", key,
                      tiles.row(plan.caps[0]).name, tiles.row(plan.caps[1]).name)
        }
        if plan.caps.count >= 2, case .source(let id) = plan.entry.caps,
           let index = plan.caps.firstIndex(of: id) {
            let next = plan.caps[(index + 1) % plan.caps.count]
            return LF("help.cand.press.two", key, tiles.row(id).name, tiles.row(next).name)
        }
        if plan.caps.count == 1 {
            return first == english
                ? LF("help.cand.caps.back", key, tiles.row(first).name)
                : LF("help.cand.press.one", key, tiles.row(first).name)
        }
        // 진입 언어가 「다음 언어」인 2개 이상 목록: 누를 때마다 다음 칸으로 간다.
        return LF("help.cand.fn.cycle", key)
    }

    /// UAT U-5(2026-11-14 사용자): 화살표 앞에서 줄을 바꾼다. 「Caps Lock 탭」 / 「→ 2벌식」.
    /// 키·동작 줄은 좁은 칸에서도 쪼개지지 않게 줄바꿈 없는 공백으로 둔다.
    static func keepArrow(_ text: String) -> String {
        text.components(separatedBy: "\n").map { line in
            guard let range = line.range(of: " → ") else { return line }
            let head = line[..<range.lowerBound].replacingOccurrences(of: " ", with: "\u{00A0}")
            return head + "\n→ " + line[range.upperBound...]
        }.joined(separator: "\n")
    }

    /// UAT U-3: Caps에 영어 밖의 언어가 있으면 macOS 기본(영어 ↔ 직전 언어)과 다르다. 그 동작을 흐린 줄로 보인다.
    var capsNote: String? {
        // 2개 국어는 Caps 순환과 macOS 기본(영어 ↔ 직전 언어)이 같은 동작이라 보이지 않는다.
        guard let english, plan.languageCount > 2,
              plan.caps.contains(where: { $0 != english }) else { return nil }
        return LF("help.cand.caps.macOS", tiles.row(english).name)
    }

    var fnCaption: String? {
        guard let first = plan.fn.first else { return nil }
        let key = "fn"
        // 두 칸 + 다음 언어: 목록 밖에서 와도 「지금 안 쓰는 쪽」으로 가므로 역시 오가는 표기다.
        if plan.fn.count == 2, coversAll(plan.fn) || plan.entry.fn == .next {
            return LF("help.cand.toggle", key,
                      tiles.row(plan.fn[0]).name, tiles.row(plan.fn[1]).name)
        }
        if plan.fn.count >= 2, case .source(let id) = plan.entry.fn,
           let index = plan.fn.firstIndex(of: id) {
            let next = plan.fn[(index + 1) % plan.fn.count]
            return LF("help.cand.press.two", key, tiles.row(id).name, tiles.row(next).name)
        }
        if plan.fn.count >= 2 { return LF("help.cand.fn.cycle", key) }
        return LF("help.cand.press.one", key, tiles.row(first).name)
    }

    /// 이 목록이 배치의 모든 언어를 덮는지(목록 밖에서 들어올 일이 없는지).
    private func coversAll(_ list: [SourceID]) -> Bool {
        Set(plan.caps + plan.fn + plan.assigned).isSubset(of: Set(list))
    }

    var assignedCaption: String? {
        guard !plan.assigned.isEmpty else { return nil }
        let names = plan.assigned.map { tiles.row($0).name }.joined(separator: ", ")
        return LF("help.cand.assigned", names)
    }
}

// MARK: - macOS 기본 그림

/// D-48 macOS 기본 그림: Caps Lock(A ↔ 직전 언어) + 🌐 고리(켜 둔 소스 전부, 회전 화살표 없음).
/// 🌐는 최근에 쓴 순서(MRU)로 가므로 정해진 순서를 그리지 않는다. 처음 설정 1단계도 다시 쓴다.
struct MacOSPicture: View {
    @ObservedObject var ui: SettingsUIState
    let ready: GuidanceLayout.Ready
    let tiles: HelpTiles

    var body: some View {
        let caps: [SourceRow] = ready.english.map { [tiles.row($0)] } ?? []
        return KeysMiniature(
            ui: ui,
            caps: caps,
            fn: ready.macOSGlobe.map { tiles.row($0) },
            capsCaption: L("help.setup.macos.caps"),
            // 영어가 있으면 Caps Lock으로 이미 가는 영어가 🌐 순서에 또 나온다는 점을 한 줄 더한다(2026-11-13).
            fnCaption: ready.english == nil
                ? L("help.setup.macos.globe")
                : L("help.setup.macos.globe") + "\n\n" + L("help.setup.macos.globe.english"),
            showsArrows: false,
            customCapsBox: ready.english.map { AnyView(MacCapsMiniBox(english: tiles.row($0))) })
    }
}

// MARK: - 공용 입력·행

extension AppSnapshot {
    /// 도움말 그림과 후보 계산이 쓰는 입력. 화면이 채운다(D-26).
    var guidanceInput: GuidanceInput {
        GuidanceInput(
            sources: helpSources,
            caps: capsRows.map(\.id),
            fn: fnRows.map(\.id),
            assigned: assignedRows.map(\.id),
            entry: entry,
            systemLanguage: systemLanguage)
    }
}

/// SourceID → 그림용 행. 사용자의 입력 소스 이름과 SourceGlyph 기호를 그대로 쓴다(D-26).
struct HelpTiles {
    private let rows: [SourceID: SourceRow]

    init(_ sources: [SourceInfo]) {
        var map: [SourceID: SourceRow] = [:]
        for source in sources {
            map[source.id] = Self.row(id: source.id, name: source.localizedName,
                                      languages: source.languages)
        }
        self.rows = map
    }

    private static func row(id: SourceID, name: String, languages: [String]) -> SourceRow {
        SourceRow(id: id, name: name, enabled: true,
                  glyph: SourceGlyph.text(id: id, languages: languages, name: name))
    }

    func row(_ id: SourceID) -> SourceRow {
        rows[id] ?? SourceRow(id: id, name: id, enabled: true, glyph: "•")
    }
}
