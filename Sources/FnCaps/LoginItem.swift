import FnCapsCore
import Foundation
import ServiceManagement

/// SMAppService.mainApp 래퍼. .notFound/.notRegistered 상태라는 이유로 등록을 막지 않는다(Pitfall 4).
final class LoginItem {
    private(set) var lastRegisterFailed = false

    var rawStatus: Int { SMAppService.mainApp.status.rawValue }

    var presentation: LoginItemPresentation {
        .from(rawStatus: rawStatus, registerFailed: lastRegisterFailed)
    }

    @discardableResult
    func setEnabled(_ on: Bool) -> Bool {
        do {
            if on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            lastRegisterFailed = false
            return true
        } catch {
            let e = error as NSError
            AppLog.info("login register failed domain=\(e.domain) code=\(e.code)")
            if on { lastRegisterFailed = true }
            return false
        }
    }

    /// 첫 실행에서만 한 번 등록을 시도한다. 이후 사용자 선택은 덮어쓰지 않는다(D-11).
    func registerOnFirstLaunch(_ defaults: UserDefaults) {
        let done = defaults.object(forKey: "loginItemInitialized") as? Bool ?? false
        guard !done else { return }
        setEnabled(true)
        defaults.set(true, forKey: "loginItemInitialized")
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
