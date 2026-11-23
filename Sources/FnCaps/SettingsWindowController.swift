import AppKit
import Combine
import FnCapsCore
import SwiftUI

/// 설정 창은 하나뿐이다. 처음 설정은 별도 창(OnboardingWindowController)이다(08.1 D-01).
/// 활성화 정책은 WindowPresence가 처음 설정 창과 합산한다(08.1 D-03): 둘 다 닫혔을 때만 .accessory로 복귀한다.
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let model: AppModel
    private let reports: ReportController
    private let presence: WindowPresence
    private let window: NSWindow
    private let host: NSHostingController<SettingsRootView>
    let ui: SettingsUIState
    private var centered = false
    private var cancellables = Set<AnyCancellable>()

    init(model: AppModel, updates: UpdateController, reports: ReportController,
         onboarding: OnboardingUIState, presence: WindowPresence,
         openOnboarding: @escaping () -> Void) {
        self.model = model
        self.reports = reports
        self.presence = presence
        ui = SettingsUIState()
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: DS.s(690), height: DS.s(675)),
            styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: true)
        host = NSHostingController(
            rootView: SettingsRootView(model: model, ui: ui, onboarding: onboarding,
                                       openOnboarding: openOnboarding,
                                       updates: updates, reports: reports))
        super.init()
        // 제목 글자는 숨기고 창 메뉴·접근성용으로만 둔다. 제목 막대는 내용과 합친다(R2).
        window.title = L("window.title")
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        // 빈 도구 막대를 붙여 제목 막대를 시스템 설정처럼 높인다. 창 버튼이 모서리에서 안쪽으로 들어온다(UAT 2026-11-13).
        window.toolbar = NSToolbar(identifier: "settings")
        window.toolbarStyle = .unified
        window.isReleasedWhenClosed = false
        host.sizingOptions = []
        window.contentViewController = host
        // sizingOptions가 비어 있으면 contentViewController를 붙일 때 창이 뷰의 0x0 크기로 줄어든다(04-09 K2에서 발견).
        window.setContentSize(NSSize(width: DS.s(690), height: DS.s(675)))
        // 690×675(×DS.scale) 고정(2026-11-08 사용자 요청으로 Q1 「높이 조절」을 바꿈, 04.3 UAT M-3에서 520→675, 시스템 설정 창 높이에 맞춤). 넘치는 쪽은 쪽 안에서 스크롤한다.
        window.contentMinSize = NSSize(width: DS.s(690), height: DS.s(675))
        window.contentMaxSize = NSSize(width: DS.s(690), height: DS.s(675))
        // 닫기만 켠다. 최소화는 styleMask에서 빼고, 버튼은 흐리게 둔다(R2, W5).
        window.standardWindowButton(.miniaturizeButton)?.isEnabled = false
        window.standardWindowButton(.zoomButton)?.isEnabled = false
        window.delegate = self
        // 관찰: 앱 판정이 바뀌어도 창을 클릭해야 그려짐(02-20 2회차). 비활성 앱에서 그리기가 미뤄지는 것으로 추정.
        // @Published는 값이 바뀌기 전에 알리므로 다음 차례에 그린다. 활성 상태를 조건으로 쓰지 않는다.
        model.$snapshot
            .removeDuplicates()
            .sink { [weak self] snapshot in
                DispatchQueue.main.async {
                    self?.forceRedraw(status: snapshot.status)
                }
            }
            .store(in: &cancellables)
        // 「문제 알리기」 성공은 쪽이 아니라 창이 받는다. 쪽을 옮긴 뒤 결과가 와도 놓치지 않게
        // 창과 수명이 같은 여기서 구독한다(D-43, checker 지적 6).
        reports.$phase
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] phase in
                guard let self, case .done(.sent) = phase else { return }
                self.handleReportSent()
            }
            .store(in: &cancellables)
        // 후보 [이 설정 사용하기] 확인 창(D-09). 요청은 SettingsUIState가 한 번에 하나만 받는다.
        ui.$pendingCandidate
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] plan in self?.presentCandidateAlert(plan) }
            .store(in: &cancellables)
    }

    /// D-09~D-11: 후보 적용 확인 시트. 창이 안 보이거나 다른 시트가 있으면 요청을 버린다(T-04.4-12).
    private func presentCandidateAlert(_ plan: GuidancePlan) {
        guard window.isVisible, ui.windowVisible, window.attachedSheet == nil else {
            ui.pendingCandidate = nil
            return
        }
        let preview = model.candidatePreview(plan)
        var lines: [String] = []
        if let preview {
            if !preview.emptyChordIDs.isEmpty { lines.append(L("help.cand.confirm.chord")) }
            if preview.unusedCount >= 1 { lines.append(LF("help.cand.confirm.unused", preview.unusedCount)) }
        }
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = L("help.cand.confirm.title")
        alert.informativeText = lines.joined(separator: "\n")
        alert.addButton(withTitle: L("help.cand.confirm.apply"))
        let cancel = alert.addButton(withTitle: L("help.cand.confirm.cancel"))
        cancel.keyEquivalent = "\u{1b}"
        let emptyIDs = preview?.emptyChordIDs ?? []
        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self else { return }
            self.ui.pendingCandidate = nil
            let apply = response == .alertFirstButtonReturn
            AppLog.info("candidate alert result=\(apply ? "apply" : "cancel") unused=\(preview?.unusedCount ?? 0) emptyChords=\(emptyIDs.count) window=settings")
            guard apply else { return }
            // WR-05: 적용되지 않았으면(목록을 아직 못 읽음) 이동도 하지 않는다.
            guard self.model.applyCandidate(plan) else { return }
            self.ui.selectedPage = .keys
            if !emptyIDs.isEmpty {
                self.ui.keysChordHighlight = Set(emptyIDs)
                self.ui.keysAnchor = "keys.assigned"
            }
        }
    }

    /// 성공(.sent)을 받은 순간 글·메일을 곧바로 비운다(글을 비우면 canSend가 false라 같은 신고를 두 번 보낼 수 없다).
    /// 창이 보이면 확인 시트를 띄우고, 보내는 중에 창을 닫았으면 시트 없이 상태만 되돌린다(사용자 확정 2026-11-13).
    private func handleReportSent() {
        let hadEmail = !ui.reportEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        ui.reportMessage = ""
        ui.reportEmail = ""
        guard window.isVisible, ui.windowVisible else {
            AppLog.info("report sheet skipped visible=\(window.isVisible) uiVisible=\(ui.windowVisible)")
            reports.reset()
            return
        }
        AppLog.info("report sheet shown key=\(window.isKeyWindow)")
        let alert = NSAlert()
        alert.messageText = L("report.done.title")
        var body = L("report.done.body")
        if hadEmail { body += " " + L("report.done.reply") }
        alert.informativeText = body
        alert.addButton(withTitle: L("report.done.ok"))
        alert.beginSheetModal(for: window) { [weak self] _ in
            self?.reports.reset()
        }
    }

    private func forceRedraw(status: AppStatus) {
        guard window.isVisible else { return }
        host.view.needsLayout = true
        host.view.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        CATransaction.flush()
        AppLog.info("window sync status=\(status.rawValue)")
    }

    func show(page: SettingsPage? = nil) {
        if let page {
            ui.selectedPage = page
        } else if model.snapshot.permissionPanel != .hidden {
            ui.selectedPage = .general
        }
        // 활성화 정책은 처음 설정 창과 합산한다(08.1 D-03). 창을 앞으로 가져오기 전에 부른다.
        presence.opened(WindowPresence.settings)
        if !centered {
            window.center()
            centered = true
        }
        bringToFront()
        ui.windowVisible = true
        AppLog.info("window show page=\(ui.selectedPage.rawValue)")
        // 활성화 정책 전환은 비동기로 끝나고, macOS 14의 협조적 활성화는 다른 앱이 양보하지 않으면
        // activate()를 무시한다. 창이 키 창이 될 때까지 두 번 더 올린다(Spotlight·메뉴 막대·Dock 공통 경로).
        for delay in [0.15, 0.5] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, self.window.isVisible, !self.window.isKeyWindow else { return }
                AppLog.info("window front retry delay=\(delay)")
                self.bringToFront(force: true)
            }
        }
    }

    /// 처음 설정이 후보 적용·마침 뒤 부른다(D-07, UI-SPEC 「나가기」 표). 이미 열려 있으면 그 쪽으로 옮겨 앞으로 가져온다.
    /// 적용으로 정해야 하는 빈 단축키 칸이 있으면 함께 강조한다.
    func showKeys(highlight: Set<SourceID>) {
        show(page: .keys)
        guard !highlight.isEmpty else { return }
        ui.keysChordHighlight = highlight
        ui.keysAnchor = "keys.assigned"
    }

    /// 창을 맨 앞으로. force는 협조적 활성화가 무시됐을 때 쓰는 대비책이다(사용자가 직접 연 경우에만 불린다).
    private func bringToFront(force: Bool = false) {
        if force {
            NSApp.activate(ignoringOtherApps: true)
        } else {
            NSApp.activate()
        }
        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)
    }

    /// 버튼을 흐리게 해도 제목 막대 두 번 클릭·창 메뉴로 zoom이 불린다(W5). 여기서 막는다(W6).
    func windowShouldZoom(_ window: NSWindow, toFrame newFrame: NSRect) -> Bool { false }

    func windowDidBecomeKey(_ notification: Notification) { ui.windowVisible = true }
    func windowDidMiniaturize(_ notification: Notification) { ui.windowVisible = false }
    func windowDidDeminiaturize(_ notification: Notification) { ui.windowVisible = true }

    func windowWillClose(_ notification: Notification) {
        ui.windowVisible = false
        ui.memoText = ""
        // 글·메일은 저장하지 않는다(D-40). 창을 닫으면 비운다.
        ui.reportMessage = ""
        ui.reportEmail = ""
        // 오류 문구가 빈 입력 위에 남지 않게 한다. 보내는 중·성공 결과는 건드리지 않는다.
        reports.clearError()
        ui.helpAnchor = nil
        ui.keysAnchor = nil
        ui.keysChordHighlight = []
        ui.pendingCandidate = nil
        ui.newTagIDs = []
        // 다른 창이 열려 있으면 WindowPresence가 setWindowOpen(false)를 부르지 않으므로 녹화를 직접 끝낸다(T-04-68).
        model.endShortcutRecording()
        // 마지막 창이 닫힐 때만 .accessory로 돌아간다(08.1 D-03).
        presence.closed(WindowPresence.settings)
    }
}
