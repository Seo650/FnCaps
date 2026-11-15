import FnCapsCore
import FnCapsSystem
import SwiftUI

/// 처음 설정 단계 화면(04.4 D-14, D-15, UI-SPEC §3). 같은 설정 창 안에서 사이드바와 메모 줄 없이 5단계를 보인다.
/// 어디서든 [나중에](Esc)로 나가면 사이드바에 「처음 설정 n/5」가 남는다(D-16).
/// 틀은 다섯 단계가 같다(UI-SPEC §3): 위 pageInsetTop에서 왼쪽 제목으로 시작하는 스크롤 내용과
/// 메모 줄 모양의 아래 줄(높이 48, underPageBackgroundColor, 위 Divider). 아래 줄은 왼쪽 [나중에],
/// 가운데 단계 점 5개, 오른쪽 [이전]·[다음]/[마침]이다.
struct FirstRunSetupView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var ui: SettingsUIState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var snapshot: AppSnapshot { model.snapshot }
    private var globeOK: Bool { !snapshot.globeNotice }
    private var step: Int { ui.setupStep }

    /// 내용이 바뀔 때만 슬라이드·페이드를 건다(5단계 목록 ↔ 「직접 설정」 분기).
    private var contentID: String { "\(step)-\(ui.setupBranch)" }

    var body: some View {
        VStack(spacing: 0) {
            contentArea
            footer
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L("setup.title"))
    }

    // MARK: 틀

    /// 스크롤 내용. 1·2·3단계(환영·권한·🌐)만 세로 가운데에 두고 나머지는 위 왼쪽에서 시작한다.
    private var contentArea: some View {
        GeometryReader { proxy in
            ScrollView {
                content
                    .id(contentID)
                    .transition(reduceMotion
                        ? .identity
                        : .asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .opacity))
                    .padding(.horizontal, DS.pageInsetH)
                    // 처음 설정에는 사이드바가 없어 창 버튼이 제목 위에 온다. 루트가 위 여백(safe area)을
                    // 무시하므로 사이드바와 같은 창 버튼 자리(30)를 먼저 두고 평소 쪽 위 여백을 더한다(04.5 UAT C-3b).
                    .padding(.top, DS.s(30) + DS.pageInsetTop)
                    .padding(.bottom, DS.s(20))
                    .frame(maxWidth: .infinity, minHeight: proxy.size.height,
                           alignment: step <= 3 ? .center : .topLeading)
            }
        }
    }

    /// 아래 줄: 메모 줄(MemoLine)과 같은 틀이다. 높이·바탕·위 Divider·가로 여백이 같아
    /// 처음 설정을 나가도 줄이 바뀌지 않는다(UI-SPEC §3, G-2·S-1·S-2·S-8).
    private var footer: some View {
        // orchestrator decision 6: 2단계에서 권한이 없어도 [다음]은 꺼지지 않는다.
        // 권한이 없는 동안은 이 화면의 권한 버튼이 유일한 강조·기본 버튼이다.
        let nextIsProminent = !(step == 2 && snapshot.permissionPanel == .grant)
        return ZStack {
            HStack(spacing: DS.s(8)) {
                Button(L("setup.later")) { ui.leaveSetup() }
                    .buttonStyle(PillButtonStyle())
                    .keyboardShortcut(.cancelAction)
                Spacer(minLength: 0)
                if step > 1 {
                    Button(L("setup.back")) { goBack() }
                        .buttonStyle(PillButtonStyle())
                }
                nextButton(isProminent: nextIsProminent)
            }
            dots
        }
        .padding(.horizontal, DS.s(16))
        .frame(maxWidth: .infinity)
        .frame(height: DS.s(48))
        .background(Color(nsColor: .underPageBackgroundColor))
        .overlay(alignment: .top) { Divider() }
    }

    /// [이전]: 5단계 「직접 설정」 분기 쪽에서는 4단계가 아니라 5단계 목록으로 돌아간다(UI-SPEC S-17).
    private func goBack() {
        if step == FirstRunSetup.stepCount && ui.setupBranch {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                ui.setupBranch = false
            }
        } else {
            go(FirstRunSetup.previousStep(before: step, globeOK: globeOK))
        }
    }

    @ViewBuilder
    private func nextButton(isProminent: Bool) -> some View {
        if step < FirstRunSetup.stepCount {
            if isProminent {
                Button(L("setup.next")) {
                    go(FirstRunSetup.nextStep(after: step, globeOK: globeOK))
                }
                .buttonStyle(ProminentButtonStyle())
                .keyboardShortcut(.defaultAction)
            } else {
                Button(L("setup.next")) {
                    go(FirstRunSetup.nextStep(after: step, globeOK: globeOK))
                }
                .buttonStyle(PillButtonStyle())
            }
        } else {
            Button(L("setup.finish")) { ui.requestFinish() }
                .buttonStyle(ProminentButtonStyle())
                .keyboardShortcut(.defaultAction)
        }
    }

    /// 단계 점 5개(UI-SPEC §4). 건너뛴 3단계도 점은 그대로 5개다. 아래 줄 가운데에 둔다.
    private var dots: some View {
        HStack(spacing: DS.s(8)) {
            ForEach(1...FirstRunSetup.stepCount, id: \.self) { n in
                dot(n)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(LF("setup.step.a11y", step))
    }

    @ViewBuilder
    private func dot(_ n: Int) -> some View {
        let size = DS.s(8)
        if n == step {
            Circle().fill(Color.primary).frame(width: size, height: size)
        } else if n < step {
            Circle().fill(Color.primary.opacity(0.45)).frame(width: size, height: size)
        } else {
            Circle().strokeBorder(Color.secondary.opacity(0.3), lineWidth: 1)
                .frame(width: size, height: size)
        }
    }

    private func go(_ target: Int) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
            ui.setupGo(to: target)
        }
    }

    // MARK: 단계 내용

    @ViewBuilder
    private var content: some View {
        switch step {
        case 1: welcome
        case 2: SetupPermissionStep(model: model, ui: ui)
        case 3: globe
        case 4: basics
        default: SetupLayoutStep(model: model, ui: ui)
        }
    }

    /// 1단계: 환영 인사만 둔다(04.4 UAT U-11, UI-SPEC §6-1). 가운데 정렬은 이 단계만의 예외다(S-7).
    private var welcome: some View {
        VStack(spacing: 0) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: DS.s(80), height: DS.s(80))
                .accessibilityHidden(true)
                .padding(.bottom, DS.groupSpacing)
            Text(verbatim: L("setup.welcome.title"))
                .font(DS.pageTitle)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .padding(.bottom, DS.s(8))
            Text(verbatim: L("setup.welcome.body"))
                .font(DS.rowTitle)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(DS.s(2))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: DS.s(420))
        }
        .frame(maxWidth: .infinity)
    }

    /// 3단계: 🌐 키(UI-SPEC §6-3, 2026-11-14 사용자 결정). 2단계와 같은 가운데 열로 그리고
    /// 아이콘 칸에는 fn 키 그림을 크게 둔다. 제목 자리(가장 잘 보이는 곳)에 바꿀 값을
    /// 「🌐 키 → 입력 소스 변경」처럼 짧게 적는다. 값이 다르면 아래에 긴 설명(help.notes.globe, 2026-11-15
    /// 사용자 요청으로 되살림)·버튼·경고를, 같으면 위치 한 줄과 「같음」 상자를 둔다.
    private var globe: some View {
        VStack(spacing: 0) {
            fnIconTile
                .padding(.bottom, DS.groupSpacing)
            GlobeText.make(L("setup.globe.title"), size: DS.s(20))
                .font(DS.pageTitle)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .padding(.bottom, DS.s(8))
            if snapshot.globeNotice {
                GlobeText.make(L("help.notes.globe"))
                    .font(DS.rowTitle)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(DS.s(2))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, DS.groupSpacing)
                Group {
                    Button(L("help.notes.globe.open")) { _ = InputSourceSettings.openKeyboard() }
                        .buttonStyle(ProminentButtonStyle())
                }
                .frame(maxWidth: .infinity)
                .frame(height: DS.controlHeight)
                WarningNote(text: L("globe.notice"))
                    .padding(.top, DS.groupSpacing)
            } else {
                Text(verbatim: L("setup.globe.where"))
                    .font(DS.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, DS.groupSpacing)
                okBox
            }
        }
        .frame(maxWidth: DS.s(420))
        .frame(maxWidth: .infinity)
    }

    /// 3단계 아이콘 칸(S-12): 2단계와 같은 80pt 상자에 fn 키 그림을 크게 둔다.
    /// 배율은 기존 `Keycap`의 `scale` 값이다(새 크기 토큰 아님).
    private var fnIconTile: some View {
        RoundedRectangle(cornerRadius: DS.boxCornerRadius, style: .continuous)
            .fill(DS.boxFill)
            .frame(width: DS.s(80), height: DS.s(80))
            .overlay {
                Keycap(kind: .fn, scale: 1.25)
            }
            .accessibilityHidden(true)
    }

    /// 🌐 값이 권장과 같을 때의 「같음」 상자.
    private var okBox: some View {
        SettingsBox {
            HStack(alignment: .firstTextBaseline, spacing: DS.s(8)) {
                StatusDot(color: DS.ok)
                    .accessibilityHidden(true)
                Text(verbatim: L("setup.globe.ok"))
                    .font(DS.rowTitle)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, DS.rowInset)
            .padding(.vertical, DS.s(12))
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// 4단계: 전환 방식(UI-SPEC §6-4, 2026-11-14 사용자 결정).
    /// 도움말 「설정하기」의 macOS 기본 조각(그림·요약 줄)을 한 상자에 그대로 넣는다.
    /// 「FnCaps」 쪽은 권장 배치와 대응하지 않아 두지 않는다.
    private var basics: some View {
        let snapshot = model.snapshot
        let layout = GuidanceLayout.make(snapshot.guidanceInput)
        let tiles = HelpTiles(snapshot.helpSources)
        return VStack(alignment: .leading, spacing: DS.groupSpacing) {
            // 제목은 이 단계가 macOS 기본 전환을 보여 준다는 것을 밝힌다(2026-11-14 사용자 결정).
            SetupStepHeader(title: Text(verbatim: L("setup.basics.title")))
            SettingsBox {
                switch layout {
                case .ready(let ready):
                    VStack(alignment: .leading, spacing: 0) {
                        MacOSPicture(ui: ui, ready: ready, tiles: tiles)
                            .padding(.horizontal, DS.rowInset)
                            .padding(.vertical, DS.s(12))
                        SettingsDivider()
                        HelpSetupSummaryLine()
                            .padding(.horizontal, DS.rowInset)
                            .padding(.vertical, DS.s(12))
                    }
                case .single:
                    HelpSetupEmptyState()
                }
            }
        }
    }
}
