import Foundation
import Testing
@testable import FnCapsCore

private func near(_ a: Double, _ b: Double, _ eps: Double = 1e-9) -> Bool { abs(a - b) <= eps }
private func deg(_ d: Double) -> Double { d * .pi / 180 }

@Suite struct RingGeometryTests {
    @Test func radiiZeroAndOneAreCenter() {
        #expect(RingGeometry.radii(count: 0) == .init(a: 0, b: 0))
        #expect(RingGeometry.radii(count: 1) == .init(a: 0, b: 0))
    }

    private func nearRadii(_ r: RingGeometry.Radii, _ a: Double, _ b: Double) -> Bool {
        near(r.a, a * RingGeometry.scale) && near(r.b, b * RingGeometry.scale)
    }

    @Test func scaleIsOnePointOneFive() {
        #expect(RingGeometry.scale == 1.15)
        let s = RingGeometry.scale
        #expect(near(RingGeometry.unit, 34 * s))
        #expect(near(RingGeometry.tileWidth, 44 * s))
        #expect(near(RingGeometry.tileHeight, 28 * s))
        #expect(near(RingGeometry.arrowSize, 9 * s))
        #expect(near(RingGeometry.minBoxHeight, 96 * s))
    }

    @Test func radiiTableValues() {
        #expect(nearRadii(RingGeometry.radii(count: 2), 52, 32))
        #expect(nearRadii(RingGeometry.radii(count: 3), 64, 46))
        #expect(nearRadii(RingGeometry.radii(count: 4), 64, 46))
        #expect(nearRadii(RingGeometry.radii(count: 5), 76, 60))
        #expect(nearRadii(RingGeometry.radii(count: 6), 76, 60))
        #expect(nearRadii(RingGeometry.radii(count: 7), 76, 60))
    }

    @Test func boxHeightMatchesFinalDraft() {
        let s = RingGeometry.scale
        #expect(near(RingGeometry.minBoxHeight, 96 * s))
        #expect(near(RingGeometry.boxHeight(count: 0), 96 * s))
        #expect(near(RingGeometry.boxHeight(count: 1), 96 * s))
        #expect(near(RingGeometry.boxHeight(count: 2), 132 * s))
        #expect(near(RingGeometry.boxHeight(count: 3), 160 * s))
        #expect(near(RingGeometry.boxHeight(count: 4), 160 * s))
        #expect(near(RingGeometry.boxHeight(count: 5), 188 * s))
        #expect(near(RingGeometry.boxHeight(count: 6), 188 * s))
    }

    @Test func radiiFitFixedBoxHeight() {
        let s = RingGeometry.scale
        #expect(nearRadii(RingGeometry.radii(count: 5, maxBoxHeight: 166 * s), 64, 46))
        #expect(nearRadii(RingGeometry.radii(count: 3, maxBoxHeight: 194 * s), 64, 46))
        #expect(RingGeometry.radii(count: 6, maxBoxHeight: 96 * s) == .init(a: 0, b: 0))
    }

    @Test func slotAngleStartsLeftAndGoesClockwise() {
        #expect(near(RingGeometry.slotAngle(index: 0, count: 4), .pi))
        #expect(near(RingGeometry.slotAngle(index: 1, count: 4), 3 * .pi / 2))
        #expect(near(RingGeometry.slotAngle(index: 2, count: 4), 0))
        #expect(near(RingGeometry.slotAngle(index: 3, count: 4), .pi / 2))
    }

    @Test func slotOffsetForTwo() {
        let r = RingGeometry.radii(count: 2)
        let p0 = RingGeometry.slotOffset(index: 0, count: 2, radii: r)
        let p1 = RingGeometry.slotOffset(index: 1, count: 2, radii: r)
        #expect(near(p0.x, -r.a) && near(p0.y, 0))
        #expect(near(p1.x, r.a) && near(p1.y, 0))
    }

    @Test func arrowAnglesSitBetweenTiles() {
        let a = RingGeometry.arrowAngles(count: 2)
        #expect(a.count == 2)
        #expect(near(a[0], 3 * .pi / 2))
        #expect(near(a[1], .pi / 2))
        #expect(RingGeometry.arrowAngles(count: 1).isEmpty)
        #expect(RingGeometry.arrowAngles(count: 0).isEmpty)
    }

    @Test func arrowRotationFollowsTangent() {
        let r = RingGeometry.radii(count: 2)
        // 위쪽(3π/2)에서 시계 방향 접선은 오른쪽(0).
        #expect(near(RingGeometry.arrowRotation(angle: 3 * .pi / 2, radii: r), 0))
        // 아래쪽(π/2)에서는 왼쪽(π).
        #expect(near(abs(RingGeometry.arrowRotation(angle: .pi / 2, radii: r)), .pi))
        #expect(near(RingGeometry.arrowRotation(angle: 0.7, radii: r), atan2(r.b * cos(0.7), -r.a * sin(0.7))))
    }

    @Test func pointerAngleNormalizesOnEllipse() {
        let r = RingGeometry.radii(count: 3)
        #expect(near(RingGeometry.pointerAngle(dx: -r.a, dy: 0, radii: r), .pi))
        #expect(near(RingGeometry.pointerAngle(dx: 0, dy: -r.b, radii: r), 3 * .pi / 2))
        #expect(near(RingGeometry.pointerAngle(dx: r.a, dy: r.b, radii: r), .pi / 4))
        let a = RingGeometry.pointerAngle(dx: 3, dy: -0.0001, radii: r)
        #expect(a >= 0 && a < 2 * .pi)
    }

    @Test func pointerAngleWithZeroRadiiUsesRawAtan2() {
        let r = RingGeometry.Radii(a: 0, b: 0)
        #expect(near(RingGeometry.pointerAngle(dx: 1, dy: 1, radii: r), .pi / 4))
        #expect(near(RingGeometry.pointerAngle(dx: 0, dy: -1, radii: r), 3 * .pi / 2))
    }

    @Test func insertionSingleSlotIsZero() {
        #expect(RingGeometry.insertionIndex(pointerAngle: 1.2, slotCount: 1, previous: nil) == 0)
        #expect(RingGeometry.insertionIndex(pointerAngle: 1.2, slotCount: 0, previous: nil) == 0)
    }

    @Test func insertionNearestWithoutPrevious() {
        #expect(RingGeometry.insertionIndex(pointerAngle: deg(185), slotCount: 4, previous: nil) == 0)
    }

    @Test func insertionHysteresisKeepsPreviousNearBoundary() {
        #expect(RingGeometry.insertionIndex(pointerAngle: deg(230), slotCount: 4, previous: 0) == 0)
        #expect(RingGeometry.insertionIndex(pointerAngle: deg(234), slotCount: 4, previous: 0) == 1)
        #expect(RingGeometry.insertionIndex(pointerAngle: deg(220), slotCount: 4, previous: 1) == 1)
        #expect(RingGeometry.insertionIndex(pointerAngle: deg(216), slotCount: 4, previous: 1) == 0)
    }

    @Test func insertionWrapsAroundZero() {
        #expect(RingGeometry.insertionIndex(pointerAngle: deg(355), slotCount: 4, previous: nil) == 2)
        #expect(RingGeometry.insertionIndex(pointerAngle: deg(5), slotCount: 4, previous: nil) == 2)
    }

    @Test func insertionOutOfRangePreviousActsAsNil() {
        #expect(RingGeometry.insertionIndex(pointerAngle: deg(185), slotCount: 4, previous: 7) == 0)
        #expect(RingGeometry.insertionIndex(pointerAngle: deg(185), slotCount: 4, previous: -1) == 0)
    }

    @Test func defaultHysteresisIsEightDegrees() {
        #expect(near(RingGeometry.defaultHysteresis, deg(8)))
    }

    // MARK: 진입 화살표(D-07)

    @Test func entryArrowTwoLeftPointsRight() {
        let r = RingGeometry.radii(count: 2)
        let s = RingGeometry.scale
        let arrow = RingGeometry.entryArrow(index: 0, count: 2, radii: r)
        #expect(near(arrow.tipX, -(r.a + RingGeometry.tileWidth / 2 + 3 * s)))
        #expect(near(arrow.tipY, 0))
        #expect(near(arrow.tailX, arrow.tipX - 14 * s))
        #expect(near(arrow.tailY, 0))
        #expect(near(arrow.rotation, 0))
    }

    @Test func entryArrowTwoRightPointsLeft() {
        let r = RingGeometry.radii(count: 2)
        let s = RingGeometry.scale
        let arrow = RingGeometry.entryArrow(index: 1, count: 2, radii: r)
        #expect(near(arrow.tipX, r.a + RingGeometry.tileWidth / 2 + 3 * s))
        #expect(near(arrow.tipY, 0))
        #expect(near(cos(arrow.rotation), -1))
        #expect(near(sin(arrow.rotation), 0))
    }

    @Test func entryArrowFourTopPointsDown() {
        let r = RingGeometry.radii(count: 4)
        let s = RingGeometry.scale
        let arrow = RingGeometry.entryArrow(index: 1, count: 4, radii: r)
        #expect(near(arrow.tipY, -(r.b + RingGeometry.tileHeight / 2 + 3 * s)))
        #expect(near(cos(arrow.rotation), 0))
        #expect(near(sin(arrow.rotation), 1))
    }

    @Test func entryArrowGeometryHoldsForTwoThroughSix() {
        for count in 2...6 {
            let r = RingGeometry.radii(count: count)
            let halfHeight = RingGeometry.boxHeight(count: count) / 2
            for index in 0..<count {
                let arrow = RingGeometry.entryArrow(index: index, count: count, radii: r)
                let p = RingGeometry.slotOffset(index: index, count: count, radii: r)

                // 화살촉이 타일 사각형 밖에 있다.
                #expect(abs(arrow.tipX - p.x) >= RingGeometry.tileWidth / 2 - 1e-9
                        || abs(arrow.tipY - p.y) >= RingGeometry.tileHeight / 2 - 1e-9)

                // 꼬리가 상자 높이 안에 든다.
                #expect(abs(arrow.tailY) <= halfHeight + 1e-9)

                // 화살촉 중심은 tip에서 법선 방향으로 arrowSize/2만큼.
                let hx = arrow.headX - arrow.tipX
                let hy = arrow.headY - arrow.tipY
                #expect(near((hx * hx + hy * hy).squareRoot(), RingGeometry.arrowSize / 2))

                // 법선 n은 단위 벡터이고, tip은 타일 가운데에서 바깥(n) 쪽에 있다.
                let half = RingGeometry.arrowSize / 2
                let nx = hx / half
                let ny = hy / half
                #expect(near(nx * nx + ny * ny, 1))
                #expect((arrow.tipX - p.x) * nx + (arrow.tipY - p.y) * ny > 0)

                // 회전은 화살촉이 타일 쪽을 향함: (cos, sin)이 (p - tip) 방향이다.
                let dx = p.x - arrow.tipX
                let dy = p.y - arrow.tipY
                let d = (dx * dx + dy * dy).squareRoot()
                #expect(near(cos(arrow.rotation), dx / d, 1e-6))
                #expect(near(sin(arrow.rotation), dy / d, 1e-6))

                // 좌표에 NaN·무한대가 없다.
                #expect(arrow.tipX.isFinite && arrow.tipY.isFinite
                        && arrow.tailX.isFinite && arrow.tailY.isFinite
                        && arrow.headX.isFinite && arrow.headY.isFinite
                        && arrow.rotation.isFinite)
            }
        }
    }

    @Test func entryArrowShorterLengthKeepsTipAndHead() {
        let r = RingGeometry.radii(count: 3)
        let s = RingGeometry.scale
        let def = RingGeometry.entryArrow(index: 2, count: 3, radii: r)
        let short = RingGeometry.entryArrow(index: 2, count: 3, radii: r, length: 12 * s)
        #expect(near(def.tipX, short.tipX))
        #expect(near(def.tipY, short.tipY))
        #expect(near(def.headX, short.headX))
        #expect(near(def.headY, short.headY))
        let tailLength = ((short.tailX - short.tipX) * (short.tailX - short.tipX)
                          + (short.tailY - short.tipY) * (short.tailY - short.tipY)).squareRoot()
        #expect(near(tailLength, 12 * s))
        let moved = ((def.tailX - short.tailX) * (def.tailX - short.tailX)
                     + (def.tailY - short.tailY) * (def.tailY - short.tailY)).squareRoot()
        #expect(near(moved, 2 * s))
    }

    @Test func entryArrowZeroRadiiStaysFinite() {
        let s = RingGeometry.scale
        let candidates = [RingGeometry.Radii(a: 0, b: 0),
                          RingGeometry.Radii(a: 0, b: 32 * s),
                          RingGeometry.Radii(a: 52 * s, b: 0)]
        for radii in candidates {
            for index in 0..<2 {
                let arrow = RingGeometry.entryArrow(index: index, count: 2, radii: radii)
                #expect(arrow.tipX.isFinite && arrow.tipY.isFinite
                        && arrow.tailX.isFinite && arrow.tailY.isFinite
                        && arrow.headX.isFinite && arrow.headY.isFinite
                        && arrow.rotation.isFinite)
            }
        }
    }
}
