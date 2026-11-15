import AppKit
import FnCapsCore
import SwiftUI

/// 「FnCaps 정보」: 제목 아래 한 줄, 업데이트, GitHub 별, Buy Me a Coffee(D-02: 버전·업데이트·후원 + 별 행).
/// 앱 아이콘과 버전은 사이드바 앱 머리에 있으므로 여기에 앱 정체 상자를 두지 않는다.
struct AboutPage: View {
    @ObservedObject var ui: SettingsUIState
    @ObservedObject var updates: UpdateController
    @Environment(\.colorScheme) private var scheme

    private var meta: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return LF("about.meta", short, build)
    }

    // MARK: 업데이트

    private var updateGroup: some View {
        SettingsGroup(title: L("about.update.group")) {
            SettingRow(title: L("about.update.title"), caption: updates.statusText(), ui: ui) {
                updateControls
            }
            SettingsDivider()
            SettingRow(
                title: L("about.update.auto"),
                info: (id: "update.auto", text: L("about.update.auto.info")),
                ui: ui
            ) {
                Toggle(L("about.update.auto"), isOn: Binding(
                    get: { updates.autoCheck },
                    set: { updates.setAutoCheck($0) }))
                    .greenSwitch()
            }
        }
    }

    /// 새 버전이 있으면 앱 안에서 설치한다(D-06). 실패·되돌림이면 릴리스 페이지로도 갈 수 있다.
    @ViewBuilder
    private var updateControls: some View {
        switch updates.phase {
        case .done(.available):
            Button(L("about.update.open")) { updates.install() }
                .buttonStyle(ProminentButtonStyle())
        case .installFailed, .rolledBack:
            HStack(spacing: DS.s(8)) {
                Button(L("about.update.open")) { updates.install() }
                    .buttonStyle(ProminentButtonStyle())
                Button(L("about.update.releasePage")) {
                    updates.openRelease(ExternalLinks.releasesLatest)
                }
                .buttonStyle(PillButtonStyle())
            }
        case .downloading, .verifying, .installing:
            ProgressView().controlSize(.small)
        case .idle, .checking, .done(_):
            HStack(spacing: DS.s(8)) {
                if updates.phase == .checking {
                    ProgressView().controlSize(.small)
                }
                Button(L("about.update.checkNow")) { updates.checkNow() }
                    .buttonStyle(PillButtonStyle())
                    .disabled(updates.isBusy)
            }
        }
    }

    // MARK: GitHub

    private var githubGroup: some View {
        // 상표 이름이라 번역하지 않는다.
        SettingsGroup(title: "GitHub") {
            HStack(spacing: DS.s(10)) {
                Image(nsImage: NSImage(named: scheme == .dark ? "github-mark-dark" : "github-mark") ?? NSImage())
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(height: DS.s(24))
                    .accessibilityHidden(true)
                Text(verbatim: "GitHub")
                    .font(DS.rowTitle)
                Spacer(minLength: DS.s(8))
                Button {
                    ui.githubOpenFailed = !NSWorkspace.shared.open(ExternalLinks.githubRepo)
                } label: {
                    HStack(spacing: DS.s(4)) {
                        Image(systemName: "star")
                        Text(verbatim: "Star")
                    }
                }
                .buttonStyle(ProminentButtonStyle())
                .accessibilityLabel(L("about.github.a11y"))
            }
            .padding(.horizontal, DS.rowInset)
            .frame(height: DS.s(50))
            if ui.githubOpenFailed {
                Text(verbatim: L("about.support.openFailed"))
                    .font(DS.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, DS.rowInset)
                    .padding(.bottom, DS.s(10))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: Buy Me a Coffee

    private var coffeeGroup: some View {
        // 상표 이름이라 번역하지 않는다.
        SettingsGroup(title: "Buy Me a Coffee") {
            HStack(spacing: DS.s(10)) {
                Image(nsImage: NSImage(named: scheme == .dark ? "bmc-cup-dark" : "bmc-cup") ?? NSImage())
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(height: DS.s(24))
                    .accessibilityHidden(true)
                Text(verbatim: "Buy Me a Coffee")
                    .font(DS.rowTitle)
                Spacer(minLength: DS.s(8))
                Button(L("about.bmc.button")) {
                    ui.supportOpenFailed = !NSWorkspace.shared.open(ExternalLinks.buyMeACoffee)
                }
                .buttonStyle(ProminentButtonStyle())
            }
            .padding(.horizontal, DS.rowInset)
            .frame(height: DS.s(50))
            if ui.supportOpenFailed {
                Text(verbatim: L("about.support.openFailed"))
                    .font(DS.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, DS.rowInset)
                    .padding(.bottom, DS.s(10))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.groupSpacing) {
                VStack(alignment: .leading, spacing: DS.s(8)) {
                    Text(verbatim: L(SettingsPage.about.titleKey))
                        .font(DS.pageTitle)
                    Text(verbatim: meta)
                        .font(DS.caption)
                        .foregroundStyle(.secondary)
                }
                updateGroup
                githubGroup
                coffeeGroup
            }
            .padding(.horizontal, DS.pageInsetH)
            .padding(.top, DS.pageInsetTop)
            .padding(.bottom, DS.s(20))
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
