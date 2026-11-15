import Testing
@testable import FnCapsCore

/// 「키와 언어」 쪽 상자에서 타일을 끄는 동안 가장자리에서 자동으로 스크롤하는 속도(W7).
/// 04-22가 한 틱마다 이 값을 쓴다. 화면·AppKit 없이 순수 계산만 한다.
@Suite struct DragAutoScrollTests {
    @Test func bottomBandScrollsPositive() {
        // 아래 가장자리 40pt 안: 아래로(양수).
        #expect(DragAutoScroll.step(pointerY: 480, viewportMinY: 100, viewportMaxY: 500) > 0)
        // 가장자리에 가까울수록 빠르다.
        let near = DragAutoScroll.step(pointerY: 495, viewportMinY: 100, viewportMaxY: 500)
        let far = DragAutoScroll.step(pointerY: 465, viewportMinY: 100, viewportMaxY: 500)
        #expect(near > far)
        #expect(far > 0)
    }

    @Test func topBandScrollsNegative() {
        #expect(DragAutoScroll.step(pointerY: 120, viewportMinY: 100, viewportMaxY: 500) < 0)
        let near = DragAutoScroll.step(pointerY: 105, viewportMinY: 100, viewportMaxY: 500)
        let far = DragAutoScroll.step(pointerY: 135, viewportMinY: 100, viewportMaxY: 500)
        #expect(near < far)
    }

    @Test func middleIsZero() {
        #expect(DragAutoScroll.step(pointerY: 300, viewportMinY: 100, viewportMaxY: 500) == 0)
        // band 경계 바로 안쪽은 아직 0이다(경계 밖과 같게).
        #expect(DragAutoScroll.step(pointerY: 460, viewportMinY: 100, viewportMaxY: 500) == 0)
    }

    @Test func outsideBandClampsToMaxStep() {
        // 가장자리 밖(뷰포트 아래·위)은 최대 속도로 붙잡는다.
        #expect(DragAutoScroll.step(pointerY: 600, viewportMinY: 100, viewportMaxY: 500) == 12)
        #expect(DragAutoScroll.step(pointerY: 0, viewportMinY: 100, viewportMaxY: 500) == -12)
        // 정확히 가장자리에서도 최대.
        #expect(DragAutoScroll.step(pointerY: 500, viewportMinY: 100, viewportMaxY: 500) == 12)
    }

    @Test func tooSmallViewportIsZero() {
        // 높이가 band×2보다 작으면 위·아래 판정이 겹치므로 0.
        #expect(DragAutoScroll.step(pointerY: 110, viewportMinY: 100, viewportMaxY: 150) == 0)
        #expect(DragAutoScroll.step(pointerY: 150, viewportMinY: 100, viewportMaxY: 150) == 0)
        // 0이나 뒤집힌 뷰포트도 0.
        #expect(DragAutoScroll.step(pointerY: 100, viewportMinY: 100, viewportMaxY: 100) == 0)
        #expect(DragAutoScroll.step(pointerY: 100, viewportMinY: 200, viewportMaxY: 100) == 0)
    }

    @Test func customBandAndMaxStep() {
        #expect(DragAutoScroll.step(pointerY: 500, viewportMinY: 100, viewportMaxY: 500, band: 20, maxStep: 6) == 6)
        #expect(DragAutoScroll.step(pointerY: 485, viewportMinY: 100, viewportMaxY: 500, band: 20, maxStep: 6) > 0)
        #expect(DragAutoScroll.step(pointerY: 485, viewportMinY: 100, viewportMaxY: 500, band: 20, maxStep: 6) < 6)
    }
}
