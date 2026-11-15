import FnCapsCore
import SwiftUI

/// 처음 설정 2단계(손쉬운 사용 권한, UI-SPEC §6-2, APP-02·APP-22).
/// 「일반」 쪽 권한 상자를 재사용하지 않고 가운데 전용 화면으로 그린다(2026-11-14 사용자 결정).
/// 상태 값만 `model.snapshot`에서 읽는다.
struct SetupPermissionStep: View {
    @ObservedObject var model: AppModel
    @ObservedObject var ui: SettingsUIState

    private var snapshot: AppSnapshot { model.snapshot }

    private var isStuck: Bool {
        snapshot.permissionPanel == .stuck || snapshot.permissionPanel == .stuckResetFailed
    }

    /// 이유 줄: 권한을 잃었으면 잃었다고 알리고(기존 `permission.lost`), 아니면 이유를 쓴다.
    private var reasonKey: String {
        snapshot.permissionPanel == .grant && snapshot.permissionLost
            ? "permission.lost"
            : "general.desc.permission"
    }

    var body: some View {
        VStack(spacing: 0) {
            iconTile
                .padding(.bottom, DS.groupSpacing)
            Text(verbatim: L("settings.permission.title"))
                .font(DS.pageTitle)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .padding(.bottom, DS.s(8))
            Text(verbatim: L(reasonKey))
                .font(DS.rowTitle)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(DS.s(2))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, DS.groupSpacing)
            buttonZone
            if isStuck {
                stuckNotes
                    .padding(.top, DS.s(8))
            }
            warnings
                .padding(.top, DS.groupSpacing)
        }
        .frame(maxWidth: DS.s(420))
        .frame(maxWidth: .infinity)
    }

    // MARK: 부품

    /// 아이콘 칸(S-12): 설정 상자와 같은 바탕·모서리라 1단계 앱 아이콘(80)과 같은 발자국이다.
    private var iconTile: some View {
        RoundedRectangle(cornerRadius: DS.boxCornerRadius, style: .continuous)
            .fill(DS.boxFill)
            .frame(width: DS.s(80), height: DS.s(80))
            .overlay {
                Image(systemName: "accessibility")
                    .resizable()
                    .scaledToFit()
                    .frame(width: DS.s(40), height: DS.s(40))
                    .foregroundStyle(.primary)
            }
            .accessibilityHidden(true)
    }

    /// 버튼 칸(S-13): 높이를 늘 예약해 허용 전후에 아래가 밀리지 않는다.
    private var buttonZone: some View {
        Group {
            switch snapshot.permissionPanel {
            case .grant:
                Button(L("general.permission.open")) { model.openAccessibilitySettings() }
                    .buttonStyle(ProminentButtonStyle())
                    .keyboardShortcut(.defaultAction)
            case .hidden:
                HStack(spacing: DS.s(6)) {
                    StatusDot(color: DS.ok)
                    Text(verbatim: L("settings.permission.granted"))
                        .font(DS.controlFont)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            case .stuck, .stuckResetFailed:
                // Claude의 선택: 키를 읽지 못하는 동안 「허용됨」을 보이지 않는다(§6-2).
                Color.clear
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: DS.controlHeight)
    }

    /// 권한이 막혔을 때의 안내. 상자를 만들지 않고 글과 버튼만 둔다(§6-2 「권한 잃음·막힘」).
    private var stuckNotes: some View {
        VStack(spacing: DS.s(8)) {
            Text(verbatim: L("permission.stuck.body"))
                .font(DS.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(DS.s(2))
                .fixedSize(horizontal: false, vertical: true)
            Button(L("permission.stuck.button")) { model.resetPermission() }
                .buttonStyle(PillButtonStyle())
                .disabled(snapshot.resetting)
            if snapshot.permissionPanel == .stuckResetFailed {
                Text(verbatim: L("permission.relist"))
                    .font(DS.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(DS.s(2))
                    .fixedSize(horizontal: false, vertical: true)
                Button(L("permission.button")) { model.openAccessibilitySettings() }
                    .buttonStyle(PillButtonStyle())
            }
        }
    }

    /// APP-02는 늘 보이고(닫기 없음), APP-22는 권한이 없으면 늘, 있으면 키 변경 앱이 실행 중이고
    /// 닫지 않았을 때만 보인다(D-40). 두 경고는 같은 폭(가운데 열 420)이다.
    private var warnings: some View {
        VStack(spacing: DS.groupSpacing) {
            WarningNote(text: L("permission.warning"))
            if snapshot.permissionPanel == .grant {
                WarningNote(text: L("general.conflict.warning"))
            } else if snapshot.trusted, !snapshot.conflictApps.isEmpty, !snapshot.conflictDismissed {
                WarningNote(text: L("general.conflict.warning"),
                            onDismiss: { model.dismissConflictWarning() },
                            dismissLabel: L("general.conflict.dismiss"))
            }
        }
    }
}
