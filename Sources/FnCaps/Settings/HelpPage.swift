import FnCapsCore
import FnCapsSystem
import SwiftUI

/// 「도움말」 쪽(D-01, D-45): 설정하기 → 알아 둘 점 → 같은 언어를 여러 키에 두기.
/// 모든 횟수는 GuidanceLayout이 실제 ListSwitcher로 계산한 값이고, 그림은 사용자가 켜 둔
/// 입력 소스 이름·기호로 그린다(D-26). 계산은 이 쪽을 그릴 때만 한다(T-04.2-16).
struct HelpPage: View {
    @ObservedObject var model: AppModel
    @ObservedObject var ui: SettingsUIState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let setupAnchor = "help.setup"
    private static let notesAnchor = "help.notes"
    private static let globeAnchor = "help.notes.globe"

    var body: some View {
        let snapshot = model.snapshot
        let layout = GuidanceLayout.make(snapshot.guidanceInput)
        let tiles = HelpTiles(snapshot.helpSources)
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: DS.groupSpacing) {
                    Text(verbatim: L(SettingsPage.help.titleKey))
                        .font(DS.pageTitle)
                    group(Self.setupAnchor, L("help.setup.title"), trailing: setupTrailing(layout)) {
                        setupBox(layout, tiles)
                    }
                    group(Self.notesAnchor, L("help.notes.title")) {
                        notesBox()
                    }
                }
                .padding(.horizontal, DS.pageInsetH)
                .padding(.top, DS.pageInsetTop)
                .padding(.bottom, DS.s(20))
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onAppear { consumeAnchor(proxy) }
            .onChange(of: ui.helpAnchor) { _, _ in consumeAnchor(proxy) }
        }
    }

    /// 다른 쪽에서 넘어온 묶음 id로 스크롤한다. 한 번 쓰고 지운다(RESEARCH Pattern 5).
    /// 배치가 끝나기 전에는 먹지 않으므로 한 틱 미루고, 제목 줄만 0.6초 강조한다(움직임 줄이기면 생략).
    private func consumeAnchor(_ proxy: ScrollViewProxy) {
        guard let anchor = ui.helpAnchor else { return }
        ui.helpAnchor = nil
        DispatchQueue.main.async {
            proxy.scrollTo(anchor, anchor: .top)
            guard !reduceMotion else { return }
            ui.helpHighlighted = anchor
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                if ui.helpHighlighted == anchor { ui.helpHighlighted = nil }
            }
        }
    }

    // MARK: 묶음 틀

    /// 묶음 제목 + 상자. 스크롤 도착 id를 갖고, 도착한 묶음 제목만 잠깐 강조한다.
    /// `trailing`은 제목 줄 오른쪽에 두는 버튼이다(D-49).
    private func group<Content: View>(
        _ id: String, _ title: String, trailing: AnyView? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: DS.groupTitleGap) {
            HStack(spacing: DS.s(8)) {
                Text(verbatim: title)
                    .font(DS.groupTitle)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, DS.s(4))
                    .padding(.vertical, DS.s(1))
                    .background(
                        RoundedRectangle(cornerRadius: DS.s(4), style: .continuous)
                            .fill(ui.helpHighlighted == id ? DS.dropHighlight : Color.clear))
                Spacer(minLength: 0)
                if let trailing { trailing }
            }
            SettingsBox { content() }
        }
        .id(id)
    }

    // MARK: H0. 설정하기 (D-44, D-46~D-50)

    /// D-44·D-49: 이 쪽의 중심이다. 제목 줄 오른쪽 [키와 언어 열기]는 그림을 실제 화면과 잇는다.
    private func setupTrailing(_ layout: GuidanceLayout) -> AnyView? {
        guard case .ready = layout else { return nil }
        return AnyView(
            Button(L("help.setup.open")) { ui.selectedPage = .keys }
                .buttonStyle(PillButtonStyle()))
    }

    @ViewBuilder
    private func setupBox(
        _ layout: GuidanceLayout, _ tiles: HelpTiles
    ) -> some View {
        switch layout {
        case .ready(let ready):
            VStack(alignment: .leading, spacing: 0) {
                Picker(selection: $ui.helpSetupSegment) {
                    Text(verbatim: L("help.setup.segment.macos")).tag(HelpSetupSegment.macOS)
                    Text(verbatim: L("help.setup.segment.fncaps")).tag(HelpSetupSegment.recommended)
                } label: {
                    EmptyView()
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .font(DS.controlFont)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, DS.s(12))
                SettingsDivider()
                switch ui.helpSetupSegment {
                case .macOS:
                    MacOSPicture(ui: ui, ready: ready, tiles: tiles)
                        .padding(.horizontal, DS.rowInset)
                        .padding(.vertical, DS.s(12))
                    SettingsDivider()
                    HelpSetupSummaryLine()
                        .padding(.horizontal, DS.rowInset)
                        .padding(.vertical, DS.s(12))
                case .recommended:
                    // D-12: 권장 아래에는 요약 줄(같음/다름)을 두지 않는다. 후보가 자기 여백을 갖는다.
                    CandidateList(ui: ui, ready: ready, tiles: tiles)
                }
            }
        case .single:
            HelpSetupEmptyState()
        }
    }


    // MARK: H4. 알아 둘 점 (D-12~D-16)

    /// 설정 행 설명을 되풀이하지 않는 짧은 문단 다섯 개(D-04). 버튼은 🌐 항목의 키보드 설정 열기 하나만 둔다(2026-11-13).
    /// 1개 언어 빈 상태에서도 보인다(UI-SPEC 표).
    private func notesBox() -> some View {
        VStack(alignment: .leading, spacing: 0) {
            note(L("help.notes.ctrlSpace"))
            SettingsDivider()
            VStack(alignment: .leading, spacing: 0) {
                note(L("help.notes.globe"))
                Button(L("help.notes.globe.open")) { _ = InputSourceSettings.openKeyboard() }
                    .padding(.horizontal, DS.rowInset)
                    .padding(.bottom, DS.s(12))
            }
            .id(Self.globeAnchor)
            SettingsDivider()
            note(L("help.notes.indicator"))
            SettingsDivider()
            note(L("help.notes.capsLight"))
            SettingsDivider()
            note(L("help.notes.secureInput"))
        }
    }

    private func note(_ text: String) -> some View {
        GlobeText.make(text)
            .font(DS.rowTitle)
            .lineSpacing(DS.s(2))
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, DS.rowInset)
            .padding(.vertical, DS.s(12))
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - 「설정하기」 상자 조각(도움말 · 처음 설정 4단계 공용)

/// macOS 기본 그림 아래 한 줄. FnCaps를 만든 이유를 적는다(2026-11-13).
/// 처음 설정 4단계도 같은 줄을 쓴다(2026-11-14 사용자 결정).
struct HelpSetupSummaryLine: View {
    var body: some View {
        GlobeText.make(L("help.setup.macos.summary"))
            .font(DS.rowTitle)
            .lineSpacing(DS.s(2))
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 켜 둔 언어가 하나 이하일 때의 빈 상태(D-28). 도움말과 처음 설정 4단계가 같이 쓴다.
struct HelpSetupEmptyState: View {
    var body: some View {
        VStack(alignment: .leading, spacing: DS.s(8)) {
            Text(verbatim: L("help.setup.empty"))
                .font(DS.rowTitle)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button(L("help.setup.openSources")) { _ = InputSourceSettings.open() }
                    .buttonStyle(PillButtonStyle())
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, DS.rowInset)
        .padding(.vertical, DS.s(12))
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
