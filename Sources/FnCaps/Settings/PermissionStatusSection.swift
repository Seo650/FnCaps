import FnCapsCore
import SwiftUI

/// 「일반」 상태 상자와 권한 안내(D-32, D-39, D-40). 처음 설정 2단계도 같은 상자를 쓴다(04.4 D-15).
struct PermissionStatusSection: View {
    enum Part { case status, detail }

    @ObservedObject var model: AppModel
    @ObservedObject var ui: SettingsUIState
    /// false면 🌐 값 경고(globe.notice)를 그리지 않는다. 처음 설정은 3단계가 따로 보인다.
    var showsGlobeNotice = true
    /// false면 권한 버튼이 보통 버튼이고 기본 단축키가 없다.
    var grantIsProminent = true
    var part: Part

    private var snapshot: AppSnapshot { model.snapshot }

    /// 상태 상자에 그릴 한 경우. 고르는 순서는 권한 > 꺼짐 > Caps Lock 사용 중 > 대기 > 동작.
    private enum Look { case permission, off, capsBlocked, waiting, running }

    private var look: Look {
        switch snapshot.status {
        case .permissionNeeded: return .permission
        case .off: return .off
        case .waiting: return .waiting
        case .running: return snapshot.capsBlocked ? .capsBlocked : .running
        }
    }

    private var lookStyle: (dot: Color, titleKey: String, descKey: String) {
        switch look {
        case .permission: return (DS.warn, "status.permission", "general.desc.permission")
        case .off: return (Color.secondary.opacity(0.6), "status.off", "general.desc.off")
        case .capsBlocked: return (DS.warn, "status.capsBlocked", "general.desc.capsBlocked")
        case .waiting: return (Color.secondary, "status.waiting", "general.desc.waiting")
        case .running: return (DS.ok, "status.running", "general.desc.running")
        }
    }

    private var pathKey: String {
        PermissionGuide.pathKey(osMajor: ProcessInfo.processInfo.operatingSystemVersion.majorVersion)
    }

    private func captionText(_ text: String) -> some View {
        GlobeText.make(text, size: DS.s(11))
            .font(DS.caption)
            .foregroundStyle(.secondary)
            .lineSpacing(DS.s(2))
            .fixedSize(horizontal: false, vertical: true)
    }

    private func caption(_ text: String) -> some View {
        captionText(text)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 「동작 중」 설명 + [권장 배치 보기](D-19). 폭이 모자라면 링크가 다음 줄 왼쪽으로 간다.
    private func runningCaption() -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: DS.s(4)) {
                captionText(L("general.desc.running"))
                moreButton
            }
            VStack(alignment: .leading, spacing: DS.s(2)) {
                captionText(L("general.desc.running"))
                HStack(spacing: 0) {
                    moreButton
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private var moreButton: some View {
        Button(L("general.desc.running.more")) {
            ui.showHelpSetup()
        }
        .buttonStyle(.link)
        .font(DS.controlFont)
    }

    // MARK: 상태 상자

    private var statusBox: some View {
        let style = lookStyle
        let dim = look == .permission || look == .off
        return KeyZoneBox {
            VStack(alignment: .leading, spacing: DS.s(8)) {
                Keycap(kind: .caps, scale: 0.8, dimmed: dim)
                Keycap(kind: .fn, scale: 0.8, dimmed: dim)
            }
            .padding(.vertical, DS.s(16))
        } content: {
            VStack(alignment: .leading, spacing: DS.s(8)) {
                HStack(spacing: DS.s(8)) {
                    StatusDot(color: style.dot)
                        .accessibilityHidden(true)
                    Text(verbatim: L(style.titleKey))
                        .font(DS.statusTitle)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: DS.s(8))
                    if look != .permission {
                        Text(verbatim: L("window.enableToggle"))
                            .font(DS.controlFont)
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                        Toggle(L("window.enableToggle"), isOn: Binding(
                            get: { snapshot.enabled },
                            set: { model.setEnabled($0) }))
                            .greenSwitch()
                            .disabled(!snapshot.trusted)
                    }
                }
                if look == .running {
                    // 처음 설정 중에는 도움말 쪽으로 갈 수 없으니(창이 설정 화면에 고정) 링크를 숨긴다.
                    if ui.setupMode { caption(L(style.descKey)) } else { runningCaption() }
                } else {
                    caption(L(style.descKey))
                }
                if snapshot.permissionPanel == .grant {
                    if grantIsProminent {
                        Button(L("general.permission.open")) { model.openAccessibilitySettings() }
                            .buttonStyle(ProminentButtonStyle())
                            .keyboardShortcut(.defaultAction)
                            .padding(.top, DS.s(2))
                    } else {
                        Button(L("general.permission.open")) { model.openAccessibilitySettings() }
                            .buttonStyle(PillButtonStyle())
                            .padding(.top, DS.s(2))
                    }
                    // D-40: 권한을 주기 전에는 감지 없이 늘 보인다.
                    WarningNote(text: L("general.conflict.warning"))
                        .padding(.top, DS.s(6))
                } else if look == .running, !snapshot.conflictApps.isEmpty, !snapshot.conflictDismissed {
                    // D-40: 동작 중에는 Karabiner-Elements·gksdud가 실행 중일 때만.
                    // X로 닫으면 숨긴다. 충돌 앱이 새로 켜지거나 권한이 풀렸다 다시 켜지면 다시 보인다(2026-11-15).
                    WarningNote(text: L("general.conflict.warning"),
                                onDismiss: { model.dismissConflictWarning() },
                                dismissLabel: L("general.conflict.dismiss"))
                }
                if showsGlobeNotice, snapshot.globeNotice {
                    // D-17: 🌐 값 경고는 상태 상자 안 별도 주황 상자. 닫기 없음(2026-11-13).
                    WarningNote(text: L("globe.notice"), actionTitle: L("globe.notice.more"), action: {
                        ui.helpAnchor = "help.notes.globe"
                        ui.selectedPage = .help
                    })
                }
            }
            .padding(.horizontal, DS.s(18))
            .padding(.vertical, DS.s(16))
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// 권한이 막혔을 때의 안내(옛 권한 패널 분기). 상태 상자 바로 아래 같은 폭.
    @ViewBuilder
    private var permissionDetail: some View {
        switch snapshot.permissionPanel {
        case .hidden:
            EmptyView()
        case .grant:
            if snapshot.permissionLost {
                SettingsBox {
                    VStack(alignment: .leading, spacing: DS.s(6)) {
                        Text(verbatim: L("permission.lost"))
                            .font(DS.rowTitle)
                            .lineSpacing(DS.s(2))
                            .fixedSize(horizontal: false, vertical: true)
                        caption(L(pathKey))
                    }
                    .padding(.horizontal, DS.rowInset)
                    .padding(.vertical, DS.s(12))
                }
            }
        case .stuck:
            stuckBox(resetFailed: false)
        case .stuckResetFailed:
            stuckBox(resetFailed: true)
        }
    }

    private func stuckBox(resetFailed: Bool) -> some View {
        SettingsBox {
            VStack(alignment: .leading, spacing: DS.s(8)) {
                Text(verbatim: L("permission.stuck.body"))
                    .font(DS.rowTitle)
                    .lineSpacing(DS.s(2))
                    .fixedSize(horizontal: false, vertical: true)
                caption(L(pathKey))
                Button(L("permission.stuck.button")) { model.resetPermission() }
                    .buttonStyle(PillButtonStyle())
                    .disabled(snapshot.resetting)
                if resetFailed {
                    caption(L("permission.relist"))
                    Button(L("permission.button")) { model.openAccessibilitySettings() }
                        .buttonStyle(PillButtonStyle())
                }
            }
            .padding(.horizontal, DS.rowInset)
            .padding(.vertical, DS.s(12))
        }
    }

    var body: some View {
        switch part {
        case .status: statusBox
        case .detail: permissionDetail
        }
    }
}
