import AppKit
import FnCapsCore
import FnCapsSystem

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var model: AppModel!
    private var updates: UpdateController!
    private var reports: ReportController!
    private var window: SettingsWindowController!
    private var statusItem: StatusItemController!
    /// 처음 설정 창과 그 화면 상태(08.1 D-01, D-03). 설정 창과 함께 열 수 있고 진행 값을 함께 본다.
    private var onboarding: OnboardingUIState!
    private var onboardingWindow: OnboardingWindowController!
    /// 설정 창과 처음 설정 창의 활성화 정책을 합산한다(08.1 D-03).
    private var presence: WindowPresence!
    /// 자동 확인이 중요 표시를 찾았을 때 띄우는 창 하나(D-14, D-19-2). 시작 시각으로 포커스 규칙을 정한다.
    private var importantWindow: ImportantUpdateWindowController!

    /// 로그인 자동 실행인지. 실행을 알리는 Apple 이벤트('oapp')의 keyAEPropData가 keyAELaunchedAsLogInItem이면
    /// 로그인 실행이다. 'oapp'이 아니거나 이벤트가 없으면 판단하지 않는다(nil). willFinish 시점에 이벤트가
    /// 없을 때가 있어(2026-11-11 실기: login=unknown) didFinish에서 한 번 더 읽는다.
    private var launchedAsLoginItem: Bool?
    private var launchEventNote = "none"

    private func readLaunchEvent(_ stage: String) {
        guard launchedAsLoginItem == nil,
              let event = NSAppleEventManager.shared().currentAppleEvent else { return }
        let value = event.paramDescriptor(forKeyword: AEKeyword(keyAEPropData))?.enumCodeValue
        launchEventNote = "\(stage):\(Self.fourCC(event.eventID)):\(value.map(Self.fourCC) ?? "-")"
        guard event.eventID == AEEventID(kAEOpenApplication) else { return }
        launchedAsLoginItem = value == OSType(keyAELaunchedAsLogInItem)
    }

    private static func fourCC(_ code: UInt32) -> String {
        let bytes = [24, 16, 8, 0].map { UInt8((code >> $0) & 0xFF) }
        return String(bytes: bytes, encoding: .macOSRoman) ?? String(code)
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        readLaunchEvent("will")
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        readLaunchEvent("did")
        // 시작 시각 하나로 60초 활성화 예외를 정한다(D-19-2). 새 타이머는 만들지 않는다.
        let launchedAt = Date()
        model = AppModel()
        updates = UpdateController(defaults: .standard)
        importantWindow = ImportantUpdateWindowController(updates: updates, launchedAt: launchedAt)
        model.start()
        updates.startAutomatic()
        reports = ReportController(defaults: .standard)
        // 처음 설정 상태는 한 벌만 만들어 처음 설정 창과 설정 창 사이드바가 함께 본다(08.1 D-03).
        // AppModel.start()가 시드를 끝낸 뒤에 읽는다.
        onboarding = OnboardingUIState(firstRun: FirstRunSetup(defaults: .standard))
        // 두 창의 활성화 정책은 이 하나가 합산한다(08.1 D-03). model 생성 뒤에 만든다.
        presence = WindowPresence(model: model)
        onboardingWindow = OnboardingWindowController(model: model, ui: onboarding, presence: presence) { [weak self] highlight in
            self?.window.showKeys(highlight: highlight)
        }
        let restarted = CommandLine.arguments.contains(AppRestart.showSettingsArgument)
        window = SettingsWindowController(
            model: model, updates: updates, reports: reports,
            onboarding: onboarding, presence: presence,
            openOnboarding: { [weak self] in self?.onboardingWindow.show() })
        statusItem = StatusItemController(model: model, updates: updates, onboarding: onboarding, openSettings: { [weak self] page in
            // 메뉴가 닫힌 뒤에 연다. 메뉴 추적 중에 활성화하면 창이 뒤에 남을 때가 있다.
            DispatchQueue.main.async {
                guard let self else { return }
                // 창이 열려 있으면 「새 버전」 줄은 그 창을 앞으로 가져온다(D-19-4). 줄 모양은 그대로다.
                if page == .about, self.importantWindow.isOpen {
                    self.importantWindow.bringToFront()
                } else {
                    self.window.show(page: page)
                }
            }
        }, openOnboarding: { [weak self] in
            // 「처음 설정 계속…」도 같은 이유로 메뉴가 닫힌 뒤에 연다.
            DispatchQueue.main.async { self?.onboardingWindow.show() }
        })
        installMainMenu()
        // 처음 실행·재시작(재설정 버튼을 봐야 함)·직접 연 실행은 창을 띄운다. 로그인 자동 실행만 조용히 둔다.
        AppLog.info("launch first=\(model.isFirstLaunch) restarted=\(restarted) login=\(launchedAsLoginItem.map(String.init) ?? "unknown") event=\(launchEventNote) setup=\(onboarding.firstRun.opensInSetupMode)")
        if LaunchWindowPolicy.shouldShow(firstLaunch: model.isFirstLaunch, restarted: restarted,
                                         loginItem: launchedAsLoginItem) {
            showLaunchWindow()
        }
        // 업데이트 도우미가 띄운 실행이면 여기서 영수증에 pid를 남긴다(D-08).
        UpdateReceipt.writeIfRequested()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showLaunchWindow()
        return true
    }

    /// 시작·다시 열기의 창 하나: 처음 설정 대상이고 아직 나가지 않았으면 처음 설정 창, 아니면 설정 창.
    /// 두 창을 함께 열지 않는다(08.1 UI-SPEC 「열기」 표 첫 행). 로그인 항목 실행은 호출부가 거른다.
    private func showLaunchWindow() {
        if onboarding.firstRun.opensInSetupMode {
            onboardingWindow.show()
        } else {
            window.show()
        }
    }

    /// 종료 전에 Caps 경로가 바꾼 시스템 값을 되돌린다. 결과와 무관하게 항상 종료에 답한다
    /// (취소하면 로그아웃을 막고 복원과 경합한다). 실패하면 기록을 남긴 채 종료하고 다음 실행이 복구한다.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        model.caps.beginTermination()
        guard model.caps.needsRestore else { return .terminateNow }
        var replied = false
        var returned = false
        let reply = {
            guard !replied else { return }
            replied = true
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        model.caps.restore(force: true) { _ in
            if returned { reply() } else { replied = true }
        }
        if replied { return .terminateNow }
        returned = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            if !replied { AppLog.info("caps restore result=timeout") }
            reply()
        }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.shutdown()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

    private func installMainMenu() {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(title: L("menu.quit"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)

        // 메모 줄(D-33)에서 표준 편집 단축키가 되도록 편집 메뉴를 둔다. 대상은 첫 응답자 사슬(nil).
        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: L("menu.edit"))
        editMenu.addItem(NSMenuItem(title: L("menu.undo"), action: Selector(("undo:")), keyEquivalent: "z"))
        let redo = NSMenuItem(title: L("menu.redo"), action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(redo)
        editMenu.addItem(.separator())
        editMenu.addItem(NSMenuItem(title: L("menu.cut"), action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: L("menu.copy"), action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: L("menu.paste"), action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: L("menu.selectAll"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)

        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: L("window.title"))
        windowMenu.addItem(NSMenuItem(title: L("menu.closeWindow"), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
        windowItem.submenu = windowMenu
        mainMenu.addItem(windowItem)

        NSApp.mainMenu = mainMenu
    }
}
