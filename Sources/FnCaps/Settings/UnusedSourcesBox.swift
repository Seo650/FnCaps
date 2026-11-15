import FnCapsCore
import FnCapsSystem
import SwiftUI

/// 「사용 안 함」 상자(D-39). 키 칸 없음. 제목 줄 + 「입력 소스 추가…」(D-36), 아래 타일 한 줄.
/// 상자 전체가 끌기 영역 .excluded다(04-17).
struct UnusedSourcesBox: View {
    let rows: [SourceRow]
    let slotIDs: [SourceID?]
    var highlighted = false
    let currentID: SourceID?
    let newIDs: Set<SourceID>
    @ObservedObject var keys: KeysPageState
    @ObservedObject var ui: SettingsUIState
    var placeholderID: SourceID?
    let tileContent: (SourceRow) -> AnyView

    init(rows: [SourceRow], slotIDs: [SourceID?]? = nil, highlighted: Bool = false,
         currentID: SourceID?, newIDs: Set<SourceID>, keys: KeysPageState, ui: SettingsUIState,
         placeholderID: SourceID? = nil, tileContent: @escaping (SourceRow) -> AnyView) {
        self.rows = rows
        self.slotIDs = slotIDs ?? rows.map(\.id)
        self.highlighted = highlighted
        self.currentID = currentID
        self.newIDs = newIDs
        self.ui = ui
        self.keys = keys
        self.placeholderID = placeholderID
        self.tileContent = tileContent
    }

    private static let tileHeight = CGFloat(RingGeometry.tileHeight)

    var body: some View {
        VStack(alignment: .leading, spacing: DS.s(10)) {
            HStack(alignment: .firstTextBaseline, spacing: DS.s(8)) {
                Text(verbatim: L("keys.unused.title"))
                    .font(DS.bodyEmphasis)
                    .lineLimit(1)
                    .layoutPriority(1)
                // 설명은 ⓘ 안에 둔다. 긴 언어(fr·ru 등)에서 「입력 소스 추가…」 단추 옆에 들어가지 않는다(04.1 UAT S1·S4).
                InfoButton(id: "keys.unused", text: L("keys.unused.caption"), title: L("keys.unused.title"), ui: ui)
                    .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + DS.s(4) }
                Spacer(minLength: DS.s(8))
                Button(L("keys.addSource")) { InputSourceSettings.open() }
                    .buttonStyle(PillButtonStyle())
                    .fixedSize()
                    .layoutPriority(1)
            }
            .zIndex(0)

            if slotIDs.isEmpty {
                // 비었을 때는 얇게. 끄는 동안만 타일 높이로 늘려 놓을 자리를 넉넉히 둔다.
                Text(verbatim: L("keys.unused.none"))
                    .font(DS.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
                    .frame(height: keys.drag != nil ? Self.tileHeight : nil)
            } else {
                FlowLayout(spacing: DS.s(10), centered: true) {
                    ForEach(slotKeys, id: \.key) { i, _ in
                        slot(index: i)
                            .zIndex(keys.isHovered(slotIDs[i], in: .excluded) ? 1 : 0)
                    }
                }
                .zIndex(1)
            }
        }
        .padding(.horizontal, DS.s(16))
        .padding(.vertical, DS.s(12))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: DS.boxCornerRadius, style: .continuous)
            .fill(highlighted ? DS.dropHighlight : Color.clear))
        .background(RoundedRectangle(cornerRadius: DS.boxCornerRadius, style: .continuous).fill(DS.boxFill))
        .background(GeometryReader { geo in
            Color.clear.preference(key: KeyZoneFrameKey.self, value: [.excluded: geo.frame(in: .named("keys"))])
        })
    }

    /// 빈 칸은 목록마다 많아야 하나라(DragSession.slots) 고정 키로 둔다. 자리가 옮겨 가면 빈 칸도 미끄러진다.
    private var slotKeys: [(index: Int, key: String)] {
        slotIDs.enumerated().map { ($0.offset, $0.element ?? "__gap") }
    }

    @ViewBuilder
    private func slot(index i: Int) -> some View {
        if let id = slotIDs[i], let row = rows.first(where: { $0.id == id }) {
            tileContent(row).id(id)
        } else if placeholderID != nil {
            SourceTile(row: nil, style: .placeholder).id(placeholderID)
        } else {
            Color.clear.frame(width: CGFloat(RingGeometry.tileWidth), height: Self.tileHeight)
        }
    }
}

/// 폭이 모자라면 다음 줄로 넘기는 배치. `centered`면 줄마다 가운데로 모은다(2026-11-11).
struct FlowLayout: Layout {
    var spacing: CGFloat = 10
    var centered = false

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let rows = arrange(width: width, subviews: subviews)
        let height = rows.last.map { $0.y + $0.height } ?? 0
        let used = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? used, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = arrange(width: bounds.width, subviews: subviews)
        for row in rows {
            var x = centered ? bounds.minX + max(0, (bounds.width - row.width) / 2) : bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: bounds.minY + row.y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
        }
    }

    private struct Row {
        var indices: [Int] = []
        var y: CGFloat = 0
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if !current.indices.isEmpty && needed > width {
                rows.append(current)
                current = Row(y: current.y + current.height + spacing)
            }
            current.width = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            current.height = max(current.height, size.height)
            current.indices.append(index)
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}
