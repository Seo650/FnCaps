import FnCapsCore
import SwiftUI

/// 알림 한 줄. 같은 이름의 소스가 둘 있어도 줄이 겹치지 않도록 소스 ID로 구분한다(04-REVIEW IN-07).
private struct AssignedNotice: Identifiable {
    let id: SourceID
    let text: String
}

/// 「지정 단축키」 상자(D-46). fn 상자와 「사용 안 함」 상자 사이에 둔다.
/// 「사용 안 함」과 같은 줄 상자 모양이고, 타일마다 아래에 단축키 칸이 있다.
/// 상자 전체가 끌기 영역 `.assigned`다(04-22).
struct AssignedShortcutsBox: View {
    let rows: [SourceRow]
    let slotIDs: [SourceID?]
    var highlighted = false
    var countWarning = false
    let currentID: SourceID?
    let newIDs: Set<SourceID>
    @ObservedObject var keys: KeysPageState
    @ObservedObject var ui: SettingsUIState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var placeholderID: SourceID?
    let chordText: [SourceID: String]
    let conflictIDs: Set<SourceID>
    let typingIDs: Set<SourceID>
    let onChordTap: (SourceID) -> Void
    let tileContent: (SourceRow) -> AnyView

    init(rows: [SourceRow], slotIDs: [SourceID?]? = nil, highlighted: Bool = false,
         countWarning: Bool = false, currentID: SourceID?, newIDs: Set<SourceID>,
         keys: KeysPageState, ui: SettingsUIState, placeholderID: SourceID? = nil,
         chordText: [SourceID: String], conflictIDs: Set<SourceID> = [],
         typingIDs: Set<SourceID> = [], onChordTap: @escaping (SourceID) -> Void,
         tileContent: @escaping (SourceRow) -> AnyView) {
        self.rows = rows
        self.slotIDs = slotIDs ?? rows.map(\.id)
        self.highlighted = highlighted
        self.countWarning = countWarning
        self.currentID = currentID
        self.newIDs = newIDs
        self.keys = keys
        self.ui = ui
        self.placeholderID = placeholderID
        self.chordText = chordText
        self.conflictIDs = conflictIDs
        self.typingIDs = typingIDs
        self.onChordTap = onChordTap
        self.tileContent = tileContent
    }

    private static let tileHeight = CGFloat(RingGeometry.tileHeight)
    private static let tileWidth = CGFloat(RingGeometry.tileWidth)
    /// 단축키 칸 한 줄 높이. 알약 테두리가 들어가도 타일 줄과 겹치지 않게 둔다.
    private static let chordLineHeight: CGFloat = DS.s(18)

    /// 본문 최소 높이(W7). 이 상자에서 끄는 동안만 둔다. 마지막 타일을 끌어 내도 상자가 줄지 않는다.
    /// 끌지 않을 때 빈 상자는 「사용 안 함」처럼 얇다(2026-11-11 사용자 요청).
    private var minBodyHeight: CGFloat? {
        keys.drag?.origin == .assigned ? Self.tileHeight + DS.s(4) + Self.chordLineHeight : nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.s(10)) {
            HStack(alignment: .firstTextBaseline, spacing: DS.s(8)) {
                Text(verbatim: L("keys.assigned.title"))
                    .font(DS.bodyEmphasis)
                    .lineLimit(1)
                    .layoutPriority(1)
                // 「사용 안 함」 상자와 같이 설명은 ⓘ 안에 둔다(04.1 UAT S4).
                InfoButton(id: "keys.assigned", text: L("keys.assigned.caption"), title: L("keys.assigned.title"), ui: ui)
                    .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + DS.s(4) }
                Spacer(minLength: DS.s(8))
                Text(verbatim: LF("keys.count", rows.count, KeyLists.maxPerKey))
                    .font(DS.caption.monospacedDigit())
                    .foregroundStyle(countWarning ? AnyShapeStyle(Color.red) : AnyShapeStyle(.tertiary))
                    .layoutPriority(1)
                    .accessibilityHidden(true)
            }
            .zIndex(0)

            VStack(alignment: .center, spacing: DS.s(6)) {
                if slotIDs.isEmpty {
                    // 「사용 안 함」과 같은 빈 모양: 가운데 「없음」, 끌지 않을 때는 얇게.
                    Text(verbatim: L("keys.assigned.none"))
                        .font(DS.caption)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity)
                        .frame(height: keys.drag != nil ? Self.tileHeight : nil)
                } else {
                    FlowLayout(spacing: DS.s(10), centered: true) {
                        ForEach(slotKeys, id: \.key) { i, _ in
                            slot(index: i)
                                .zIndex(keys.isHovered(slotIDs[i], in: .assigned) ? 1 : 0)
                        }
                    }
                    .zIndex(1)
                }
                noticeLine
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: minBodyHeight, alignment: .top)
        }
        .padding(.horizontal, DS.s(16))
        .padding(.vertical, DS.s(12))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: DS.boxCornerRadius, style: .continuous)
            .fill(highlighted ? DS.dropHighlight : Color.clear))
        .background(RoundedRectangle(cornerRadius: DS.boxCornerRadius, style: .continuous).fill(DS.boxFill))
        .background(GeometryReader { geo in
            Color.clear.preference(key: KeyZoneFrameKey.self, value: [.assigned: geo.frame(in: .named("keys"))])
        })
    }

    /// 빈 칸은 목록마다 많아야 하나라(DragSession.slots) 고정 키로 둔다(04-17 방식).
    private var slotKeys: [(index: Int, key: String)] {
        slotIDs.enumerated().map { ($0.offset, $0.element ?? "__gap") }
    }

    @ViewBuilder
    private func slot(index i: Int) -> some View {
        if let id = slotIDs[i], let row = rows.first(where: { $0.id == id }) {
            VStack(spacing: DS.s(4)) {
                tileContent(row)
                chordCell(id)
            }
            .id(id)
        } else if placeholderID != nil {
            VStack(spacing: DS.s(4)) {
                SourceTile(row: nil, style: .placeholder)
                Color.clear.frame(height: Self.chordLineHeight)
            }
            .id(placeholderID)
        } else {
            VStack(spacing: DS.s(4)) {
                Color.clear.frame(width: Self.tileWidth, height: Self.tileHeight)
                Color.clear.frame(height: Self.chordLineHeight)
            }
        }
    }

    /// 타일 아래 단축키 칸. 누르면 그 소스를 다시 녹화한다.
    /// 조합이 있으면 글자, 없으면 「단축키 없음」, 녹화 중이면 알약 안에 누르는 수정 키를 보인다.
    private func chordCell(_ id: SourceID) -> some View {
        let recording = keys.recordingID == id
        return Button {
            onChordTap(id)
        } label: {
            HStack(spacing: DS.s(3)) {
                if recording {
                    Text(verbatim: ChordFormatter.modifierText(keys.recordingModifiers))
                        .foregroundStyle(keys.recordingModifiers == 0
                                         ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.primary))
                    if keys.recordingModifiers == 0 {
                        Text(verbatim: L("keys.assigned.recording"))
                            .foregroundStyle(.secondary)
                    }
                } else if let text = chordText[id] {
                    Text(verbatim: text)
                        .foregroundStyle(Color.primary)
                    if conflictIDs.contains(id) {
                        // 주황 점은 겹침을 알리는 표시다. 뜻은 아래 알림 줄이 설명한다.
                        Circle().fill(DS.warn).frame(width: DS.s(6), height: DS.s(6))
                    }
                } else {
                    Text(verbatim: L("keys.assigned.noShortcut"))
                        .foregroundStyle(.tertiary)
                }
            }
            .font(DS.caption)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, recording ? DS.s(10) : 0)
            .padding(.vertical, recording ? DS.s(2) : 0)
            .background {
                if recording {
                    Capsule().strokeBorder(DS.ok, lineWidth: DS.s(1.2))
                }
            }
            .frame(minHeight: Self.chordLineHeight)
            .background {
                if ui.keysChordHighlight.contains(id) {
                    RoundedRectangle(cornerRadius: DS.s(4)).fill(DS.dropHighlight)
                }
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: ui.keysChordHighlight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: accessibilityValue(id, recording: recording)))
    }

    private func accessibilityValue(_ id: SourceID, recording: Bool) -> String {
        if recording { return L("keys.assigned.recording") }
        if let text = chordText[id] { return LF("keys.assigned.value", text) }
        return L("keys.assigned.noShortcut")
    }

    /// 상자 안 맨 아래 알림 줄. 거절 문구 > 빼앗기 알림 > 겹침·입력 막힘 순서로 하나만 둔다.
    /// 겹침과 입력 막힘은 함께 있을 수 있어 두 줄이 된다.
    @ViewBuilder
    private var noticeLine: some View {
        if let message = keys.recordingMessage {
            notice(message, color: AnyShapeStyle(DS.warn))
        } else if let last = keys.lastNotice {
            notice(last, color: AnyShapeStyle(.secondary))
        } else if !conflictNotices.isEmpty || !typingNotices.isEmpty {
            VStack(alignment: .leading, spacing: DS.s(2)) {
                ForEach(conflictNotices) { notice($0.text, color: AnyShapeStyle(DS.warn)) }
                ForEach(typingNotices) { notice($0.text, color: AnyShapeStyle(DS.warn)) }
            }
        }
    }

    private var conflictNotices: [AssignedNotice] {
        rows.filter { conflictIDs.contains($0.id) }
            .map { AssignedNotice(id: $0.id, text: LF("keys.assigned.conflict", $0.name)) }
    }

    private var typingNotices: [AssignedNotice] {
        rows.compactMap { row -> AssignedNotice? in
            guard typingIDs.contains(row.id), let text = chordText[row.id] else { return nil }
            return AssignedNotice(id: row.id, text: LF("keys.assigned.typing", text))
        }
    }

    private func notice(_ text: String, color: AnyShapeStyle) -> some View {
        Text(verbatim: text)
            .font(DS.caption)
            .foregroundStyle(color)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .fixedSize(horizontal: false, vertical: true)
    }
}
