import SwiftUI

/// 「제목 + ⓘ + 오른쪽 컨트롤」 한 행. vertical이면 컨트롤이 제목 아래 전체 폭.
struct SettingRow<Control: View>: View {
    let title: String
    let info: (id: String, text: String)?
    let caption: String?
    let vertical: Bool
    @ObservedObject var ui: SettingsUIState
    let control: Control

    init(title: String,
         info: (id: String, text: String)? = nil,
         caption: String? = nil,
         vertical: Bool = false,
         ui: SettingsUIState,
         @ViewBuilder control: () -> Control) {
        assert(info == nil || caption == nil, "D-35: 한 행에는 줄 설명과 ⓘ 중 하나만")
        self.title = title
        self.info = info
        self.caption = caption
        self.vertical = vertical
        self.ui = ui
        self.control = control()
    }

    private var titleView: some View {
        HStack(spacing: DS.s(6)) {
            Text(verbatim: title)
                .font(DS.rowTitle)
                .lineSpacing(DS.s(2))
                .fixedSize(horizontal: false, vertical: true)
            if let info {
                InfoButton(id: info.id, text: info.text, title: title, ui: ui)
            }
        }
    }

    @ViewBuilder
    private var captionView: some View {
        if let caption {
            Text(verbatim: caption)
                .font(DS.caption)
                .foregroundStyle(.secondary)
                .lineSpacing(DS.s(2))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    var body: some View {
        Group {
            if vertical {
                VStack(alignment: .leading, spacing: DS.s(2)) {
                    titleView
                    captionView
                    control
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, DS.s(8))
                }
            } else {
                // 확정 초안: 설명은 제목 아래 왼쪽 칸에만, 컨트롤은 그 칸의 세로 가운데.
                HStack(alignment: .center, spacing: DS.s(12)) {
                    VStack(alignment: .leading, spacing: DS.s(2)) {
                        titleView
                        captionView
                    }
                    Spacer(minLength: DS.s(8))
                    control
                }
            }
        }
        .padding(.horizontal, DS.rowInset)
        .padding(.vertical, DS.s(10))
        // 최소 높이만 둔다. 시스템 컨트롤 높이는 고정하지 않는다(PA14).
        .frame(maxWidth: .infinity, minHeight: DS.rowMinHeight, alignment: .leading)
    }
}
