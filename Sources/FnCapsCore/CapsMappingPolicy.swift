import Foundation

/// 시스템에 둘 Caps 경로의 범위.
public enum CapsSystemTarget: Equatable, Sendable {
    /// #60과 매핑 모두 적용.
    case full
    /// 매핑만 내리고 #60은 유지한다(잠금 화면).
    case shortcutOnly
    /// 둘 다 복원한다.
    case none
    /// 아무것도 하지 않는다(탭이 잠깐 없는 동안).
    case hold
}

public enum CapsMappingPolicy {
    /// 탭이 사라진 뒤 이 시간이 지나면 매핑을 내린다. 탭 재생성 때마다 #60을 쓰지 않기 위한 유예.
    public static let tapGraceSeconds: TimeInterval = 5

    /// 우선순위: 없음 조건(탭 조건 제외) > 세션 비활성·앱별 끄기 > 탭 없음.
    /// - appOff: 「FnCaps 끄기」 앱이 맨 앞이다(FINAL-REVIEW §7 R1). 화면 잠금과 같은 검증된 경로로
    ///   매핑만 내리고 #60은 두어, 앱을 오갈 때 시스템 단축키를 다시 쓰지 않는다.
    public static func target(
        axTrusted: Bool, enabled: Bool, tapInstalled: Bool, tapAbsentSeconds: TimeInterval,
        capsListActive: Bool, sessionAway: Bool, appOff: Bool = false, capsTaken: Bool, hasPulseRoute: Bool
    ) -> CapsSystemTarget {
        guard enabled, axTrusted, capsListActive, !capsTaken, hasPulseRoute
        else { return .none }
        if sessionAway || appOff { return .shortcutOnly }
        if !tapInstalled { return tapAbsentSeconds < tapGraceSeconds ? .hold : .none }
        return .full
    }
}

/// 1초 조정 틱이 이번에 무엇을 할지만 정한다. 시스템에 닿지 않는다.
public enum CapsTickDecision: Equatable, Sendable {
    /// 키보드 열거와 재적용을 이어서 한다.
    case proceed
    /// 매핑만 내린다(잠금 화면, 다른 사용자 세션).
    case markAway
    /// 아무것도 하지 않는다. 틱의 나머지는 건너뛴다.
    case stayIdle

    /// - lastTarget: 마지막으로 성공한 시스템 target. 복원이 시작되면 nil이다.
    /// - gateIdle: 적용·복원이 진행 중이 아니다.
    public static func decide(
        sessionAway: Bool, lastTarget: CapsSystemTarget?, gateIdle: Bool, terminating: Bool
    ) -> CapsTickDecision {
        guard !terminating, gateIdle, lastTarget == .full else { return .stayIdle }
        return sessionAway ? .markAway : .proceed
    }
}
