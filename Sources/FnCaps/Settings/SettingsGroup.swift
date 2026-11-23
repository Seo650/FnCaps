import SwiftUI

/// 작은 묶음 제목 + 테두리 없는 상자(D-37, D-39). 행 사이에는 호출자가 SettingsDivider를 넣는다.
struct SettingsGroup<Content: View>: View {
    let title: String?
    let description: String?
    let content: Content

    init(title: String?, description: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.description = description
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.groupTitleGap) {
            if let title {
                Text(verbatim: title)
                    .font(DS.groupTitle)
                    .foregroundStyle(.secondary)
                    .padding(.leading, DS.s(4))
            }
            if let description {
                Text(verbatim: description)
                    .font(DS.caption)
                    .foregroundStyle(.secondary)
                    .lineSpacing(DS.s(2))
                    .padding(.leading, DS.s(4))
                    .fixedSize(horizontal: false, vertical: true)
            }
            SettingsBox { content }
        }
    }
}

/// 상자 안 행 사이 선. 왼쪽을 inset만큼, 오른쪽을 trailing(기본 DS.rowInset)만큼 띄워 행 글자와 같은 자리에서 끝낸다
/// (04.5 UAT F-4, G-08.1-11, 2026-11-23 사용자: 상자 안 모든 선). 오른쪽 여백을 부르는 곳마다 따로 붙이지 않는다.
struct SettingsDivider: View {
    var inset: CGFloat = DS.rowInset
    var trailing: CGFloat = DS.rowInset

    var body: some View {
        Divider().padding(.leading, inset).padding(.trailing, trailing)
    }
}
