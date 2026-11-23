// 구조 참고: Sparkle SUUpdateAlert (MIT)
import AppKit
import SwiftUI

/// 단계 머리 B(08.1 사용자 선택 2026-11-22, UI-SPEC O-1): 앱 아이콘 + 제목 + 보조 한 줄.
/// 출처: Sparkle `SUUpdateAlert`, 중요 업데이트 창 `ImportantUpdateView`(AltTab·Ice는 아이디어만).
/// 다섯 단계(환영 제외)가 이 하나를 쓴다. 아이콘은 제목이 이름을 말하므로 접근성에서 숨긴다.
/// 업데이트 창 머리는 줄이 둘이라 `.top`이지만 단계마다 보조 글 유무가 달라 `.center`로 통일한다.
struct SetupStepHeader: View {
    /// 제목. 🌐가 들어가는 단계는 `GlobeText.make`의 Text를 그대로 넘긴다.
    let title: Text
    /// 보조 한 줄. 없으면 제목만 그린다.
    var subtitle: String? = nil

    var body: some View {
        HStack(alignment: .center, spacing: DS.s(16)) {
            appIcon(DS.s(56))
            VStack(alignment: .leading, spacing: DS.s(4)) {
                title
                    .font(DS.statusTitle)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                if let subtitle {
                    Text(verbatim: subtitle)
                        .font(DS.value)
                        .foregroundStyle(.secondary)
                        .lineSpacing(DS.s(4))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func appIcon(_ side: CGFloat) -> some View {
        Image(nsImage: NSApp.applicationIconImage)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: side, height: side)
            .accessibilityHidden(true)
    }
}
