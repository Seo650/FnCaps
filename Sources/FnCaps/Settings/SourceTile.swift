import AppKit
import FnCapsCore
import FnCapsSystem
import SwiftUI

/// 입력 소스 타일 44×28(D-37, D-39, D-44). 테두리 없음, 왼쪽 손잡이 칸, 가운데 기호.
/// 지금 소스 = 오른쪽 위 초록 점, 새 소스 = 주황 점. 마우스를 올리면 1.06배와 이름 말풍선.
struct SourceTile: View {
    enum Style { case normal, unused, placeholder }

    let row: SourceRow?
    let style: Style
    var isCurrent = false
    var isNew = false
    var hovered = false
    /// 04-17 끄는 중.
    var lifted = false
    /// 끌기 손잡이 칸. 보기 전용 축소판(도움말)은 끈다.
    var showsGrip = true
    @Environment(\.colorScheme) private var scheme

    private static let width = CGFloat(RingGeometry.tileWidth)
    private static let height = CGFloat(RingGeometry.tileHeight)
    private static let shape = RoundedRectangle(cornerRadius: DS.s(8), style: .continuous)

    var body: some View {
        if style == .placeholder {
            Self.shape
                .strokeBorder(Color.secondary.opacity(0.5), style: StrokeStyle(lineWidth: DS.s(1.2), dash: [DS.s(4), DS.s(3)]))
                .frame(width: Self.width, height: Self.height)
        } else {
            tile
        }
    }

    private var dark: Bool { scheme == .dark }
    private var unused: Bool { style == .unused }

    private var fill: Color {
        if dark { return Color(white: unused ? 0.20 : 0.27) }
        return Color.white.opacity(unused ? 0.7 : 1)
    }

    private var shadowOpacity: Double {
        if dark { return 0.45 }
        return unused ? 0.07 : 0.14
    }

    private var shadowRadius: CGFloat { lifted ? DS.s(10) : (hovered ? DS.s(6) : DS.s(3)) }
    private var shadowY: CGFloat { lifted ? DS.s(5) : (hovered ? DS.s(3) : DS.s(1.5)) }
    private var scale: CGFloat { lifted ? 1.08 : (hovered ? 1.06 : 1) }

    private var tile: some View {
        HStack(spacing: 0) {
            if showsGrip { grip }
            glyph
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: Self.width, height: Self.height)
        .background(fill)
        .clipShape(Self.shape)
        .shadow(color: .black.opacity(shadowOpacity), radius: shadowRadius, y: shadowY)
        .overlay(alignment: .topTrailing) { badge }
        .scaleEffect(scale)
        // 사용 안 함 타일은 왼쪽부터 줄지어 있어 가운데 말풍선이 상자·창 왼쪽 밖으로 나간다. 타일 왼쪽에 맞춘다.
        .overlay(alignment: unused ? .topLeading : .top) { tooltip }
    }

    private var grip: some View {
        VStack(spacing: DS.s(2.5)) {
            ForEach(0..<3, id: \.self) { _ in
                HStack(spacing: DS.s(2.5)) { gripDot; gripDot }
            }
        }
        .frame(width: DS.s(11))
        .frame(maxHeight: .infinity)
        .background(Color.primary.opacity(0.07))
    }

    private var gripDot: some View {
        Circle().fill(Color.primary.opacity(0.35)).frame(width: DS.s(2), height: DS.s(2))
    }

    /// 메뉴 막대 입력 소스 아이콘 크기의 테두리 네모(D-44). 모든 소스가 같은 22×16 pt 네모에 글자를 넣는다.
    /// 크기는 메뉴 막대 스크린샷 실측(44×32 px @2x, 모서리 약 8 px). 글자가 길면 네모가 아니라 글자를 줄인다.
    static let badgeSize = CGSize(width: DS.s(22), height: DS.s(16))
    static let badgeCorner: CGFloat = DS.s(4)

    private var glyph: some View {
        let ink: Color = unused ? .secondary : .primary
        return Text(verbatim: row?.glyph ?? "")
            .font(DS.caption.weight(.semibold))
            .minimumScaleFactor(0.55)
            .lineLimit(1)
            .padding(.horizontal, DS.s(2))
            .frame(width: Self.badgeSize.width, height: Self.badgeSize.height)
            .overlay(RoundedRectangle(cornerRadius: Self.badgeCorner, style: .continuous).strokeBorder(ink, lineWidth: DS.s(1.2)))
            .foregroundStyle(ink)
    }

    @ViewBuilder
    private var badge: some View {
        if isCurrent || isNew {
            Circle()
                .fill(isCurrent ? DS.ok : DS.warn)
                .frame(width: DS.s(8), height: DS.s(8))
                .overlay(Circle().strokeBorder(Color(nsColor: .windowBackgroundColor), lineWidth: DS.s(1.5)))
                .offset(x: DS.s(3), y: DS.s(-3))
        }
    }

    @ViewBuilder
    private var tooltip: some View {
        if hovered, !lifted, let row {
            Text(verbatim: isNew ? LF("keys.tile.newTooltip", row.name) : row.name)
                .font(DS.caption.weight(.medium))
                .fixedSize()
                .padding(.horizontal, DS.s(8))
                .frame(height: DS.s(22))
                .background(RoundedRectangle(cornerRadius: DS.s(6)).fill(Color(nsColor: .controlBackgroundColor)))
                .shadow(color: .black.opacity(0.18), radius: DS.s(4), y: DS.s(2))
                .offset(y: DS.s(-28))
                .allowsHitTesting(false)
        }
    }
}
