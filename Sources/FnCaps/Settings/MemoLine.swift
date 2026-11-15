import AppKit
import SwiftUI

/// 창 맨 아래 메모 줄(D-33, D-35). 모든 쪽에서 같은 자리다.
/// 글자는 저장하지 않는다(M7). 창을 닫으면 창 컨트롤러가 비운다.
struct MemoLine: View {
    @ObservedObject var ui: SettingsUIState

    var body: some View {
        HStack(spacing: DS.s(8)) {
            Image(systemName: "keyboard")
                .font(DS.caption)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField(
                L("memo.placeholder"),
                text: Binding(get: { ui.memoText }, set: { ui.memoText = $0 }))
                .textFieldStyle(.plain)
                .font(DS.value)
                .accessibilityLabel(L("memo.placeholder"))
        }
        .padding(.horizontal, DS.s(10))
        .frame(height: DS.s(30))
        .background(
            RoundedRectangle(cornerRadius: DS.s(8), style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(
            RoundedRectangle(cornerRadius: DS.s(8), style: .continuous)
                .strokeBorder(Color.primary.opacity(0.15)))
        .padding(.horizontal, DS.s(16))
        .frame(maxWidth: .infinity)
        .frame(height: DS.s(48))
        .background(Color(nsColor: .underPageBackgroundColor))
        .overlay(alignment: .top) { Divider() }
    }
}
