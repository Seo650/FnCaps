import SwiftUI

/// ⓘ 버튼. 올리면 말풍선, 누르면 popover(한 번에 하나만).
/// 표시 상태는 `isPresented` 하나로 모은다. 기존 `init(id:text:title:ui:)`는 `ui.infoBinding(id)`를 넘긴다.
struct InfoButton: View {
    /// 팝오버 항목 한 덩어리: 굵은 이름과 그 설명.
    struct Item {
        let name: String
        let text: String
    }

    private let title: String
    private let text: String
    private let items: [Item]
    private let footnote: String?
    private let isPresented: Binding<Bool>

    /// 설명 글 하나만 보이는 기존 변형. 호출처는 그대로다.
    init(id: String, text: String, title: String, ui: SettingsUIState) {
        self.title = title
        self.text = text
        self.items = []
        self.footnote = nil
        self.isPresented = ui.infoBinding(id)
    }

    /// 항목 이름·설명과 아래 예시를 보이는 변형(04.4 D-22). 표시 상태는 부르는 쪽이 갖는다.
    init(title: String, items: [Item], footnote: String?, isPresented: Binding<Bool>) {
        self.title = title
        self.text = ""
        self.items = items
        self.footnote = footnote
        self.isPresented = isPresented
    }

    /// 말풍선·접근성 힌트에 쓸 글. 항목은 「이름: 설명」을 줄바꿈으로 잇는다.
    private var hint: String {
        if items.isEmpty { return text }
        var lines = items.map { "\($0.name): \($0.text)" }
        if let footnote { lines.append(footnote) }
        return lines.joined(separator: "\n")
    }

    var body: some View {
        Button {
            isPresented.wrappedValue.toggle()
        } label: {
            // 설명 옆 ⓘ는 10(04.1 UAT S7~S9, 사용자 요청).
            Image(systemName: "info.circle")
                .font(.system(size: DS.s(10)))
                .foregroundStyle(.secondary)
                .frame(width: DS.s(20), height: DS.s(20))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // 누르는 자리(20)는 두고 왼쪽 빈 자리만 겹치게 해 제목과 ⓘ 사이를 반으로 줄인다(04.1 UAT S11).
        .padding(.leading, -DS.s(5))
        .help(hint)
        .popover(isPresented: isPresented) {
            popoverContent
        }
        .accessibilityLabel(LF("info.label", title))
        .accessibilityHint(hint)
    }

    /// popover는 내용의 이상적 크기로 창을 잡는다. maxWidth만 주면 한 줄 높이로 잡혀 「…」로 잘린다.
    /// 폭을 고정하고 세로는 글 길이만큼 늘린다.
    @ViewBuilder
    private var popoverContent: some View {
        if items.isEmpty {
            Text(verbatim: text)
                .font(DS.value)
                .lineSpacing(DS.s(2))
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: DS.s(280), alignment: .leading)
                .padding(DS.s(16))
        } else {
            VStack(alignment: .leading, spacing: DS.s(8)) {
                ForEach(items.indices, id: \.self) { index in
                    VStack(alignment: .leading, spacing: DS.s(2)) {
                        Text(verbatim: items[index].name)
                            .font(DS.bodyEmphasis)
                        Text(verbatim: items[index].text)
                            .font(DS.value)
                            .lineSpacing(DS.s(2))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if let footnote {
                    Text(verbatim: footnote)
                        .font(DS.caption)
                        .foregroundStyle(.secondary)
                        .lineSpacing(DS.s(2))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(width: DS.s(280), alignment: .leading)
            .padding(DS.s(16))
        }
    }
}
