import SwiftUI

/// 문구 속 🌐 이모지를 SF Symbol `globe`로 바꿔 그린다(2026-11-13 사용자 요청).
/// 이모지는 파란색으로 튀지만 기호는 글자색·글꼴 크기를 따른다. 문자열 파일은 🌐 그대로 둔다
/// (메뉴 막대 메뉴처럼 기호를 넣을 수 없는 곳에서도 같은 문구를 쓰기 때문).
enum GlobeText {
    /// `size`는 둘레 글자 크기다. 기호는 그보다 작게(약 0.8배) 그려 글자 높이에 맞춘다(2026-11-13 사용자: 「너무 커」).
    static func make(_ string: String, size: CGFloat = DS.s(13)) -> Text {
        let parts = string.components(separatedBy: "🌐")
        var text = Text(verbatim: parts[0])
        let globe = Text(Image(systemName: "globe")).font(.system(size: size * 0.8))
        for part in parts.dropFirst() {
            text = text + globe + Text(verbatim: part)
        }
        return text
    }
}
