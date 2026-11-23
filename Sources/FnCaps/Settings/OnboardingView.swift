import FnCapsCore
import FnCapsSystem
import SwiftUI

/// 처음 설정 단계 화면(04.4 D-14, D-15, UI-SPEC §3). 별도 창(OnboardingWindowController, 08.1 D-01)에서
/// 사이드바와 메모 줄 없이 5단계를 보인다. 모양은 08.1-04 시안 비교에서 사용자가 고른 하나다
/// (2026-11-22 사용자 선택 기록, 08.1-UI-SPEC.md): 머리 B, 아래 줄 F2, 진행 표시 P1.
/// 어디서든 [나중에](Esc)로 나가면 사이드바에 「처음 설정 n/5」가 남는다(D-16).
/// 강조·Return·[이전]·[마침] 확인 여부는 Core의 `OnboardingButtonRule` 한 곳이 정한다(D-07, D-08).
struct OnboardingView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var ui: OnboardingUIState
    /// [나중에]·Esc가 부른다(컨트롤러가 창을 닫고 markLeft는 windowShouldClose가 한다).
    let close: () -> Void
    /// 확인 없이 끝내는 [마침]이 부른다.
    let finish: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var snapshot: AppSnapshot { model.snapshot }
    private var globeOK: Bool { !snapshot.globeNotice }
    private var step: Int { ui.setupStep }

    /// 한 화면의 버튼 규칙. 한 화면에 강조는 하나이고 그 버튼이 Return이다(04.5 §3, UI-SPEC 「아래 줄」 표).
    private var footerRule: OnboardingFooter { OnboardingButtonRule.footer(for: screen) }

    private var screen: OnboardingScreen {
        OnboardingButtonRule.screen(
            step: step,
            needsGrant: snapshot.permissionPanel == .grant,
            globeNeedsChange: snapshot.globeNotice,
            branch: ui.setupBranch,
            singleSource: isSingleSource)
    }

    /// 5단계 빈 상태(GuidanceLayout .single)인지. UI-SPEC O-5a.
    private var isSingleSource: Bool {
        if case .single = GuidanceLayout.make(snapshot.guidanceInput) { return true }
        return false
    }

    /// 내용이 바뀔 때만 슬라이드·페이드를 건다(5단계 목록 ↔ 「직접 설정」 분기).
    private var contentID: String { "\(step)-\(ui.setupBranch)" }

    var body: some View {
        VStack(spacing: 0) {
            contentArea
            footer
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L("setup.title"))
        // 창이 없으므로 뷰가 바탕을 깔고 제목 막대 자리까지 채운다(중요 업데이트 뷰와 같음).
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .ignoresSafeArea(.container, edges: .top)
    }

    // MARK: 틀

    /// 머리 B는 1단계만 가운데 영웅이고 나머지 단계는 위에서 시작한다(UI-SPEC O-1 B).
    private var contentAlignment: Alignment { step == 1 ? .center : .topLeading }

    /// 스크롤 내용.
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
                           alignment: contentAlignment)
            }
        }
    }

    /// 아래 줄 F2: 중요 업데이트 창 버튼 줄 결(Sparkle 버튼 줄, Rectangle, LinearMouse, MonitorControl,
    /// `ImportantUpdateView.buttonRow`, 2026-11-22 사용자 선택). 바탕·선 없음, 진행 표시는 왼쪽 끝,
    /// 버튼은 오른쪽 끝에 모은다. [나중에]와 [이전] 사이만 간격을 더 준다.
    /// 위아래 여백은 같고(G-08.1-10) 값은 창 버튼(신호등)과 창 가장자리 간격 `DS.windowChromeInset`(18pt)이다
    /// (G-08.1-16, 2026-11-23 사용자: 버튼과 창 끝 간격이 신호등 버튼 정도).
    /// 가로 여백은 내용과 같은 DS.pageInsetH라 진행 점과 버튼이 본문 끝과 맞는다.
    private var footer: some View {
        HStack(spacing: DS.s(8)) {
            progressIndicator
            Spacer(minLength: 0)
            laterButton
            if footerRule.showsBack {
                backButton.padding(.leading, DS.s(8))
            }
            trailingButton
        }
        .padding(.horizontal, DS.pageInsetH)
        .padding(.vertical, DS.windowChromeInset)
        // F2는 원래 선이 없지만(UI-SPEC O-2), 5단계처럼 내용이 버튼 줄 위에서 잘릴 때 경계가 거칠어
        // 머리카락 선 하나를 더한다(UI-SPEC backstop, 08.1-06 렌더 점검 결정).
        .overlay(alignment: .top) { Divider() }
    }

    private var laterButton: some View {
        Button(L("setup.later")) { close() }
            .buttonStyle(PillButtonStyle())
            .keyboardShortcut(.cancelAction)
    }

    private var backButton: some View {
        Button(L("setup.back")) { goBack() }
            .buttonStyle(PillButtonStyle())
    }

    /// [다음]/[마침]. 강조·Return·확인 여부는 `footerRule`만 따른다.
    @ViewBuilder
    private var trailingButton: some View {
        if step < FirstRunSetup.stepCount {
            // 권한을 주기 전 2단계 [다음]은 눌리지 않는다(G-08.1-12). [나중에]·[이전]은 막지 않는다(04.4 D-16).
            if footerRule.prominent == .next {
                Button(L("setup.next")) { go(FirstRunSetup.nextStep(after: step, globeOK: globeOK)) }
                    .buttonStyle(ProminentButtonStyle())
                    .keyboardShortcut(defaultAction(.next))
                    .disabled(!footerRule.nextEnabled)
            } else {
                Button(L("setup.next")) { go(FirstRunSetup.nextStep(after: step, globeOK: globeOK)) }
                    .buttonStyle(PillButtonStyle())
                    .keyboardShortcut(defaultAction(.next))
                    .disabled(!footerRule.nextEnabled)
            }
        } else if footerRule.prominent == .finish {
            // 「직접 설정」 쪽·빈 상태의 [마침]은 강조 + Return이다(D-08, UI-SPEC O-5a).
            Button(L("setup.finish")) { finishAction() }
                .buttonStyle(ProminentButtonStyle())
                .keyboardShortcut(defaultAction(.finish))
        } else {
            // 5단계 후보 목록의 [마침]은 회색이고 Return에 묶지 않는다(D-08).
            Button(L("setup.finish")) { finishAction() }
                .buttonStyle(PillButtonStyle())
        }
    }

    /// Return에 묶을 버튼이면 `.defaultAction`, 아니면 nil.
    private func defaultAction(_ button: OnboardingButton) -> KeyboardShortcut? {
        footerRule.defaultAction == button ? .defaultAction : nil
    }

    /// [마침] 동작: 확인 시트를 거치는 화면이면 요청만 남기고, 아니면 바로 끝낸다(D-07, D-08).
    private func finishAction() {
        if footerRule.finishConfirms {
            ui.finishPromptRequested = true
        } else {
            finish()
        }
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

    /// 진행 표시 P1(04.5 §4, 2026-11-22 사용자 선택): 점 5개.
    private var progressIndicator: some View {
        HStack(spacing: DS.s(8)) {
            ForEach(1...FirstRunSetup.stepCount, id: \.self) { n in
                dot(n)
            }
        }
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
        case 2:
            SetupPermissionStep(
                model: model,
                opensDefault: footerRule.defaultAction == .openAccessibility)
        case 3: globe
        case 4: basics
        default:
            SetupLayoutStep(
                model: model, ui: ui, candidatesProminent: footerRule.candidatesProminent)
        }
    }

    /// 1단계: 환영 인사만 둔다(04.4 UAT U-11, UI-SPEC §6-1). 머리 B도 가운데 영웅을 유지한다.
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

    /// 3단계: 🌐 키(UI-SPEC §6-3, 2026-11-14 사용자 결정). 큰 타일 없이 머리가 제목을 맡는다.
    private var globe: some View {
        VStack(alignment: .leading, spacing: 0) {
            SetupStepHeader(title: GlobeText.make(L("setup.globe.title")))
                .padding(.bottom, DS.groupSpacing)
            globeBody
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 🌐 값이 다르면 긴 설명·버튼·경고를, 같으면 위치 한 줄과 「같음」 상자를 둔다.
    @ViewBuilder
    private var globeBody: some View {
        if snapshot.globeNotice {
            GlobeText.make(L("help.notes.globe"))
                .font(DS.rowTitle)
                .foregroundStyle(.secondary)
                .lineSpacing(DS.s(2))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, DS.groupSpacing)
            keyboardButton
            WarningNote(text: L("globe.notice"))
                .padding(.top, DS.groupSpacing)
        } else {
            Text(verbatim: L("setup.globe.where"))
                .font(DS.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, DS.groupSpacing)
            okBox
        }
    }

    /// [키보드 설정 열기]: 한 화면에 강조는 하나이고 그 버튼이 Return이다(OnboardingButtonRule).
    private var keyboardButton: some View {
        HStack(spacing: 0) {
            if footerRule.prominent == .openKeyboard {
                Button(L("help.notes.globe.open")) { _ = InputSourceSettings.openKeyboard() }
                    .buttonStyle(ProminentButtonStyle())
                    .keyboardShortcut(defaultAction(.openKeyboard))
            } else {
                Button(L("help.notes.globe.open")) { _ = InputSourceSettings.openKeyboard() }
                    .buttonStyle(PillButtonStyle())
                    .keyboardShortcut(defaultAction(.openKeyboard))
            }
            Spacer(minLength: 0)
        }
        .frame(height: DS.controlHeight)
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
                        MacOSPicture(miniKeys: ui.miniKeys, ready: ready, tiles: tiles)
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
