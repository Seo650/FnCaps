import AppKit
import FnCapsCore
import SwiftUI

/// 설정창 재설계 디자인 토큰(REDESIGN-SPEC §6, D-39). 모든 쪽이 이 값만 쓴다.
/// 글자는 다섯 단계뿐이다. 이 밖의 크기는 키캡·타일 기호만 쓴다.
enum DS {
    // MARK: 배율
    /// 설정창 전체 배율. 원본은 RingGeometry.scale 하나다(quick 261110-jnz).
    static let scale: CGFloat = CGFloat(RingGeometry.scale)
    /// 원래 치수 v에 배율을 곱한다(반올림 없음).
    static func s(_ v: CGFloat) -> CGFloat { v * scale }

    // MARK: 글자
    static let pageTitle = Font.system(size: s(20), weight: .semibold)
    static let statusTitle = Font.system(size: s(15), weight: .semibold)
    static let rowTitle = Font.system(size: s(13))
    /// 값, 버튼, 팝업 글자.
    static let value = Font.system(size: s(13))
    static let caption = Font.system(size: s(11))
    /// 묶음 제목. 색은 secondary로 쓴다.
    static let groupTitle = Font.system(size: s(11), weight: .semibold)
    /// 강조 본문(버튼, 강조 행).
    static let bodyEmphasis = Font.system(size: s(13), weight: .medium)
    /// 작은 라벨(설정 팁의 점·배지·보조 글자). 7·8·10pt를 이 하나로 통일.
    static let label = Font.system(size: s(10))
    /// 그림 요소(KeyArt)에서 scale을 곱해 쓰는 글자 크기.
    static let captionSize: CGFloat = s(11)
    static let labelSize: CGFloat = s(10)

    // MARK: 컨트롤
    // 네이티브 Picker(.menu)는 .font를 받지 않고 시스템 크기(13pt, 칸 높이 24pt 실측)로 그려진다.
    // 버튼·스위치·값 글자를 거기에 맞추는 값이라 배율 s()를 곱하지 않는다(quick 261110-knh).
    static let controlFontSize: CGFloat = 13
    static let controlFont = Font.system(size: controlFontSize)
    static let controlFontEmphasis = Font.system(size: controlFontSize, weight: .medium)
    static let controlHeight: CGFloat = 24
    static let controlCornerRadius: CGFloat = 6
    /// 스위치 배율. 기본 스위치(프레임 54x24pt)에 곱한다.
    static let switchScale: CGFloat = 0.80

    // MARK: 간격
    static let groupSpacing: CGFloat = s(16)
    static let groupTitleGap: CGFloat = s(6)
    static let rowInset: CGFloat = s(16)
    /// 행 최소 높이. 시스템 컨트롤 높이는 고정하지 않는다(PA14: macOS 26에서 커진다).
    static let rowMinHeight: CGFloat = s(46)
    static let pageInsetH: CGFloat = s(20)
    static let pageInsetTop: CGFloat = s(22)
    static let boxCornerRadius: CGFloat = s(14)

    // MARK: 키 그림 치수
    /// 키캡 한 칸 단위.
    static let keyUnit: CGFloat = s(34)
    /// 왼쪽 키 칸 폭. 네 쪽 모두 같다(D-39).
    static let keyZoneWidth: CGFloat = 1.95 * keyUnit + s(28)

    // MARK: 색 (PA15: 라이트·다크·대비 증가 라이트·대비 증가 다크 네 값)
    /// 정상·켜짐·현재 언어 점·스위치.
    static let ok = dynamic(
        light: rgb(0.30, 0.80, 0.42), dark: rgb(0.30, 0.80, 0.42),
        highContrastLight: rgb(0.13, 0.55, 0.25), highContrastDark: rgb(0.42, 0.90, 0.54))
    /// 경고·권한 필요·새 소스 점.
    static let warn = dynamic(
        light: rgb(0.96, 0.58, 0.16), dark: rgb(0.96, 0.58, 0.16),
        highContrastLight: rgb(0.76, 0.38, 0.02), highContrastDark: rgb(1.00, 0.70, 0.32))
    /// 키 칸 바탕 위쪽(라이트는 단색이라 위아래 같다).
    static let keyZoneTop = dynamic(
        light: rgb(0.885, 0.885, 0.895), dark: NSColor(white: 0.26, alpha: 1),
        highContrastLight: rgb(0.80, 0.80, 0.81), highContrastDark: NSColor(white: 0.34, alpha: 1))
    /// 키 칸 바탕 아래쪽.
    static let keyZoneBottom = dynamic(
        light: rgb(0.885, 0.885, 0.895), dark: NSColor(white: 0.21, alpha: 1),
        highContrastLight: rgb(0.80, 0.80, 0.81), highContrastDark: NSColor(white: 0.29, alpha: 1))
    /// 키캡 바탕. 라이트의 강조 버튼 바탕도 이 색이다.
    static let keycapFill = dynamic(
        light: rgb(0.11, 0.11, 0.12), dark: rgb(0.11, 0.11, 0.12),
        highContrastLight: rgb(0.05, 0.05, 0.06), highContrastDark: rgb(0.05, 0.05, 0.06))
    /// 테두리 없는 상자 바탕: primary 3.5%(라이트) / 5%(다크), 대비 증가는 8%.
    static let boxFill = dynamic(
        light: NSColor(white: 0, alpha: 0.035), dark: NSColor(white: 1, alpha: 0.05),
        highContrastLight: NSColor(white: 0, alpha: 0.08), highContrastDark: NSColor(white: 1, alpha: 0.08))

    /// 끄는 타일이 올라간 상자 바탕에 더하는 양(재설계 §4 「6%→10%」의 4%p 차이). 상자 바탕 위에 겹친다.
    /// 10%를 그대로 겹치면 3.5% 바탕과 합쳐 키 칸과 같은 회색이 되어 상자 구분이 사라진다(04-17 렌더 확인).
    static let dropHighlight = Color.primary.opacity(0.04)

    private static func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> NSColor {
        NSColor(srgbRed: r, green: g, blue: b, alpha: 1)
    }

    private static func dynamic(light: NSColor, dark: NSColor,
                                highContrastLight: NSColor, highContrastDark: NSColor) -> Color {
        let color = NSColor(name: nil) { appearance in
            switch appearance.bestMatch(from: [.aqua, .darkAqua,
                                               .accessibilityHighContrastAqua,
                                               .accessibilityHighContrastDarkAqua]) {
            case .darkAqua?: return dark
            case .accessibilityHighContrastAqua?: return highContrastLight
            case .accessibilityHighContrastDarkAqua?: return highContrastDark
            default: return light
            }
        }
        return Color(nsColor: color)
    }
}

/// 테두리 없는 상자(네 쪽 공통, D-37). 모서리 14 continuous.
struct SettingsBox<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DS.boxFill)
            .clipShape(RoundedRectangle(cornerRadius: DS.boxCornerRadius, style: .continuous))
    }
}

/// 강조 버튼: 라이트는 검정 바탕 흰 글자, 다크는 흰 바탕 검정 글자. 파란 강조 없음(D-39).
struct ProminentButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        ProminentButtonBody(label: configuration.label, pressed: configuration.isPressed)
    }
}

private struct ProminentButtonBody<Label: View>: View {
    let label: Label
    let pressed: Bool
    @Environment(\.colorScheme) private var scheme
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        let dark = scheme == .dark
        label
            .font(DS.controlFontEmphasis)
            .foregroundStyle(dark ? Color.black : Color.white)
            .padding(.horizontal, 10)
            .frame(minHeight: DS.controlHeight)
            .background(RoundedRectangle(cornerRadius: DS.controlCornerRadius, style: .continuous)
                .fill(dark ? Color.white : DS.keycapFill))
            .contentShape(RoundedRectangle(cornerRadius: DS.controlCornerRadius, style: .continuous))
            .opacity(isEnabled ? (pressed ? 0.8 : 1) : 0.4)
    }
}

/// 보통 버튼: 컨트롤 바탕 + 옅은 테두리.
struct PillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        PillButtonBody(label: configuration.label, pressed: configuration.isPressed)
    }
}

private struct PillButtonBody<Label: View>: View {
    let label: Label
    let pressed: Bool
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        label
            .font(DS.controlFontEmphasis)
            .foregroundStyle(Color.primary)
            .padding(.horizontal, 10)
            .frame(minHeight: DS.controlHeight)
            .background(RoundedRectangle(cornerRadius: DS.controlCornerRadius, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: DS.controlCornerRadius, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.18)))
            .contentShape(RoundedRectangle(cornerRadius: DS.controlCornerRadius, style: .continuous))
            .opacity(isEnabled ? (pressed ? 0.8 : 1) : 0.4)
    }
}

/// 상태 점(초록 정상, 주황 경고 등).
struct StatusDot: View {
    let color: Color
    var size: CGFloat = DS.s(8)

    var body: some View {
        Circle().fill(color).frame(width: size, height: size)
    }
}

/// 주황 경고 상자(D-40). 아이콘은 그림이고 글자가 접근성 라벨이다.
struct WarningNote: View {
    let text: String
    /// 글 끝에 붙는 링크 버튼(예: [자세히]).
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    /// 있으면 오른쪽 위에 닫기(X)를 둔다.
    var onDismiss: (() -> Void)? = nil
    var dismissLabel: String = ""

    var body: some View {
        HStack(alignment: .top, spacing: DS.s(8)) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(DS.caption)
                .foregroundStyle(DS.warn)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: DS.s(2)) {
                GlobeText.make(text, size: DS.s(11))
                    .font(DS.caption)
                    .foregroundStyle(Color.primary.opacity(0.85))
                    .lineSpacing(DS.s(2))
                    .fixedSize(horizontal: false, vertical: true)
                if let actionTitle, let action {
                    Button(actionTitle, action: action)
                        .buttonStyle(.link)
                        .font(DS.caption)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let onDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: DS.s(9), weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: DS.s(16), height: DS.s(16))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(dismissLabel)
            }
        }
        .padding(DS.s(10))
        .background(RoundedRectangle(cornerRadius: DS.s(8), style: .continuous).fill(DS.warn.opacity(0.10)))
        .accessibilityElement(children: .contain)
    }
}

// macOS 기본 스위치: 프레임 54x24pt, 렌더로 보이는 트랙 높이 약 25pt(0.88배일 때 44px=22pt 실측).
// 폭이 넓어 Picker와 같은 높이면 더 커 보이므로 높이를 맞추지 않고 0.80배로 줄인다(보이는 높이 약 20pt, 폭 약 43pt).
private let switchBaseWidth: CGFloat = 54
private let switchBaseHeight: CGFloat = 24
private let switchScale: CGFloat = DS.switchScale

extension View {
    /// macOS 기본 스위치에 초록 tint(D-39). 라벨은 행 제목이 맡는다.
    func greenSwitch() -> some View {
        toggleStyle(.switch).tint(DS.ok).labelsHidden()
            .fixedSize()
            .scaleEffect(switchScale)
            .frame(width: switchBaseWidth * switchScale, height: switchBaseHeight * switchScale)
    }
}
