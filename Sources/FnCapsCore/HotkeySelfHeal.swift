import Foundation

/// Caps 펄스가 OS에 닿지 않는 증상(#60 상실)을 누름 결과로만 잡는 순수 계수기. 시스템에 닿지 않는다.
/// 1초 조정 틱과 무관하게, 펄스 착지·시간 초과만 계수한다(사용자 결정 2026-11-16: 틱에서는 #60을 읽지 않음).
/// 2026-11-16 사고: 중복 실행이 끝나며 #60을 원래 조합으로 되돌렸고, 남은 인스턴스는 매핑만 다시 써서
/// 모든 누름이 `fallback plan=pulse leg=first reason=timeout`으로 떨어졌다.
public struct HotkeySelfHeal: Equatable, Sendable {
    /// 한 번의 시간 초과는 느린 전환일 수 있다. 둘이면 드물고, 잘못 판단해도 비용은 plist 읽기 한 번뿐이다.
    public static let missThreshold = 2
    /// 확인 간격. 다른 도구가 #60을 계속 가져가도 읽기를 60초에 한 번으로 묶는다.
    public static let checkCooldown: TimeInterval = 60
    /// 다시 적용 최대 횟수. 계속 빼앗기면 쓰기 반복을 멈춘다(T-dvj-03).
    public static let maxReapplies = 3

    public private(set) var misses = 0
    public private(set) var lastCheckAt: TimeInterval?
    public private(set) var reapplies = 0
    /// 확인이 예약됐고 아직 결과를 넣지 않았는가. 예약을 겹쳐 만들지 않는다.
    public private(set) var pending = false
    public private(set) var gaveUp = false

    public init() {}

    public enum Verdict: Equatable, Sendable {
        /// #60이 우리 값이다. 아무것도 하지 않는다.
        case keep
        /// #60을 읽지 못했다. 쓰지 않는다.
        case unreadable
        /// #60을 잃었다. 기존 조정 경로로 다시 적용한다.
        case reapply
        /// 다시 적용 한도를 다 썼다. 멈춘다.
        case giveUp
    }

    /// 펄스가 착지했다. 연속 시간 초과만 지운다. 다시 적용 한도는 남긴다:
    /// 빼앗기는 사이사이 착지가 있어 한도를 초기화하면 한도가 무의미해진다.
    public mutating func noteLanded() {
        misses = 0
    }

    /// 펄스 시간 초과 하나. 지금 확인을 예약해야 하면 참.
    public mutating func noteTimeout(at now: TimeInterval) -> Bool {
        misses += 1
        guard !gaveUp, !pending, misses >= Self.missThreshold else { return false }
        if let lastCheckAt, now - lastCheckAt < Self.checkCooldown { return false }
        pending = true
        return true
    }

    /// 예약한 확인의 결과. `ours`가 nil이면 읽기 실패다.
    public mutating func checked(ours: Bool?, at now: TimeInterval) -> Verdict {
        pending = false
        misses = 0
        lastCheckAt = now
        switch ours {
        case nil:
            return .unreadable
        case true:
            return .keep
        case false:
            if reapplies < Self.maxReapplies {
                reapplies += 1
                return .reapply
            }
            gaveUp = true
            return .giveUp
        }
    }

    /// 조건이 안 맞아 읽지 못했을 때(게이트 사용 중, 전환 중, 키 없음). 계수는 그대로 두고 다음 시간 초과에 다시 시도한다.
    public mutating func skipCheck() {
        pending = false
    }

    /// 끄기, 「원래대로 되돌리기」(「지금 복구」), 종료에서 처음으로 돌린다.
    public mutating func reset() {
        self = HotkeySelfHeal()
    }
}
