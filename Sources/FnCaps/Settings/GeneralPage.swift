import FnCapsCore
import SwiftUI

/// P1 「일반」: 상태 상자, 시작과 표시, 시스템(D-32, D-39, D-40, D-42).
struct GeneralPage: View {
    @ObservedObject var model: AppModel
    @ObservedObject var ui: SettingsUIState

    private var snapshot: AppSnapshot { model.snapshot }

    // MARK: 시작과 표시

    private var loginBinding: Binding<Bool> {
        Binding(
            get: { snapshot.login == .on || snapshot.login == .requiresApproval },
            set: { model.setLoginItem($0) })
    }

    private var loginCaption: String? {
        switch snapshot.login {
        case .requiresApproval: return L("login.requiresApproval")
        case .notFound: return L("login.notFound")
        case .failed: return L("login.failed")
        case .on, .off: return nil
        }
    }

    private var startupGroup: some View {
        SettingsGroup(title: L("settings.group.startup")) {
            SettingRow(title: L("window.loginItem"), caption: loginCaption, ui: ui) {
                Toggle(L("window.loginItem"), isOn: loginBinding).greenSwitch()
            }
            if snapshot.login == .requiresApproval || snapshot.login == .notFound {
                HStack {
                    Button(L("login.openLoginItems")) { model.openLoginItemsSettings() }
                        .buttonStyle(PillButtonStyle())
                    Spacer()
                }
                .padding(.horizontal, DS.rowInset)
                .padding(.top, DS.s(-4))
                .padding(.bottom, DS.s(12))
            }
            SettingsDivider()
            SettingRow(
                title: L("window.showIcon"),
                info: (id: "showIcon", text: L("settings.showIcon.info")),
                ui: ui
            ) {
                Toggle(L("window.showIcon"), isOn: Binding(
                    get: { !snapshot.iconHidden },
                    set: { model.setIconHidden(!$0) }))
                    .greenSwitch()
            }
            SettingsDivider()
            SettingRow(title: L("general.language.title"), caption: L("general.language.caption"), ui: ui) {
                Picker(L("general.language.title"), selection: Binding(
                    get: { snapshot.appLanguage },
                    set: { model.setAppLanguage($0) })) {
                    // 언어 자기 이름은 번역하지 않는다.
                    Text(verbatim: L("general.language.system")).tag(AppLanguage.system)
                    ForEach(AppLanguage.menuOrder, id: \.self) { lang in
                        Text(verbatim: lang.nativeName).tag(lang)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
            }
        }
    }

    // MARK: 시스템

    private var permissionCaption: String {
        // 권한이 있는 동안에는 권한을 끄기 전 주의를 덧붙인다(옛 permission.warning).
        snapshot.trusted
            ? L("general.permission.caption") + " " + L("permission.warning")
            : L("general.permission.caption")
    }

    private var systemGroup: some View {
        SettingsGroup(title: L("general.group.system")) {
            SettingRow(title: L("settings.permission.title"), caption: permissionCaption, ui: ui) {
                HStack(spacing: DS.s(6)) {
                    StatusDot(color: snapshot.trusted ? DS.ok : DS.warn, size: DS.s(7))
                        .accessibilityHidden(true)
                    Text(verbatim: L(snapshot.trusted
                        ? "settings.permission.granted"
                        : "settings.permission.needed"))
                        .font(DS.controlFont)
                        .foregroundStyle(.secondary)
                }
            }
            SettingsDivider()
            SettingRow(title: L("menu.restore"), caption: L("general.restore.caption"), ui: ui) {
                Button(L("settings.restore.button")) { model.restoreSystemState() }
                    .buttonStyle(PillButtonStyle())
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.groupSpacing) {
                Text(verbatim: L(SettingsPage.general.titleKey))
                    .font(DS.pageTitle)

                PermissionStatusSection(model: model, ui: ui, part: .status)

                PermissionStatusSection(model: model, ui: ui, part: .detail)

                startupGroup
                systemGroup
            }
            .padding(.horizontal, DS.pageInsetH)
            .padding(.top, DS.pageInsetTop)
            .padding(.bottom, DS.s(20))
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear { model.refreshLoginStatus() }
    }
}
