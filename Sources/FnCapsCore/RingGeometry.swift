import Foundation

/// 키와 언어 상자의 고리 배치 수치(재설계 §3, 확정 초안 design/settings-drafts/final.swift).
/// 화면 좌표(y 아래로)를 쓴다. 각도 0은 오른쪽, π/2는 아래, π는 왼쪽, 3π/2는 위다.
/// 첫 타일은 왼쪽(π)에서 시작하고 시계 방향으로 돈다. 모든 각도는 [0, 2π)로 돌려준다.
public enum RingGeometry {
    /// 설정창 전체 배율. DS.scale이 이 값을 따른다(quick 261110-jnz).
    public static let scale = 1.15
    public static let unit = 34.0 * scale
    public static let tileWidth = 44.0 * scale
    /// 타일 (44×28)×scale(D-44). 기호는 메뉴 막대 입력 소스 아이콘 크기의 테두리 네모 22×16 pt에 scale.
    public static let tileHeight = 28.0 * scale
    public static let arrowSize = 9.0 * scale
    /// 1개일 때 아래 안내 한 줄, 0개일 때 점선 칸과 안내 한 줄이 들어갈 높이(final.swift `ringHeight`).
    public static let minBoxHeight = 96.0 * scale
    /// 칸 경계에서 넣을 자리가 떨리지 않도록 두는 여유(§4, 8°).
    public static let defaultHysteresis = 8 * Double.pi / 180

    public struct Radii: Equatable, Sendable {
        public let a: Double
        public let b: Double
        public init(a: Double, b: Double) { self.a = a; self.b = b }
    }

    /// 타일 개수별 고리 반지름. 0·1개는 가운데 한 점이다.
    public static func radii(count: Int) -> Radii {
        switch count {
        case ...1: return Radii(a: 0, b: 0)
        case 2: return Radii(a: 52 * scale, b: 32 * scale)
        case 3...4: return Radii(a: 64 * scale, b: 46 * scale)
        default: return Radii(a: 76 * scale, b: 60 * scale)
        }
    }

    /// 높이가 고정된 상자에 들어가는 가장 큰 표 값. count의 값보다 크지 않다.
    public static func radii(count: Int, maxBoxHeight: Double) -> Radii {
        var n = max(count, 0)
        while n > 1 {
            let r = radii(count: n)
            if boxHeight(radii: r) <= maxBoxHeight { return r }
            n -= 1
        }
        return radii(count: 0)
    }

    /// 상자 높이 = max(2b + 타일 높이 + 40, 96), 모두 scale 곱.
    public static func boxHeight(count: Int) -> Double {
        boxHeight(radii: radii(count: count))
    }

    static func boxHeight(radii r: Radii) -> Double {
        max(2 * r.b + tileHeight + 40 * scale, minBoxHeight)
    }

    /// i번째 타일의 각도 π + i·2π/n.
    public static func slotAngle(index: Int, count: Int) -> Double {
        normalize(.pi + Double(index) * 2 * .pi / Double(max(count, 1)))
    }

    /// 고리 가운데에서 i번째 타일 가운데까지의 거리.
    public static func slotOffset(index: Int, count: Int, radii r: Radii) -> (x: Double, y: Double) {
        let t = slotAngle(index: index, count: count)
        return (r.a * cos(t), r.b * sin(t))
    }

    /// 화살촉 각도 t_i + π/n. 2개 미만이면 화살촉이 없다.
    public static func arrowAngles(count: Int) -> [Double] {
        guard count >= 2 else { return [] }
        return (0..<count).map { normalize(slotAngle(index: $0, count: count) + .pi / Double(count)) }
    }

    /// arrowtriangle.right 기준 회전각 atan2(b·cos t, −a·sin t). 고리의 시계 방향 접선을 향한다.
    public static func arrowRotation(angle t: Double, radii r: Radii) -> Double {
        atan2(r.b * cos(t), -r.a * sin(t))
    }

    /// 진입 화살표(D-07)의 좌표. 고리 가운데 기준 화면 좌표(y 아래로)다.
    /// `tip`은 화살촉 끝(타일 쪽), `tail`은 꼬리, `head`는 화살촉 중심.
    public struct EntryArrow: Equatable, Sendable {
        public let tailX: Double
        public let tailY: Double
        public let tipX: Double
        public let tipY: Double
        public let headX: Double
        public let headY: Double
        /// `arrowtriangle.right` 기준 회전각. 0에서 +x를 향한다.
        public let rotation: Double

        public init(tailX: Double, tailY: Double, tipX: Double, tipY: Double,
                    headX: Double, headY: Double, rotation: Double) {
            self.tailX = tailX
            self.tailY = tailY
            self.tipX = tipX
            self.tipY = tipY
            self.headX = headX
            self.headY = headY
            self.rotation = rotation
        }
    }

    /// 진입 언어 타일로 들어오는 화살표 좌표(D-07, UI-SPEC §2 기하).
    /// 슬롯 t·p에서 타원 바깥 법선 n = normalize(cos t / a, sin t / b)을 구하고,
    /// 타일 가장자리 거리 e = min((tileW/2)/|nx|, (tileH/2)/|ny|)에서 |성분|이 0인 축은 뺀다.
    /// tip = p + n·(e + gap), tail = tip + n·length, head = tip + n·(arrowSize/2),
    /// 회전 = atan2(-ny, -nx). 화살촉이 고리 밖에서 타일 쪽을 향한다.
    public static func entryArrow(index: Int, count: Int, radii r: Radii,
                                  length: Double = 14 * scale,
                                  gap: Double = 3 * scale) -> EntryArrow {
        let t = slotAngle(index: index, count: count)
        let p = slotOffset(index: index, count: count, radii: r)

        // 바깥 법선. 반지름이 0인 축은 0 나눔을 피해 cos/sin을 그대로 쓴다.
        let rawX = r.a == 0 ? cos(t) : cos(t) / r.a
        let rawY = r.b == 0 ? sin(t) : sin(t) / r.b
        let magnitude = (rawX * rawX + rawY * rawY).squareRoot()
        let nx = magnitude > 0 ? rawX / magnitude : 1
        let ny = magnitude > 0 ? rawY / magnitude : 0

        // 타일 가장자리까지의 거리. |성분|이 0에 가까운 축은 0 나눔을 피해 뺀다.
        var edge = Double.infinity
        if abs(nx) >= 1e-12 { edge = min(edge, (tileWidth / 2) / abs(nx)) }
        if abs(ny) >= 1e-12 { edge = min(edge, (tileHeight / 2) / abs(ny)) }
        if !edge.isFinite { edge = 0 }

        let reach = edge + gap
        let tipX = p.x + nx * reach
        let tipY = p.y + ny * reach
        return EntryArrow(
            tailX: tipX + nx * length,
            tailY: tipY + ny * length,
            tipX: tipX,
            tipY: tipY,
            headX: tipX + nx * arrowSize / 2,
            headY: tipY + ny * arrowSize / 2,
            rotation: atan2(-ny, -nx)
        )
    }

    /// 포인터 위치(고리 가운데 기준)의 고리 위 각도. 타원을 원으로 펴서 잰다.
    public static func pointerAngle(dx: Double, dy: Double, radii r: Radii) -> Double {
        if r.a == 0 || r.b == 0 { return normalize(atan2(dy, dx)) }
        return normalize(atan2(dy / r.b, dx / r.a))
    }

    /// 칸 m개(중심각 θk = π + k·2π/m) 가운데 넣을 자리.
    /// previous가 유효하고 |φ − θp| ≤ π/m + h이면 previous를 유지한다.
    public static func insertionIndex(pointerAngle phi: Double, slotCount m: Int, previous: Int?,
                                      hysteresis h: Double = defaultHysteresis) -> Int {
        guard m > 1 else { return 0 }
        let p = normalize(phi)
        if let prev = previous, prev >= 0, prev < m,
           circularDistance(p, slotAngle(index: prev, count: m)) <= .pi / Double(m) + h {
            return prev
        }
        var best = 0
        var bestDistance = Double.infinity
        for k in 0..<m {
            let d = circularDistance(p, slotAngle(index: k, count: m))
            if d < bestDistance { best = k; bestDistance = d }
        }
        return best
    }

    static func normalize(_ angle: Double) -> Double {
        let full = 2 * Double.pi
        var r = angle.truncatingRemainder(dividingBy: full)
        if r < 0 { r += full }
        if r >= full - 1e-12 { r = 0 }
        return r
    }

    static func circularDistance(_ x: Double, _ y: Double) -> Double {
        let d = abs(normalize(x) - normalize(y))
        return min(d, 2 * .pi - d)
    }
}
