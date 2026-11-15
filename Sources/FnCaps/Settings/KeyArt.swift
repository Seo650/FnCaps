import SwiftUI

/// 실제 키 모양 그림(caps lock, fn). 각인 글자는 실제 키에 새겨진 글자라 번역하지 않는다.
struct Keycap: View {
    enum Kind { case caps, fn }

    let kind: Kind
    var scale: CGFloat = 1
    var dimmed = false
    @Environment(\.colorScheme) private var scheme

    private var width: CGFloat {
        switch kind {
        case .caps: return 1.95 * DS.keyUnit
        case .fn: return 1.25 * DS.keyUnit
        }
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: DS.s(9) * scale, style: .continuous)
                .fill(DS.keycapFill)
                .overlay(RoundedRectangle(cornerRadius: DS.s(9) * scale, style: .continuous)
                    .strokeBorder(Color.white.opacity(scheme == .dark ? 0.10 : 0)))
                .shadow(color: .black.opacity(0.30), radius: DS.s(1.5), y: DS.s(1.5))
            if kind == .caps {
                // Caps Lock 표시등은 꺼진 회색으로 둔다(D-29).
                Circle()
                    .fill(Color.white.opacity(0.14))
                    .frame(width: DS.s(5) * scale, height: DS.s(5) * scale)
                    .padding(.top, DS.s(7) * scale)
                    .padding(.leading, DS.s(8) * scale)
            }
            VStack {
                Spacer(minLength: 0)
                HStack(spacing: DS.s(4) * scale) {
                    if kind == .fn {
                        Image(systemName: "globe")
                            .font(.system(size: DS.labelSize * scale, weight: .medium))
                    }
                    Text(verbatim: kind == .caps ? "caps lock" : "fn")
                        .font(.system(size: DS.captionSize * scale, weight: .medium))
                }
            }
            .padding(.leading, DS.s(8) * scale)
            .padding(.bottom, DS.s(7) * scale)
        }
        .foregroundStyle(Color.white.opacity(0.92))
        .frame(width: width * scale, height: DS.keyUnit * 1.25 * scale)
        .opacity(dimmed ? 0.45 : 1)
        .accessibilityHidden(true)
    }
}

/// 키 칸 바탕: 라이트는 옅은 회색 단색, 다크는 위에서 아래로 어두워지는 회색.
struct KeyZoneFill: View {
    var body: some View {
        LinearGradient(colors: [DS.keyZoneTop, DS.keyZoneBottom], startPoint: .top, endPoint: .bottom)
    }
}

/// 왼쪽 키 칸 + 오른쪽 내용 상자. 키 칸 폭은 네 쪽 모두 같다(D-39), 테두리 없음(D-37).
struct KeyZoneBox<Key: View, Content: View>: View {
    var keyAlignment: Alignment = .center
    let key: Key
    let content: Content

    init(keyAlignment: Alignment = .center,
         @ViewBuilder key: () -> Key,
         @ViewBuilder content: () -> Content) {
        self.keyAlignment = keyAlignment
        self.key = key()
        self.content = content()
    }

    var body: some View {
        HStack(spacing: 0) {
            ZStack(alignment: keyAlignment) {
                KeyZoneFill()
                key
            }
            .frame(width: DS.keyZoneWidth)
            VStack(spacing: 0) { content }
                .frame(maxWidth: .infinity, minHeight: DS.keyUnit * 1.25 + DS.s(32))
        }
        .fixedSize(horizontal: false, vertical: true)
        .background(DS.boxFill)
        .clipShape(RoundedRectangle(cornerRadius: DS.boxCornerRadius, style: .continuous))
    }
}
