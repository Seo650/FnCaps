import FnCapsCore
import FnCapsSystem
import SwiftUI

/// 처음 설정 5단계(04.5-04, UI-SPEC §6-5): 「FnCaps 권장」 후보 목록과 그 맨 마지막 「직접 설정」 행,
/// 그리고 그 행을 눌렀을 때 같은 단계 안에서 보이는 분기 쪽(안내 4행)이다.
/// 단계는 5 그대로 두고 저장하지 않는다(S-15·S-17): 분기 여부는 `OnboardingUIState.setupBranch`만 쓴다.
struct SetupLayoutStep: View {
    @ObservedObject var model: AppModel
    @ObservedObject var ui: OnboardingUIState
    /// 후보 [이 설정 사용하기]를 강조할지. OnboardingView가 OnboardingButtonRule의 candidatesProminent를 넘긴다(G-08.1-13).
    let candidatesProminent: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 분기가 열릴 때 제목으로 VoiceOver 포커스를 옮긴다(UI-SPEC §6-5 접근성).
    @AccessibilityFocusState private var titleFocused: Bool

    var body: some View {
        if ui.setupBranch {
            customPage
        } else {
            listPage
        }
    }

    // MARK: - 5단계 목록

    private var listPage: some View {
        VStack(alignment: .leading, spacing: DS.groupSpacing) {
            SetupStepHeader(title: Text(verbatim: L("setup.layout.title")))
            switch GuidanceLayout.make(model.snapshot.guidanceInput) {
            case .ready(let ready):
                // S-9: 묶음 제목은 스크롤 영역 안에 두고, 후보 목록 맨 아래에 「직접 설정」 행을 붙인다.
                SettingsGroup(title: L("help.setup.segment.fncaps")) {
                    CandidateList(ui: ui, miniKeys: ui.miniKeys, ready: ready, tiles: HelpTiles(model.snapshot.helpSources), prominentUse: candidatesProminent)
                    SettingsDivider()
                    customRow
                }
            case .single:
                // 언어가 하나면 직접 설정할 배치가 없다(C-4d): 빈 상태와 입력 소스 설정 열기만 보인다.
                Text(verbatim: L("help.setup.empty"))
                    .font(DS.rowTitle)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button(L("help.setup.openSources")) { _ = InputSourceSettings.open() }
                        .buttonStyle(PillButtonStyle())
                    Spacer(minLength: 0)
                }
            }
        }
    }

    /// §6-5 「직접 설정」 행: 후보 행과 같은 여백, 오른쪽 chevron, 호버 바탕. 누르면 같은 5단계 안 분기로.
    private var customRow: some View {
        Button {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                ui.setupCustomHover = false
                ui.setupBranch = true
            }
        } label: {
            HStack(spacing: DS.s(8)) {
                VStack(alignment: .leading, spacing: DS.s(2)) {
                    Text(verbatim: L("setup.custom.row"))
                        .font(DS.rowTitle)
                    Text(verbatim: L("setup.custom.row.caption"))
                        .font(DS.caption)
                        .foregroundStyle(.secondary)
                        .lineSpacing(DS.s(2))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: DS.s(8))
                Image(systemName: "chevron.right")
                    .font(DS.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, DS.rowInset)
            .padding(.vertical, DS.s(12))
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ui.setupCustomHover ? DS.dropHighlight : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { ui.setupCustomHover = $0 }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("setup.custom.row.a11y"))
        .accessibilityAddTraits(.isButton)
    }

    // MARK: - 분기 쪽 「직접 설정」

    /// §6-5 분기 쪽: 머리(제목 + 보조 줄)와 안내 4행. 지정 단축키 행은 넣지 않는다(S-16, M-7 임시 처리).
    private var customPage: some View {
        VStack(alignment: .leading, spacing: DS.groupSpacing) {
            SetupStepHeader(title: Text(verbatim: L("setup.custom.row")),
                            subtitle: L("setup.custom.sub"))
                .accessibilityFocused($titleFocused)
            SettingsGroup(title: nil) {
                item("arrow.left.and.right", "setup.custom.drag.title", "setup.custom.drag.caption")
                SettingsDivider(inset: DS.rowInset + DS.s(36))
                item("plus.circle", "setup.custom.add.title", "setup.custom.add.caption")
                SettingsDivider(inset: DS.rowInset + DS.s(36))
                item("plus.square.on.square", "setup.custom.dup.title", "setup.custom.dup.caption")
                SettingsDivider(inset: DS.rowInset + DS.s(36))
                item("arrow.turn.down.right", "keys.entry.title", "setup.custom.entry.caption")
            }
        }
        .onAppear { titleFocused = true }
    }

    /// 아이콘 칸(24) + 제목(`DS.bodyEmphasis`) + 설명(`DS.caption`, 최대 3줄). 행은 한 요소로 읽는다.
    private func item(_ symbol: String, _ titleKey: String, _ captionKey: String) -> some View {
        HStack(alignment: .top, spacing: DS.s(12)) {
            Image(systemName: symbol)
                .font(DS.rowTitle)
                .foregroundStyle(.secondary)
                .frame(width: DS.s(24), alignment: .center)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: DS.s(2)) {
                Text(verbatim: L(titleKey))
                    .font(DS.bodyEmphasis)
                Text(verbatim: L(captionKey))
                    .font(DS.caption)
                    .foregroundStyle(.secondary)
                    .lineSpacing(DS.s(2))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, DS.rowInset)
        .padding(.vertical, DS.s(12))
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
