import AppKit
import FnCapsCore
import SwiftUI

/// 왼쪽 사이드바: 앱 머리(보이기만) + 항목 다섯(정보 · 일반 · 키와 언어 · 고급 · 도움말, D-45)
/// + 구분선 + 「문제 알리기」(D-30).
/// 선택 바탕을 옅은 회색으로 지키려고 목록 선택 대신 행을 직접 그린다(R3).
struct SettingsSidebar: View {
    @ObservedObject var ui: SettingsUIState
    let headerLine: String
    let updateAvailable: Bool
    /// 「키와 언어」에 아직 지우지 않은 새 소스 점이 있으면 사이드바 항목에도 주황 점(04.1 UAT R4).
    var newSources = false
    /// 처음 설정에서 마친 단계 수. nil이면 「처음 설정 n/5」 행이 없다(04.4 D-16).
    var setupStep: Int? = nil
    var onSetup: () -> Void = {}

    /// 위/아래 화살표가 오가는 순서.
    private static let order: [SettingsPage] = SettingsPage.sidebarItems

    var body: some View {
        VStack(alignment: .leading, spacing: DS.s(2)) {
            header
                .padding(.bottom, DS.s(12))
            if let step = setupStep {
                setupRow(step)
            }
            ForEach(SettingsPage.sidebarItems.filter { $0 != .report }) { page in
                item(page)
            }
            // 「도움말」과 「문제 알리기」 사이 구분선 하나(D-30). 맨 아래에 붙이지 않고 바로 아래에 잇는다.
            Divider()
                .padding(.horizontal, DS.s(8))
                .padding(.vertical, DS.s(8))
            item(.report)
            Spacer(minLength: 0)
        }
        .padding(DS.s(12))
        // 루트가 위 여백(safe area)을 무시하므로 창 버튼 아래 자리를 직접 둔다(확정 초안과 같은 값).
        .padding(.top, DS.s(30))
        .frame(width: DS.s(176))
        .frame(maxHeight: .infinity, alignment: .top)
        .background(
            Color(nsColor: .underPageBackgroundColor)
                .ignoresSafeArea(edges: .top))
        .focusable()
        .focusEffectDisabled()
        .onMoveCommand { direction in
            move(direction)
        }
    }

    /// 앱 머리: 아이콘, 이름, 버전 줄. 누를 수 없다(D-45). 새 버전이 있으면 버전 줄이 「새 버전 x」로 바뀌고 주황 점이 붙는다.
    private var header: some View {
        VStack(spacing: DS.s(6)) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: DS.s(56), height: DS.s(56))
                .accessibilityHidden(true)
            VStack(spacing: DS.s(2)) {
                Text(verbatim: "FnCaps")
                    .font(DS.rowTitle.weight(.semibold))
                Text(verbatim: headerLine)
                    .font(DS.caption)
                    .foregroundStyle(updateAvailable ? Color.primary : Color.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DS.s(10))
        .accessibilityElement(children: .combine)
    }

    /// 「처음 설정 n/5」 행. 「정보」 바로 위. 바탕은 0.06이었는데 다크 모드에서 거의 보이지 않아
    /// 0.12 + 굵은 글자로 올렸다(04.5 UAT C-4). 고른 쪽(0.10)과 헷갈리지 않게 굵기로 구분한다.
    private func setupRow(_ step: Int) -> some View {
        Button(action: onSetup) {
            row(symbol: "checklist", symbolSize: 13, title: LF("sidebar.setup", step),
                fill: Color.primary.opacity(0.12), titleWeight: .semibold) { EmptyView() }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(LF("sidebar.setup.a11y", step))
    }

    /// 행 하나(아이콘 + 글자 + 바탕). 쪽 항목과 처음 설정 행이 같은 줄을 쓴다.
    private func row<Extra: View>(
        symbol: String, symbolSize: CGFloat, title: String, fill: Color,
        iconOverlay: Bool = false, titleWeight: Font.Weight = .regular,
        @ViewBuilder trailing: () -> Extra
    ) -> some View {
        HStack(spacing: DS.s(8)) {
            Image(systemName: symbol)
                .font(.system(size: DS.s(symbolSize)))
                .frame(width: DS.s(16))
                .accessibilityHidden(true)
                // 새 소스 점은 아이콘 모서리에 단다. 글자 뒤에 두면 긴 언어(ru 「Клавиши и языки」)가 잘린다.
                .overlay(alignment: .topTrailing) {
                    if iconOverlay {
                        StatusDot(color: DS.warn, size: DS.s(8))
                            .offset(x: DS.s(3), y: DS.s(-4))
                            .accessibilityHidden(true)
                    }
                }
            Text(verbatim: title)
                .font(DS.rowTitle.weight(titleWeight))
                .lineLimit(1)
                // 영어 「Keys & Languages」가 폭 112에 조금 넘친다. 잘리지 않게 조금만 줄인다.
                .minimumScaleFactor(0.85)
            Spacer(minLength: 0)
            trailing()
        }
        .padding(.horizontal, DS.s(8))
        .frame(height: DS.s(28))
        .background(
            RoundedRectangle(cornerRadius: DS.s(6))
                .fill(fill))
        .contentShape(Rectangle())
    }

    private func item(_ page: SettingsPage) -> some View {
        let selected = ui.selectedPage == page
        return Button {
            ui.selectedPage = page
        } label: {
            // 원 안 기호(「정보」 ⓘ, 「도움말」 ?)는 14로 둔다. 다른 아이콘보다 작아 보여서다(04.1 UAT S10, 04.4 UAT U-8).
            row(symbol: page.symbol, symbolSize: page == .about || page == .help ? 14 : 13, title: L(page.sidebarKey),
                fill: selected ? Color.primary.opacity(0.10) : Color.clear,
                iconOverlay: page == .keys && newSources) {
                if page == .about && updateAvailable {
                    StatusDot(color: DS.warn, size: DS.s(8))
                        .accessibilityLabel(headerLine)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityValue(page == .keys && newSources ? L("keys.newTag") : "")
    }

    private func move(_ direction: MoveCommandDirection) {
        let order = Self.order
        guard let index = order.firstIndex(of: ui.selectedPage) else { return }
        switch direction {
        case .up where index > 0:
            ui.selectedPage = order[index - 1]
        case .down where index < order.count - 1:
            ui.selectedPage = order[index + 1]
        default:
            break
        }
    }
}
