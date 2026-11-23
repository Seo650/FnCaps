import FnCapsCore
import SwiftUI

/// 설정창 전체: 사이드바 + 쪽 + 아래 메모 줄(D-39). 폭 690×DS.scale 고정, 높이는 675×DS.scale 이상에서 늘어난다.
/// 처음 설정은 별도 창(OnboardingWindowController)이 맡고, 이 창은 사이드바 행으로 그 진행만 비춘다(08.1 D-01, D-03).
/// 넘치는 쪽은 쪽 자기 ScrollView 안에서만 스크롤한다.
struct SettingsRootView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var ui: SettingsUIState
    /// 처음 설정 진행을 사이드바 「처음 설정 n/5」 행에 비추기 위해 함께 본다(D-03).
    @ObservedObject var onboarding: OnboardingUIState
    /// 사이드바 「처음 설정 n/5」를 눌렀을 때 처음 설정 창을 연다. 설정 창은 닫지 않는다(D-03, D-04).
    let openOnboarding: () -> Void
    @ObservedObject var updates: UpdateController
    @ObservedObject var reports: ReportController

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 0) {
                SettingsSidebar(ui: ui, headerLine: header.text, updateAvailable: header.available,
                                newSources: hasNewSources, setupStep: setupStep,
                                onSetup: openOnboarding)
                    .frame(width: DS.s(176))
                    .frame(maxHeight: .infinity)
                page
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(nsColor: .windowBackgroundColor))
            }
            MemoLine(ui: ui)
        }
        .frame(width: DS.s(690))
        .frame(minHeight: DS.s(675), maxHeight: .infinity)
        // 제목 막대 자리(위 여백 28~32)까지 루트가 채운다. 무시하지 않으면 최소 높이 675이
        // 여백을 뺀 자리보다 커서 가운데 정렬되며 메모 줄 아래가 잘린다(창 안 렌더로 확인).
        // 쪽 내용은 창 위에서 22, 사이드바는 창 버튼 아래에서 시작한다(확정 초안).
        .ignoresSafeArea(.container, edges: .top)
        // 새 소스 점은 쪽을 옮겨도 남는다. 타일에 마우스를 올렸다 떼거나 창을 닫으면 지워진다(04.1 UAT R1·R4).
    }

    /// 사이드바 「처음 설정 n/5」의 n = 누르면 돌아갈 단계(멈춘 단계, 🌐가 맞으면 3 → 4, 권한이 없으면 2).
    /// 마친 단계 수가 아니다(04.5 UAT 사용자 결정, 2026-11-15). 처음 설정 대상이 아니면 nil이라 행이 없다(D-16).
    private var setupStep: Int? {
        onboarding.sidebarStep(globeOK: !model.snapshot.globeNotice, needsGrant: model.snapshot.permissionPanel == .grant)
    }

    /// 지금 켜진 소스에 남은 새 소스 점이 있는지. 창이 열린 사이 시스템에서 지운 소스는 세지 않는다(리뷰 WR-01).
    private var hasNewSources: Bool {
        let s = model.snapshot
        if !s.pendingNewSourceIDs.isEmpty { return true }
        let live = Set((s.capsRows + s.fnRows + s.assignedRows + s.unassignedRows).map(\.id))
        return !ui.newTagIDs.isDisjoint(with: live)
    }

    /// 사이드바 머리 상태 줄: 최신이면 「버전 x · 최신」, 새 버전이면 주황 점 + 「새 버전 y」, 나머지는 「버전 x」(D-41, D-42).
    private var header: (text: String, available: Bool) {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "-"
        return updates.sidebarLine(version: version)
    }

    @ViewBuilder
    private var page: some View {
        switch ui.selectedPage {
        case .general: GeneralPage(model: model, ui: ui)
        case .keys: KeysPage(model: model, ui: ui)
        case .advanced: AdvancedPage(model: model, ui: ui)
        case .help: HelpPage(model: model, ui: ui)
        case .about: AboutPage(ui: ui, updates: updates)
        case .report: ReportPage(model: model, ui: ui, reports: reports)
        }
    }
}
