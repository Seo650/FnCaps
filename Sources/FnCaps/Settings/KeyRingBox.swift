import FnCapsCore
import SwiftUI

/// 목록별 화면 영역(좌표계 "keys"). Caps·fn은 고리 칸, 사용 안 함은 상자 전체.
struct KeyZoneFrameKey: PreferenceKey {
    static var defaultValue: [SourceList: CGRect] = [:]
    static func reduce(value: inout [SourceList: CGRect], nextValue: () -> [SourceList: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

/// Caps·fn 고리 중심(좌표계 "keys").
struct RingCenterKey: PreferenceKey {
    static var defaultValue: [SourceList: CGPoint] = [:]
    static func reduce(value: inout [SourceList: CGPoint], nextValue: () -> [SourceList: CGPoint]) {
        value.merge(nextValue()) { _, new in new }
    }
}

/// Caps 또는 fn 상자: 왼쪽 키 칸(키캡) + 오른쪽 고리 칸(D-39). 테두리 없음(D-37).
/// 고리는 「슬롯 목록」으로 그린다. nil 슬롯은 빈 칸이다(04-17 끌기가 쓴다).
/// 고리 아래 푸터에 키별 진입 언어 메뉴를 둘 수 있다(D-04, 04.3).
struct KeyRingBox: View {
    let list: SourceList
    let rows: [SourceRow]
    let slotIDs: [SourceID?]
    var frozenHeight: CGFloat?
    var highlighted = false
    var countWarning = false
    let currentID: SourceID?
    let newIDs: Set<SourceID>
    @ObservedObject var keys: KeysPageState
    var placeholderID: SourceID?
    /// 「n/6」 글자를 그릴지. macOS 기본 그림은 FnCaps 한도가 뜻이 없어 끈다(D-48).
    var showsCount = true
    /// 고리 회전 화살표를 그릴지. macOS 🌐는 최근 순서(MRU)라 정해진 회전 방향이 없어 끈다(D-48).
    var showsArrows = true
    /// 고리에 언어가 하나일 때 아래 글. 도움말 fn 상자는 「누르면 이 언어로 갑니다」를 쓴다.
    var singleKey = "keys.single"
    /// 이 키의 진입 언어(D-04). 엔진이 정리한 `snapshot.entry[key]`를 그대로 보인다.
    var entry: EntryLanguage = .next
    /// 진입 화살표를 그릴 타일(D-07). nil이면 그리지 않는다(기본 꺼짐 — 축소판 무변경).
    var entryID: SourceID?
    /// 고리 아래 진입 언어 푸터를 보일지(D-09). 축소판은 끈다.
    var showsEntryControl = false
    /// 끌기 중에는 메뉴를 잠근다(기존 끌기 중 컨트롤 규칙).
    var entryControlDisabled = false
    var onEntry: ((EntryLanguage) -> Void)?
    let tileContent: (SourceRow) -> AnyView

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 푸터 위 구분선 높이.
    private static let dividerHeight = DS.s(1)

    init(list: SourceList, rows: [SourceRow], slotIDs: [SourceID?]? = nil,
         frozenHeight: CGFloat? = nil, highlighted: Bool = false, countWarning: Bool = false,
         currentID: SourceID?, newIDs: Set<SourceID>, keys: KeysPageState,
         placeholderID: SourceID? = nil, showsCount: Bool = true, showsArrows: Bool = true,
         singleKey: String = "keys.single",
         entry: EntryLanguage = .next, entryID: SourceID? = nil,
         showsEntryControl: Bool = false, entryControlDisabled: Bool = false,
         onEntry: ((EntryLanguage) -> Void)? = nil,
         tileContent: @escaping (SourceRow) -> AnyView) {
        self.list = list
        self.rows = rows
        self.slotIDs = slotIDs ?? rows.map(\.id)
        self.frozenHeight = frozenHeight
        self.highlighted = highlighted
        self.countWarning = countWarning
        self.currentID = currentID
        self.newIDs = newIDs
        self.keys = keys
        self.placeholderID = placeholderID
        self.showsCount = showsCount
        self.showsArrows = showsArrows
        self.singleKey = singleKey
        self.entry = entry
        self.entryID = entryID
        self.showsEntryControl = showsEntryControl
        self.entryControlDisabled = entryControlDisabled
        self.onEntry = onEntry
        self.tileContent = tileContent
    }

    private var slotCount: Int { slotIDs.count }

    /// 빈 칸은 목록마다 많아야 하나라(DragSession.slots) 고정 키로 둔다. 자리가 옮겨 가면 빈 칸도 미끄러진다.
    private var slotKeys: [(index: Int, key: String)] {
        slotIDs.enumerated().map { ($0.offset, $0.element ?? "__gap") }
    }

    private var radii: RingGeometry.Radii {
        if let frozenHeight {
            return RingGeometry.radii(count: slotCount, maxBoxHeight: Double(frozenHeight))
        }
        return RingGeometry.radii(count: slotCount)
    }

    private var boxHeight: CGFloat { frozenHeight ?? CGFloat(RingGeometry.boxHeight(count: slotCount)) }

    /// 푸터는 확정된 rows 수로만 판정한다(슬롯 수 아님). 끌기 중에도 rows는 그대로라 높이가 튀지 않는다.
    /// 목록 0·1개는 기존 안내 줄을 그대로 두고 푸터를 숨긴다(D-09).
    private var showsFooter: Bool { showsEntryControl && rows.count >= 2 }

    private var emptyKey: String { list == .caps ? "keys.caps.empty" : "keys.fn.empty" }

    var body: some View {
        // 푸터는 고리 영역 밖 형제다. KeyZoneFrameKey·RingCenterKey는 ringZone 안에만 있다.
        // 상자 높이는 내용(고리 영역 + 푸터)을 따른다. 키 영역은 배경으로 두어 그 높이를 그대로 채운다(UAT U-1).
        VStack(spacing: 0) {
            ringZone
                .frame(height: boxHeight)
            if showsFooter {
                // 진입 언어 줄은 양옆이 같은 여백인 블록이라 구분선도 양쪽을 띄운다(UAT 2026-11-13).
                SettingsDivider()
                    .padding(.trailing, DS.rowInset)
                    .frame(height: Self.dividerHeight)
                footer
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.leading, DS.keyZoneWidth)
        .background(alignment: .leading) {
            ZStack {
                KeyZoneFill()
                Keycap(kind: list == .caps ? .caps : .fn)
            }
            .frame(width: DS.keyZoneWidth)
            .clipShape(UnevenRoundedRectangle(topLeadingRadius: DS.boxCornerRadius,
                                              bottomLeadingRadius: DS.boxCornerRadius,
                                              style: .continuous))
        }
        .frame(maxWidth: .infinity)
        // 말풍선이 상자 밖으로 나갈 수 있도록 상자 전체를 자르지 않는다.
        .background(RoundedRectangle(cornerRadius: DS.boxCornerRadius, style: .continuous).fill(DS.boxFill))
    }

    // MARK: 진입 언어 푸터(D-04, D-05)

    /// 제목·ⓘ·메뉴 한 줄. 설명 줄 대신 ⓘ(04.4 D-21, 04.2 D-35).
    private var footer: some View {
        HStack(spacing: 0) {
            Text(verbatim: L("keys.entry.title"))
                .font(DS.rowTitle)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .layoutPriority(0)
            InfoButton(title: L("keys.entry.title"),
                       items: [
                           .init(name: L("keys.outside.last"), text: L("keys.entry.info.last")),
                           .init(name: L("keys.outside.next"), text: L("keys.entry.info.next")),
                           .init(name: L("keys.entry.info.specificName"),
                                 text: L("keys.entry.info.specific")),
                       ],
                       footnote: L("keys.entry.info.example"),
                       isPresented: Binding(
                           get: { keys.entryInfoOpen == list },
                           set: { keys.entryInfoOpen = $0 ? list : nil }))
                .padding(.leading, DS.s(8))  // 지정 단축키 상자 제목·ⓘ 간격과 같다(04.4-09 렌더 점검)
            Spacer(minLength: DS.s(8))
            picker
        }
        .padding(.horizontal, DS.rowInset)
        // 메뉴(24pt)가 제목 글자보다 높아 위쪽 틈이 눈에 더 크다. 아래를 조금 더 줘 두 틈을 맞춘다(UAT U-1).
        .padding(.top, DS.s(8))
        .padding(.bottom, DS.s(11))
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .contain)
    }

    /// 선택 항목: 「다음 언어」·「쓰던 언어」·(구분선)·그 키 목록의 언어(고리 순서).
    /// 목록에 없는 소스는 엔진이 이미 「다음 언어」로 되돌렸으므로 화면도 그렇게 보인다(Pitfall 4).
    private var picker: some View {
        Picker(L("keys.entry.title"),
               selection: Binding(get: { shownEntry }, set: { onEntry?($0) })) {
            Text(verbatim: L("keys.outside.next")).tag(EntryLanguage.next)
            Text(verbatim: L("keys.outside.last")).tag(EntryLanguage.last)
            Divider()
            ForEach(rows, id: \.id) { row in
                Text(verbatim: row.name)
                    .truncationMode(.middle)
                    .tag(EntryLanguage.source(row.id))
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .font(DS.controlFont)
        .frame(maxWidth: DS.s(160))
        .fixedSize(horizontal: false, vertical: true)
        .disabled(entryControlDisabled)
        .accessibilityLabel(LF("keys.entry.a11y", L(list == .caps ? "keys.caps.title" : "keys.fn.title")))
    }

    /// 메뉴에 보일 값. 목록에 없는 소스는 「다음 언어」로 낮춰 보인다(T-04.3-14).
    private var shownEntry: EntryLanguage {
        if case let .source(id) = entry, !rows.contains(where: { $0.id == id }) {
            return .next
        }
        return entry
    }

    private var ringZone: some View {
        ZStack(alignment: .topTrailing) {
            UnevenRoundedRectangle(bottomTrailingRadius: DS.boxCornerRadius,
                                   topTrailingRadius: DS.boxCornerRadius, style: .continuous)
                .fill(highlighted ? DS.dropHighlight : Color.clear)

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if showsCount {
                Text(verbatim: LF("keys.count", rows.count, KeyLists.maxPerKey))
                    .font(DS.caption.monospacedDigit())
                    .foregroundStyle(countWarning ? AnyShapeStyle(Color.red) : AnyShapeStyle(.tertiary))
                    .padding(.trailing, DS.s(14))
                    .padding(.top, DS.s(10))
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(GeometryReader { geo in
            let frame = geo.frame(in: .named("keys"))
            Color.clear
                .preference(key: KeyZoneFrameKey.self, value: [list: frame])
                .preference(key: RingCenterKey.self, value: [list: CGPoint(x: frame.midX, y: frame.midY)])
        })
    }

    @ViewBuilder
    private var content: some View {
        switch slotCount {
        case 0:
            VStack(spacing: DS.s(6)) {
                SourceTile(row: nil, style: .placeholder)
                caption(L(emptyKey))
            }
        case 1:
            VStack(spacing: DS.s(8)) {
                slot(index: 0)
                caption(L(singleKey))
            }
        default:
            ring
        }
    }

    private func caption(_ text: String) -> some View {
        Text(verbatim: text)
            .font(DS.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, DS.s(12))
    }

    private var ring: some View {
        let r = radii
        let m = slotCount
        let tileW = CGFloat(RingGeometry.tileWidth)
        let tileH = CGFloat(RingGeometry.tileHeight)
        return ZStack {
            Ellipse()
                .stroke(Color.secondary.opacity(0.45), style: StrokeStyle(lineWidth: DS.s(1.3), dash: [DS.s(3), DS.s(3)]))
                .frame(width: 2 * r.a, height: 2 * r.b)
            ForEach(Array(RingGeometry.arrowAngles(count: m).enumerated()), id: \.offset) { _, t in
                if showsArrows {
                    Image(systemName: "arrowtriangle.right.fill")
                        .font(.system(size: CGFloat(RingGeometry.arrowSize)))
                        .foregroundStyle(Color.secondary)
                        .rotationEffect(.radians(RingGeometry.arrowRotation(angle: t, radii: r)))
                        .offset(x: r.a * cos(t), y: r.b * sin(t))
                        .accessibilityHidden(true)
                }
            }
            // 진입 화살표(D-07): 고리 밖에서 진입 타일로 들어오는 실선 한 개. 타일 아래 층에 그린다.
            // 끄는 중인 타일이 진입 언어면 숨긴다(같은 목록 안 이동이면 소스 ID를 따라간다, D-12).
            // 칸 수(m)는 끌어 넣는 중 빈칸을 포함하므로 실제 행 수도 본다(wave 4 검토 WR-03, D-09).
            if let entryID, m >= 2, rows.count >= 2, let entryIndex = slotIDs.firstIndex(of: entryID),
               keys.drag?.id != entryID {
                let g = RingGeometry.entryArrow(index: entryIndex, count: m, radii: r,
                                                length: 12 * RingGeometry.scale)
                // 축은 머리처럼 offset·rotation으로 그려 칸이 움직일 때 함께 애니메이션된다(wave 4 검토 WR-01).
                let dx = CGFloat(g.headX - g.tailX)
                let dy = CGFloat(g.headY - g.tailY)
                Capsule()
                    .fill(Color.primary.opacity(0.75))
                    .frame(width: (dx * dx + dy * dy).squareRoot() + DS.s(1.3), height: DS.s(1.3))
                    .rotationEffect(.radians(Double(atan2(dy, dx))))
                    .offset(x: CGFloat(g.tailX + g.headX) / 2, y: CGFloat(g.tailY + g.headY) / 2)
                .accessibilityHidden(true)
                .allowsHitTesting(false)
                .transition(.opacity)

                Image(systemName: "arrowtriangle.right.fill")
                    .font(.system(size: CGFloat(RingGeometry.arrowSize)))
                    .foregroundStyle(Color.primary.opacity(0.75))
                    .rotationEffect(.radians(g.rotation))
                    .offset(x: CGFloat(g.headX), y: CGFloat(g.headY))
                    .accessibilityHidden(true)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
            // 소스 ID로 정체성을 잡아 04-17에서 칸이 바뀔 때 타일이 미끄러지게 한다.
            ForEach(slotKeys, id: \.key) { i, _ in
                let id = slotIDs[i]
                let o = RingGeometry.slotOffset(index: i, count: m, radii: r)
                slot(index: i)
                    .offset(x: o.x, y: o.y)
                    .zIndex(keys.isHovered(id, in: list) ? 1 : 0)
            }
        }
        .frame(width: 2 * r.a + tileW, height: 2 * r.b + tileH)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: entryID)
    }

    @ViewBuilder
    private func slot(index i: Int) -> some View {
        if let id = slotIDs[i], let row = rows.first(where: { $0.id == id }) {
            tileContent(row).id(id)
        } else if placeholderID != nil {
            SourceTile(row: nil, style: .placeholder).id(placeholderID)
        } else {
            Color.clear
                .frame(width: CGFloat(RingGeometry.tileWidth), height: CGFloat(RingGeometry.tileHeight))
        }
    }
}
