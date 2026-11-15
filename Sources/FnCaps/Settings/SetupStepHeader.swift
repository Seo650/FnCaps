import SwiftUI

/// 단계 머리 부품(UI-SPEC §5, G-6·G-7): 제목 + 보조 한 줄. 다섯 단계(환영 제외)가 이 하나를 쓴다.
/// 「정보」 쪽 머리(제목 + caption secondary)와 같은 구조라 새 토큰이 아니다.
struct SetupStepHeader: View {
    /// 제목. 🌐가 들어가는 단계는 `GlobeText.make`의 Text를 그대로 넘긴다.
    let title: Text
    /// 보조 한 줄. 없으면 제목만 그린다.
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: DS.s(8)) {
            title
                .font(DS.pageTitle)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if let subtitle {
                Text(verbatim: subtitle)
                    .font(DS.caption)
                    .foregroundStyle(.secondary)
                    .lineSpacing(DS.s(2))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
