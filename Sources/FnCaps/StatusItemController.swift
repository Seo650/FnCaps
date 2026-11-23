import AppKit
import Combine
import FnCapsCore
import SwiftUI

/// 메뉴 막대 아이콘과 메뉴. 아이콘 가시성은 항상 snapshot에서 명시 설정한다(D-10).
/// 처음 설정이 진행 중이면 「처음 설정 계속…」 줄을 「설정 열기…」 바로 위에 둔다(08.1 D-04).
final class StatusItemController: NSObject, NSMenuDelegate {
    private let model: AppModel
    private let updates: UpdateController?
    private let onboarding: OnboardingUIState
    private let openSettings: (SettingsPage?) -> Void
    private let openOnboarding: () -> Void
    private let item: NSStatusItem
    private let menu = NSMenu()
    private let onImage: NSImage?
    private let permissionImage: NSImage?
    private var cancellables = Set<AnyCancellable>()
    private var visibilityObservation: NSKeyValueObservation?
    private var applyingVisibility = false

    init(model: AppModel, updates: UpdateController? = nil,
         onboarding: OnboardingUIState,
         openSettings: @escaping (SettingsPage?) -> Void,
         openOnboarding: @escaping () -> Void) {
        self.model = model
        self.updates = updates
        self.onboarding = onboarding
        self.openSettings = openSettings
        self.openOnboarding = openOnboarding
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.autosaveName = "FnCapsStatusItem"
        onImage = Bundle.main.image(forResource: "on")
        permissionImage = Bundle.main.image(forResource: "permission")
        super.init()
        onImage?.isTemplate = true
        permissionImage?.isTemplate = true
        menu.autoenablesItems = false
        menu.delegate = self
        item.menu = menu

        model.$snapshot
            .removeDuplicates()
            .sink { [weak self] in self?.apply($0) }
            .store(in: &cancellables)
        // 새 버전 알림 줄(D-45 후속, 2026-11-08 사용자 요청). 확인 결과가 바뀌면 메뉴를 다시 짠다.
        updates?.$phase
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.rebuildMenu(self.model.snapshot)
            }
            .store(in: &cancellables)
        // 처음 설정 상태가 바뀌면(단계 이동·마치기·나가기) 같은 실행 차례에 메뉴를 다시 짠다(UI-SPEC 「메뉴 줄」).
        // receive(on:)을 걸지 않아야 마친 직후 줄이 남지 않는다.
        onboarding.$revision
            .removeDuplicates()
            .sink { [weak self] _ in
                guard let self else { return }
                self.rebuildMenu(self.model.snapshot)
            }
            .store(in: &cancellables)

        visibilityObservation = item.observe(\.isVisible, options: [.new]) { [weak self] _, change in
            guard let self, !self.applyingVisibility, change.newValue == false,
                  self.model.snapshot.trusted else { return }
            DispatchQueue.main.async { self.model.setIconHidden(true) }
        }
    }

    private func apply(_ snapshot: AppSnapshot) {
        if let button = item.button {
            let image = snapshot.status.iconName == "permission" ? permissionImage : onImage
            if let image {
                button.image = image
                button.title = ""
            } else {
                button.image = nil
                button.title = "FnCaps"
                AppLog.info("icon missing")
            }
            button.setAccessibilityLabel(LF("accessibility.icon", L(snapshot.status.copyKey)))
        }
        applyingVisibility = true
        item.isVisible = snapshot.iconVisible
        applyingVisibility = false
        rebuildMenu(snapshot)
    }

    /// 확정 순서(D-33): (새 버전·새 소스 알림) / 상태 줄 / 끄기·켜기 /
    /// 설정 열기… / 문제 알리기… / 키 복구 / 메뉴 막대 아이콘 숨기기 / 종료.
    /// 숨긴 뒤에는 Spotlight 등으로 직접 열면 창이 뜬다(AppDelegate).
    private func rebuildMenu(_ snapshot: AppSnapshot) {
        menu.removeAllItems()

        // 새 버전이 있으면 맨 위에 알림 줄. 누르면 「FnCaps 정보」 쪽을 연다(업데이트 버튼이 있는 곳).
        if let version = availableVersion {
            let title = LF("about.update.available", version)
            let item = NSMenuItem(title: title, action: #selector(openAboutPage), keyEquivalent: "")
            item.attributedTitle = Self.dotted(title, dot: NSColor(DS.warn), text: .labelColor)
            item.target = self
            menu.addItem(item)
            menu.addItem(.separator())
        }

        if let title = snapshot.newSourcesMenuTitle {
            let fresh = NSMenuItem(title: title, action: #selector(openKeysPage), keyEquivalent: "")
            fresh.attributedTitle = Self.dotted(title, dot: NSColor(DS.warn), text: .labelColor)
            fresh.target = self
            menu.addItem(fresh)
            menu.addItem(.separator())
        }

        // 상태 줄. Caps Lock 사용 중이면 그 상태를 보인다(따로 있던 Caps 점유 줄을 대신한다, WR-06).
        let blocked = snapshot.status == .running && snapshot.capsBlocked
        let statusTitle = blocked ? L("status.capsBlocked") : L(snapshot.status.copyKey)
        let status = NSMenuItem(title: statusTitle, action: nil, keyEquivalent: "")
        status.attributedTitle = Self.dotted(statusTitle, dot: statusDotColor(snapshot), text: .labelColor)
        status.isEnabled = false
        menu.addItem(status)

        let toggleTitle = L(MenuToggle.titleKey(enabled: snapshot.enabled))
        let toggle = NSMenuItem(title: toggleTitle, action: #selector(toggleEnabled), keyEquivalent: "")
        toggle.target = self
        toggle.isEnabled = snapshot.trusted
        menu.addItem(toggle)

        menu.addItem(.separator())

        // 보이는 조건은 사이드바 「처음 설정 n/5」와 같다(08.1 D-04). 처음 설정은 선택 사항이라
        // 맨 위 알림 자리에 두지 않고 점·단축키 없이 평범한 줄로 둔다(UI-SPEC 「메뉴 줄」).
        if onboarding.firstRun.isActive {
            let resume = NSMenuItem(title: L("menu.resumeSetup"), action: #selector(openOnboardingAction), keyEquivalent: "")
            resume.target = self
            menu.addItem(resume)
        }

        let settings = NSMenuItem(title: L("menu.openSettings"), action: #selector(openSettingsAction), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        let report = NSMenuItem(title: L("menu.report"), action: #selector(openReportPage), keyEquivalent: "")
        report.target = self
        menu.addItem(report)

        // 복구는 hidutil 매핑과 입력 소스 단축키만 되돌리므로 접근성 권한 없이도 켠다.
        let restore = NSMenuItem(title: L("menu.restore"), action: #selector(restoreKeys), keyEquivalent: "")
        restore.target = self
        menu.addItem(restore)

        menu.addItem(.separator())

        let hide = NSMenuItem(title: L("menu.hideIcon"), action: #selector(hideIcon), keyEquivalent: "")
        hide.target = self
        menu.addItem(hide)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: L("menu.quit"), action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    /// 메뉴가 열리기 직전에 다시 짠다. 처음 설정 상태가 다른 길로 바뀌어도 줄의 유무가 맞는다.
    func menuNeedsUpdate(_ menu: NSMenu) {
        rebuildMenu(model.snapshot)
    }

    private func statusDotColor(_ snapshot: AppSnapshot) -> NSColor {
        switch snapshot.status {
        case .running: return snapshot.capsBlocked ? NSColor(DS.warn) : NSColor(DS.ok)
        case .permissionNeeded: return NSColor(DS.warn)
        case .off, .waiting: return .secondaryLabelColor
        }
    }

    /// 색 「● 」 글자 + 제목. 이미지가 아니라 글자로 그린다(PA10: SDK 27 링크에서 메뉴 항목 이미지는 숨는다).
    private static func dotted(_ title: String, dot: NSColor, text: NSColor) -> NSAttributedString {
        let font = NSFont.menuFont(ofSize: 0)
        let result = NSMutableAttributedString(
            string: "\u{25CF} ", attributes: [.font: font, .foregroundColor: dot])
        result.append(NSAttributedString(string: title, attributes: [.font: font, .foregroundColor: text]))
        return result
    }

    @objc private func toggleEnabled() { model.setEnabled(!model.snapshot.enabled) }
    /// 확인 창 뒤에 숨긴다. 메뉴 막대 앱이라 먼저 앞으로 나와야 창이 다른 창 뒤에 숨지 않는다.
    @objc private func hideIcon() {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = L("menu.hideIcon.confirm")
        alert.informativeText = L("menu.hideIcon.detail")
        alert.addButton(withTitle: L("menu.hideIcon.button"))
        let cancel = alert.addButton(withTitle: L("advanced.reset.cancel"))
        cancel.keyEquivalent = "\u{1b}"
        if alert.runModal() == .alertFirstButtonReturn { model.setIconHidden(true) }
    }
    @objc private func openSettingsAction() { openSettings(nil) }
    /// 메뉴가 닫힌 뒤 처음 설정 창을 연다(AppDelegate가 DispatchQueue.main.async로 잇는다).
    @objc private func openOnboardingAction() { openOnboarding() }
    @objc private func openKeysPage() { openSettings(.keys) }
    @objc private func openAboutPage() { openSettings(.about) }
    @objc private func openReportPage() { openSettings(.report) }
    /// 확인 창 없이 시스템 상태를 되돌린다(UI-SPEC D-33).
    @objc private func restoreKeys() { model.restoreSystemState() }

    private var availableVersion: String? {
        if case .done(.available(let version, _)) = updates?.phase { return version }
        return nil
    }
    @objc private func quitApp() { NSApp.terminate(nil) }
}
