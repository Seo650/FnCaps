import FnCapsCore
import SwiftUI

/// 도움말 「설정하기」의 보기 전용 축소판(D-47). 「키와 언어」 쪽 그림을 새로 그리지 않고
/// `KeyRingBox`·`SourceTile`·`Keycap`을 그대로 줄여 쓴다. 끌기·우클릭 메뉴·hover는 없다.
/// (화면 상태는 SDK 27 빌드 제약으로 `SettingsUIState`에 둔다)
enum HelpMiniature {
    /// 축소판 배율. 보기 전용이라 손잡이·「n/6」은 그리지 않는다(2026-11-13).
    static let scale: CGFloat = 0.8
    /// 축소 전 원래 폭. 「키와 언어」 상자 폭에 맞춘다.
    static let naturalWidth: CGFloat = DS.s(400)
}

/// 자식을 원래 폭으로 배치하고 보이는 크기만 `scale`배로 줄이는 배치.
/// 원래 상자의 배치 규칙(고리 반지름, 타일 크기)이 그대로 남는다.
struct ScaledBox: Layout {
    let scale: CGFloat
    let naturalWidth: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let first = subviews.first else { return .zero }
        let natural = first.sizeThatFits(ProposedViewSize(width: naturalWidth, height: nil))
        return CGSize(width: naturalWidth * scale, height: natural.height * scale)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let first = subviews.first else { return }
        first.place(at: bounds.origin, anchor: .topLeading,
                    proposal: ProposedViewSize(width: naturalWidth, height: nil))
    }
}

/// 축소한 상자 하나 + 오른쪽 말 칸. 접근성에서는 한 줄이 한 문장이 된다.
struct MiniRow<Box: View>: View {
    var caption: String?
    /// 말 아래 흐린 한 줄(04.4 UAT U-3: Caps가 macOS 기본과 다를 때 macOS 동작).
    var note: String?
    let label: String
    let box: Box

    init(caption: String? = nil, note: String? = nil, label: String,
         @ViewBuilder box: () -> Box) {
        self.caption = caption
        self.note = note
        self.label = label
        self.box = box()
    }

    var body: some View {
        HStack(alignment: .center, spacing: DS.s(12)) {
            ScaledBox(scale: HelpMiniature.scale, naturalWidth: HelpMiniature.naturalWidth) {
                box
                    .frame(width: HelpMiniature.naturalWidth, alignment: .leading)
                    .scaleEffect(HelpMiniature.scale, anchor: .topLeading)
            }
            .allowsHitTesting(false)
            words
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: label))
    }

    @ViewBuilder
    private var words: some View {
        if let caption {
            VStack(alignment: .leading, spacing: DS.s(4)) {
                GlobeText.make(caption, size: DS.s(11))
                    .font(DS.caption)
                    .lineSpacing(DS.s(2))
                    .fixedSize(horizontal: false, vertical: true)
                if let note {
                    Text(verbatim: note)
                        .font(DS.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Spacer(minLength: 0)
        }
    }
}

/// Caps·fn·지정 상자를 위에서 아래로 놓는 축소판. 빈 목록은 줄을 그리지 않는다.
struct KeysMiniature: View {
    @ObservedObject var ui: SettingsUIState
    var caps: [SourceRow] = []
    var fn: [SourceRow] = []
    var assigned: [SourceRow] = []
    var capsCaption: String?
    /// Caps 말 아래 흐린 줄(04.4 UAT U-3).
    var capsNote: String? = nil
    var fnCaption: String?
    var assignedCaption: String?
    var showsCount = false
    var showsArrows = true
    /// 진입 화살표를 그릴 타일(04.4 UI-SPEC C-10). 목록이 2개 이상일 때만 `KeyRingBox`가 그린다.
    /// 푸터 진입 언어 컨트롤(`showsEntryControl`)은 축소판에서 켜지 않는다.
    var capsEntryID: SourceID? = nil
    var fnEntryID: SourceID? = nil
    /// Caps 상자를 다른 모양(macOS 기본 그림의 Caps Lock)으로 바꿀 때.
    var customCapsBox: AnyView?

    var body: some View {
        VStack(alignment: .leading, spacing: DS.s(8)) {
            if !caps.isEmpty {
                MiniRow(caption: capsCaption, note: capsNote,
                        label: Self.label("Caps Lock", caps,
                                          [capsCaption, capsNote].compactMap { $0 }
                                              .joined(separator: ". "))) {
                    if let customCapsBox {
                        customCapsBox
                    } else {
                        ring(.caps, caps, entryID: capsEntryID)
                    }
                }
            }
            if !fn.isEmpty {
                MiniRow(caption: fnCaption,
                        label: Self.label("fn", fn, fnCaption)) {
                    ring(.fn, fn, entryID: fnEntryID)
                }
            }
            if !assigned.isEmpty {
                MiniRow(caption: assignedCaption,
                        label: Self.label(L("keys.assigned.title"), assigned, assignedCaption)) {
                    MiniAssignedBox(rows: assigned)
                }
            }
        }
    }

    private func ring(_ list: SourceList, _ rows: [SourceRow], entryID: SourceID?) -> some View {
        KeyRingBox(list: list, rows: rows, currentID: nil, newIDs: [], keys: ui.helpMiniKeys,
                   showsCount: showsCount, showsArrows: showsArrows,
                   singleKey: list == .fn ? "help.mini.fnSingle" : "keys.single",
                   entryID: entryID) {
            AnyView(SourceTile(row: $0, style: .normal, showsGrip: false))
        }
    }

    /// 「키 이름: 소스 이름들. 말」 한 문장(D-47 접근성).
    private static func label(_ key: String, _ rows: [SourceRow], _ caption: String?) -> String {
        var text = "\(key): \(rows.map(\.name).joined(separator: ", "))"
        if let caption { text += ". \(caption)" }
        return text
    }
}

/// 「지정 단축키」 상자의 축소판(D-46 모양). 바탕·모서리·안쪽 여백·제목만 두고
/// 단축키 칸·ⓘ·녹화 버튼은 없다(보기 전용).
struct MiniAssignedBox: View {
    let rows: [SourceRow]

    var body: some View {
        VStack(alignment: .leading, spacing: DS.s(10)) {
            Text(verbatim: L("keys.assigned.title"))
                .font(DS.bodyEmphasis)
                .lineLimit(1)
            FlowLayout(spacing: DS.s(10), centered: true) {
                ForEach(rows, id: \.id) { row in
                    SourceTile(row: row, style: .normal, showsGrip: false)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, DS.s(16))
        .padding(.vertical, DS.s(12))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: DS.boxCornerRadius, style: .continuous)
            .fill(DS.boxFill))
    }
}

/// macOS 기본 Caps Lock 상자(D-48): A ↔ 직전 언어. 켰을 때의 동작만 보인다.
struct MacCapsMiniBox: View {
    let english: SourceRow

    var body: some View {
        KeyZoneBox {
            Keycap(kind: .caps)
        } content: {
            HStack(spacing: DS.s(8)) {
                SourceTile(row: english, style: .normal, showsGrip: false)
                Image(systemName: "arrow.left.arrow.right")
                    .font(DS.label.weight(.bold))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                VStack(spacing: DS.s(4)) {
                    SourceTile(row: nil, style: .placeholder)
                    Text(verbatim: L("help.setup.macos.previous"))
                        .font(DS.label)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, DS.s(12))
        }
    }
}
