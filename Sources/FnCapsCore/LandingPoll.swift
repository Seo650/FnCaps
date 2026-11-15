import Foundation

/// 01-REVIEW L-04: 착지는 TIS 선택 변경 알림이 먼저 깨워 줄 수 있지만, 알림은 추가 깨우기일 뿐이다.
/// 폴링은 알림이 오지 않거나 합쳐져 늦게 올 때의 대비책이라 예전과 같은 5 ms로 둔다(05 WR-06).
/// 실키 회귀가 보이면 notificationFirst를 false로 바꿔 알림 구독 없이 폴링만 쓴다
/// (user away — review at UAT).
public enum LandingPoll {
    /// 참이면 `LandingWaiter`가 `kTISNotifySelectedKeyboardInputSourceChanged`도 함께 듣는다.
    public static let notificationFirst = true

    /// 알림 우선 이전부터 쓰던 폴링 간격.
    public static let legacyPollMs: Double = 5

    /// 알림이 오지 않을 때의 대비책 폴링 간격. 알림 유무와 상관없이 5 ms를 유지한다.
    public static let fallbackPollMs: Double = 5

    /// `LandingWaiter.wait` / `waitStable`의 기본 폴링 간격.
    public static var pollMs: Double { fallbackPollMs }
}
