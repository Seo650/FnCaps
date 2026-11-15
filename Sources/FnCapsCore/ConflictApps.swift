import Foundation

/// 같은 키를 다루는 다른 앱이 실행 중인지 본다(D-40). 실행 중 앱의 번들 ID를 읽기만 한다.
///
/// 출처: 04-RESEARCH-ADDENDUM §2(K1: gksdud 번들 ID), §4(Karabiner-Elements 16.1.0·macOS 27.2 실측:
/// org.pqrs.Karabiner-Core-Service, org.pqrs.Karabiner-NotificationWindow, 설정 창이 열렸을 때
/// org.pqrs.Karabiner-Elements.Settings). 15.7.0 이전에는 핵심 프로세스가 karabiner_grabber였으므로(K2)
/// 접두어 org.pqrs.Karabiner를 보조로 본다.
/// 구현 뒤 이 Mac에서 NSWorkspace.runningApplications 결과를 다시 확인한다(실기기 확인 넘김).
public enum ConflictApps {
    public static let karabinerName = "Karabiner-Elements"
    public static let gksdudName = "gksdud"

    static let karabinerCoreID = "org.pqrs.Karabiner-Core-Service"
    static let karabinerPrefix = "org.pqrs.Karabiner"
    static let gksdudID = "io.gksdud.inputswitch"

    /// 경고 문구와 같은 순서(Karabiner-Elements, gksdud)로 이름을 낸다. 같은 앱은 한 번.
    public static func detected(runningBundleIDs: [String]) -> [String] {
        var out: [String] = []
        if runningBundleIDs.contains(where: { $0 == karabinerCoreID || $0.hasPrefix(karabinerPrefix) }) {
            out.append(karabinerName)
        }
        if runningBundleIDs.contains(gksdudID) { out.append(gksdudName) }
        return out
    }
}
