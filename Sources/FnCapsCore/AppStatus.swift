import Foundation

/// One app state at a time. Priority: permission missing > off > both key lists empty > running.
public enum AppStatus: String, Equatable, Sendable {
    case permissionNeeded, off, waiting, running

    public static func resolve(
        trusted: Bool, enabled: Bool, hasActiveList: Bool, hasShortcuts: Bool = false
    ) -> AppStatus {
        if !trusted { return .permissionNeeded }
        if !enabled { return .off }
        if !(hasActiveList || hasShortcuts) { return .waiting }
        return .running
    }

    /// 사선 아이콘 = FnCaps가 키를 처리하지 않는 상태(권한 필요, 꺼짐). 사용자 요청 2026-11-08.
    public var iconName: String { (self == .permissionNeeded || self == .off) ? "permission" : "on" }

    public var copyKey: String {
        switch self {
        case .running: return "status.running"
        case .permissionNeeded: return "status.permission"
        case .waiting: return "status.waiting"
        case .off: return "status.off"
        }
    }
}

/// The tap exists only while trusted, enabled and at least one key list or assigned shortcut is present.
/// If any condition breaks the tap must be removed, shrinking the window in which a revoked permission
/// could freeze input. Without this the tap is never installed when only assigned shortcuts exist
/// and every shortcut is dead (04-RESEARCH-SHORTCUTS §6-3).
public enum TapInstallPolicy {
    public static func shouldInstall(
        trusted: Bool, enabled: Bool, hasActiveList: Bool, hasShortcuts: Bool = false
    ) -> Bool {
        trusted && enabled && (hasActiveList || hasShortcuts)
    }
}

/// Menu bar icon may be hidden only while permission is granted (D-10).
public enum IconVisibility {
    public static func isVisible(hidden: Bool, trusted: Bool) -> Bool { !(hidden && trusted) }
}

/// macOS 27+ uses the "device control and data access" wording (D-08).
public enum PermissionGuide {
    public static func pathKey(osMajor: Int) -> String {
        osMajor >= 27 ? "permission.path.27" : "permission.path.legacy"
    }
}

/// Login item display state from `SMAppService.Status.rawValue`
/// (0 notRegistered, 1 enabled, 2 requiresApproval, 3 notFound).
/// `.notFound` is treated as plain off rather than "cannot register" (02-RESEARCH Pitfall 4).
public enum LoginItemPresentation: String, Equatable, Sendable {
    case on, off, requiresApproval, failed
    /// SMAppService .notFound(3). 04-RESEARCH-BUILD PA13: off와 따로 보인다.
    case notFound

    public static func from(rawStatus: Int, registerFailed: Bool) -> LoginItemPresentation {
        if rawStatus == 1 { return .on }
        if registerFailed { return .failed }
        if rawStatus == 2 { return .requiresApproval }
        if rawStatus == 3 { return .notFound }
        return .off
    }
}

/// Permission/tap polling cadence in seconds.
public enum PollInterval {
    public static func seconds(trusted: Bool, tapInstalled: Bool, windowOpen: Bool) -> TimeInterval {
        if !trusted || windowOpen { return 1 }
        if tapInstalled { return 2 }
        return 5
    }
}

/// 메뉴 토글 라벨. 라벨은 사용자 설정값만 따른다.
/// 상태(권한 없음 등)는 상태 줄과 흐림으로 알린다 (UAT D3).
public enum MenuToggle {
    public static func titleKey(enabled: Bool) -> String {
        enabled ? "menu.turnOff" : "menu.turnOn"
    }
}

/// 권한 버튼 동작. 첫 클릭은 시스템 자물쇠 프롬프트만 띄운다 (사용자 요청, UAT A4·D4).
/// 프롬프트가 뜨지 않는 경우를 위해 두 번째 클릭부터 설정 화면을 연다.
public enum PermissionButton {
    public enum Action: Equatable, Sendable { case prompt, openSettings }

    public static func action(didRequestPrompt: Bool) -> Action {
        didRequestPrompt ? .openSettings : .prompt
    }
}
