import Foundation

/// 「키와 언어」 쪽 상자에서 타일을 끄는 동안 가장자리에서 자동으로 스크롤하는 속도(W7).
/// 화면 없이 계산만 한다: 한 틱마다 04-22가 이 값을 스크롤 오프셋에 더한다.
public enum DragAutoScroll {
    /// 선형 감속: 가장자리까지 거리 d(< band)일 때 `maxStep × (1 − d / band)`.
    /// 아래 가장자리는 양수, 위 가장자리는 음수, 가운데는 0. 뷰포트가 band×2보다 작으면
    /// 위·아래 판정이 겹치므로 0을 낸다.
    public static func step(
        pointerY: Double, viewportMinY: Double, viewportMaxY: Double,
        band: Double = 40, maxStep: Double = 12
    ) -> Double {
        guard band > 0, maxStep > 0 else { return 0 }
        let height = viewportMaxY - viewportMinY
        guard height >= band * 2 else { return 0 }
        let fromTop = pointerY - viewportMinY
        let fromBottom = viewportMaxY - pointerY
        if fromTop < band { return -maxStep * (1 - max(0, fromTop) / band) }
        if fromBottom < band { return maxStep * (1 - max(0, fromBottom) / band) }
        return 0
    }
}
