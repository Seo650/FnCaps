import Foundation

/// 실행할 때 설정 창을 띄울지 정한다(todo 2026-11-11 first-launch-and-window-front).
/// 처음 실행과 사용자가 직접 연 실행은 늘 띄운다. 로그인 자동 실행만 메뉴 막대에 조용히 둔다.
/// 로그인 실행인지 모르면(nil) 띄운다 — 사용자가 연 것을 무시하는 쪽이 더 나쁘다.
public enum LaunchWindowPolicy {
    public static func shouldShow(firstLaunch: Bool, restarted: Bool, loginItem: Bool?) -> Bool {
        if firstLaunch || restarted { return true }
        return loginItem != true
    }
}
