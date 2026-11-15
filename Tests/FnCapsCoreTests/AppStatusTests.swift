import Testing
@testable import FnCapsCore

@Suite struct AppStatusTests {
    @Test func resolvePriority() {
        #expect(AppStatus.resolve(trusted: false, enabled: true, hasActiveList: true) == .permissionNeeded)
        #expect(AppStatus.resolve(trusted: false, enabled: false, hasActiveList: false) == .permissionNeeded)
        #expect(AppStatus.resolve(trusted: true, enabled: false, hasActiveList: true) == .off)
        #expect(AppStatus.resolve(trusted: true, enabled: true, hasActiveList: false) == .waiting)
        #expect(AppStatus.resolve(trusted: true, enabled: true, hasActiveList: true) == .running)
    }

    @Test func iconAndCopyKeys() {
        #expect(AppStatus.permissionNeeded.iconName == "permission")
        #expect(AppStatus.off.iconName == "permission")
        #expect(AppStatus.waiting.iconName == "on")
        #expect(AppStatus.running.iconName == "on")
        #expect(AppStatus.running.copyKey == "status.running")
        #expect(AppStatus.permissionNeeded.copyKey == "status.permission")
        #expect(AppStatus.waiting.copyKey == "status.waiting")
        #expect(AppStatus.off.copyKey == "status.off")
    }

    @Test func tapInstallPolicy() {
        #expect(TapInstallPolicy.shouldInstall(trusted: true, enabled: true, hasActiveList: true))
        #expect(!TapInstallPolicy.shouldInstall(trusted: false, enabled: true, hasActiveList: true))
        #expect(!TapInstallPolicy.shouldInstall(trusted: true, enabled: false, hasActiveList: true))
        #expect(!TapInstallPolicy.shouldInstall(trusted: true, enabled: true, hasActiveList: false))
    }

    @Test func tapInstallsWithOnlyOneListActive() {
        // modeCount 조건 제거: Caps만 있거나 fn만 있어도 hasActiveList면 설치된다.
        let capsOnly = KeyLayout(caps: [Fx.abc.id], fn: [], sources: [Fx.abc, Fx.ko2], rule: .nextAfterLast)
        let fnOnly = KeyLayout(caps: [], fn: [Fx.ko2.id], sources: [Fx.abc, Fx.ko2], rule: .nextAfterLast)
        #expect(TapInstallPolicy.shouldInstall(trusted: true, enabled: true, hasActiveList: capsOnly.hasActiveList))
        #expect(TapInstallPolicy.shouldInstall(trusted: true, enabled: true, hasActiveList: fnOnly.hasActiveList))
        #expect(!TapInstallPolicy.shouldInstall(trusted: true, enabled: true, hasActiveList: KeyLayout.empty.hasActiveList))
    }

    @Test func iconVisibility() {
        #expect(IconVisibility.isVisible(hidden: false, trusted: false))
        #expect(IconVisibility.isVisible(hidden: false, trusted: true))
        #expect(!IconVisibility.isVisible(hidden: true, trusted: true))
        #expect(IconVisibility.isVisible(hidden: true, trusted: false))
    }

    @Test func permissionGuidePath() {
        #expect(PermissionGuide.pathKey(osMajor: 27) == "permission.path.27")
        #expect(PermissionGuide.pathKey(osMajor: 28) == "permission.path.27")
        #expect(PermissionGuide.pathKey(osMajor: 26) == "permission.path.legacy")
        #expect(PermissionGuide.pathKey(osMajor: 14) == "permission.path.legacy")
    }

    @Test func loginItemPresentation() {
        #expect(LoginItemPresentation.from(rawStatus: 1, registerFailed: false) == .on)
        #expect(LoginItemPresentation.from(rawStatus: 0, registerFailed: false) == .off)
        // 04-RESEARCH-BUILD PA13: 02-RESEARCH Pitfall 4의 「notFound는 off로」 결정을 바꿔 따로 보인다.
        // (build/ 폴더에서 실행하면 늘 notFound일 수 있다. 사용자 확인 필요로 넘김)
        #expect(LoginItemPresentation.from(rawStatus: 3, registerFailed: false) == .notFound)
        #expect(LoginItemPresentation.from(rawStatus: 2, registerFailed: false) == .requiresApproval)
        #expect(LoginItemPresentation.from(rawStatus: 9, registerFailed: false) == .off)
        #expect(LoginItemPresentation.from(rawStatus: 0, registerFailed: true) == .failed)
        #expect(LoginItemPresentation.from(rawStatus: 3, registerFailed: true) == .failed)
        #expect(LoginItemPresentation.from(rawStatus: 1, registerFailed: true) == .on)
    }

    @Test func pollInterval() {
        #expect(PollInterval.seconds(trusted: false, tapInstalled: false, windowOpen: false) == 1)
        #expect(PollInterval.seconds(trusted: true, tapInstalled: false, windowOpen: true) == 1)
        #expect(PollInterval.seconds(trusted: true, tapInstalled: true, windowOpen: false) == 2)
        #expect(PollInterval.seconds(trusted: true, tapInstalled: false, windowOpen: false) == 5)
    }

    @Test func menuToggleTitle() {
        #expect(MenuToggle.titleKey(enabled: false) == "menu.turnOn")
        #expect(MenuToggle.titleKey(enabled: true) == "menu.turnOff")
        #expect(AppStatus.resolve(trusted: false, enabled: false, hasActiveList: true) == .permissionNeeded)
        #expect(MenuToggle.titleKey(enabled: false) == "menu.turnOn")
    }

    @Test func permissionButtonAction() {
        #expect(PermissionButton.action(didRequestPrompt: false) == .prompt)
        #expect(PermissionButton.action(didRequestPrompt: true) == .openSettings)
    }
}

@Suite struct AssignedShortcutStatusTests {
    @Test func tapInstallsWithOnlyAssignedShortcuts() {
        // 지정 단축키가 하나 이상이면 Caps·fn이 모두 비어도 탭을 설치한다(연구 §6-3).
        #expect(TapInstallPolicy.shouldInstall(trusted: true, enabled: true, hasActiveList: false, hasShortcuts: true))
        #expect(!TapInstallPolicy.shouldInstall(trusted: false, enabled: true, hasActiveList: false, hasShortcuts: true))
        #expect(!TapInstallPolicy.shouldInstall(trusted: true, enabled: false, hasActiveList: false, hasShortcuts: true))
    }

    @Test func runningWithOnlyAssignedShortcuts() {
        #expect(AppStatus.resolve(trusted: true, enabled: true, hasActiveList: false, hasShortcuts: true) == .running)
        #expect(AppStatus.resolve(trusted: true, enabled: true, hasActiveList: true, hasShortcuts: false) == .running)
    }

    @Test func waitingWithoutKeysOrShortcuts() {
        #expect(AppStatus.resolve(trusted: true, enabled: true, hasActiveList: false) == .waiting)
        #expect(AppStatus.resolve(trusted: true, enabled: true, hasActiveList: false, hasShortcuts: false) == .waiting)
        #expect(!TapInstallPolicy.shouldInstall(trusted: true, enabled: true, hasActiveList: false, hasShortcuts: false))
    }
}
