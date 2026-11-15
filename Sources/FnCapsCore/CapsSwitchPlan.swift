// 구조 참고: gksdud InputSources.swift 준비 규칙 (MIT). 홉 규칙은 FnCaps 고유(조합 중 글자 보호).
import Foundation

/// Caps 전환 계획. 순수 판단이며 TIS·CoreGraphics에 의존하지 않는다.
public enum CapsSwitchPlan: Equatable, Sendable {
    /// 직전 소스가 대상이다. 펄스만 게시한다.
    case pulse
    /// TIS로 대상 -> 원래 순서로 골라 최근 순서를 맞춘 뒤 펄스한다.
    case primeThenPulse
    /// 펄스로 직전 소스에 간 뒤(OS가 조합을 확정), 거기서 TIS로 대상 -> 그곳을 골라 다시 펄스한다.
    case hopThenPrime

    public static func decide(
        target: SourceID, origin: SourceID, recent: RecentSources,
        originIsLayout: Bool, targetIsLayout: Bool, mayBeComposing: Bool
    ) -> CapsSwitchPlan {
        if PrimeDecision.decide(target: target, origin: origin, recent: recent) == .skip { return .pulse }
        // 입력기에서 레이아웃을 백그라운드로 고르면 조합 중 글자를 버린다(gksdud 측정, Pitfall 2).
        let risky = !originIsLayout && targetIsLayout
        return risky && mayBeComposing && recent.previous != nil ? .hopThenPrime : .primeThenPulse
    }
}
