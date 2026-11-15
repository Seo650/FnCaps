import Foundation

/// Decides whether to show the "Press Globe key to" notice from `AppleFnUsageType`.
/// Values: 0 do nothing, 1 change input source, 2 emoji, 3 dictation (Phase 1 E2b).
/// S10 직접 전환은 값이 1일 때만 쓰인다. 다른 값에서는 fn이 TIS로 동작해 Finder 이름 바꾸기 입력란이
/// 따라오지 않으므로(GAP-09) 안내한다. nil은 안내 대상이다(키가 없을 때의 OS 동작은 확인하지 못함, 추정).
/// 역사: 02-08 B7은 FnCaps 실행 중 단독 fn이 받아쓰기를 켜지 않음을 보였다. 이 안내의 이유는 그것과 다르다.
public enum GlobeSettingAdvisor {
    public static let dictationValue = 3
    public static func needsNotice(usage: Int?) -> Bool { usage != FnRoutePolicy.changeInputSourceUsage }
}
