import FnCapsCore
import SwiftUI

/// 처음 설정 2단계(손쉬운 사용 권한, UI-SPEC §6-2, APP-02·APP-22).
/// 「일반」 쪽 권한 상자를 재사용하지 않고 전용 화면으로 그린다(2026-11-14 사용자 결정).
/// 머리는 08.1 사용자 선택(2026-11-22)의 머리 B(앱 아이콘 + 제목 + 이유)를 쓰고 본문은 왼쪽 정렬이다.
/// 상태 값만 `model.snapshot`에서 읽는다.
struct SetupPermissionStep: View {
    @ObservedObject var model: AppModel
    /// Return을 화면 안 권한 버튼에 묶는지(`OnboardingButtonRule.defaultAction == .openAccessibility`).
    var opensDefault: Bool = true

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

    /// macOS 27의 이름 변경을 이 화면에서 알린다(08.1 RESEARCH 결론 4). 기존 키만 쓰고 새 번역은 없다.
    private var pathKey: String {
        PermissionGuide.pathKey(osMajor: ProcessInfo.processInfo.operatingSystemVersion.majorVersion)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SetupStepHeader(title: Text(verbatim: L("settings.permission.title")),
                            subtitle: L(reasonKey))
                .padding(.bottom, DS.groupSpacing)
            permissionBody
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 버튼 칸 → 경로 줄 → 막힘 안내 → 경고.
    @ViewBuilder
    private var permissionBody: some View {
        buttonZone
        pathLine
            .padding(.top, DS.s(8))
        if isStuck {
            stuckNotes
                .padding(.top, DS.s(8))
        }
        warnings
            .padding(.top, DS.groupSpacing)
    }

    // MARK: 부품

    /// 버튼 칸(S-13): 높이를 늘 예약해 허용 전후에 아래가 밀리지 않는다.
    /// Return은 규칙이 [손쉬운 사용 설정 열기]를 기본 버튼으로 고를 때만 묶는다.
    private var buttonZone: some View {
        Group {
            switch snapshot.permissionPanel {
            case .grant:
                HStack(spacing: 0) {
                    accessibilityButton
                    Spacer(minLength: 0)
                }
            case .hidden:
                HStack(spacing: DS.s(6)) {
                    StatusDot(color: DS.ok)
                    Text(verbatim: L("settings.permission.granted"))
                        .font(DS.controlFont)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .combine)
            case .stuck, .stuckResetFailed:
                // Claude의 선택: 키를 읽지 못하는 동안 「허용됨」을 보이지 않는다(§6-2).
                Color.clear
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: DS.controlHeight)
    }

    private var accessibilityButton: some View {
        Button(L("general.permission.open")) { model.openAccessibilitySettings() }
            .buttonStyle(ProminentButtonStyle())
            .keyboardShortcut(opensDefault ? .defaultAction : nil)
    }

    /// 설정 경로 한 줄(UI-SPEC 2단계 2번): 버튼 칸 바로 아래. 권한이 있을 때만 보인다.
    @ViewBuilder
    private var pathLine: some View {
        if snapshot.permissionPanel == .grant {
            Text(verbatim: L(pathKey))
                .font(DS.caption)
                .foregroundStyle(.secondary)
                .lineSpacing(DS.s(2))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// 권한이 막혔을 때의 안내. 상자를 만들지 않고 글과 버튼만 둔다(§6-2 「권한 잃음·막힘」).
    private var stuckNotes: some View {
        VStack(alignment: .leading, spacing: DS.s(8)) {
            Text(verbatim: L("permission.stuck.body"))
                .font(DS.caption)
                .foregroundStyle(.secondary)
                .lineSpacing(DS.s(2))
                .fixedSize(horizontal: false, vertical: true)
            Button(L("permission.stuck.button")) { model.resetPermission() }
                .buttonStyle(PillButtonStyle())
                .disabled(snapshot.resetting)
            if snapshot.permissionPanel == .stuckResetFailed {
                Text(verbatim: L("permission.relist"))
                    .font(DS.caption)
                    .foregroundStyle(.secondary)
                    .lineSpacing(DS.s(2))
                    .fixedSize(horizontal: false, vertical: true)
                Button(L("permission.button")) { model.openAccessibilitySettings() }
                    .buttonStyle(PillButtonStyle())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// APP-02는 늘 보이고(닫기 없음), APP-22는 권한이 없으면 늘, 있으면 키 변경 앱이 실행 중이고
    /// 닫지 않았을 때만 보인다(D-40). 두 경고는 같은 폭(내용 폭 전체)이다.
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
