import AppKit
import Combine
import FnCapsCore
import SwiftUI

/// 창은 하나뿐. 열려 있는 동안만 .regular, 닫으면 .accessory로 복귀한다.
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let model: AppModel
    private let reports: ReportController
    private let window: NSWindow
    private let host: NSHostingController<SettingsRootView>
    /// 처음 설정 진행 저장(04.4 D-18). 시험·렌더는 빈 suite를 넘길 수 있다.
    private let defaults: UserDefaults
    let ui: SettingsUIState
    private var centered = false
    private var cancellables = Set<AnyCancellable>()

    init(model: AppModel, updates: UpdateController, reports: ReportController,
         defaults: UserDefaults = .standard) {
        self.model = model
        self.reports = reports
        self.defaults = defaults
        ui = SettingsUIState(firstRun: FirstRunSetup(defaults: defaults))
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: DS.s(690), height: DS.s(675)),
            styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: true)
        host = NSHostingController(
            rootView: SettingsRootView(model: model, ui: ui, updates: updates, reports: reports))
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
        // 04.4 UAT U-9: 처음 설정 동안은 단계 화면에 맞게 창을 줄이고, 나가면 평소 크기로 돌린다.
        ui.$setupMode
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] setup in self?.applyWindowSize(setup: setup) }
            .store(in: &cancellables)
        // 후보 [이 설정 사용하기] 확인 창(D-09). 요청은 SettingsUIState가 한 번에 하나만 받는다.
        ui.$pendingCandidate
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] plan in self?.presentCandidateAlert(plan) }
            .store(in: &cancellables)
        // 5단계 목록 [마침] 확인 창(04.5 UAT F-5).
        ui.$finishPromptRequested
            .filter { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.presentFinishAlert() }
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
            AppLog.info("candidate alert result=\(apply ? "apply" : "cancel") unused=\(preview?.unusedCount ?? 0) emptyChords=\(emptyIDs.count)")
            guard apply else { return }
            // WR-05: 적용되지 않았으면(목록을 아직 못 읽음) 이동도, 처음 설정 마침도 하지 않는다.
            guard self.model.applyCandidate(plan) else { return }
            self.ui.selectedPage = .keys
            // D-15: 처음 설정 중 적용하면 마치고 「키와 언어」로 간다.
            if self.ui.setupMode { self.ui.finishSetup() }
            if !emptyIDs.isEmpty {
                self.ui.keysChordHighlight = Set(emptyIDs)
                self.ui.keysAnchor = "keys.assigned"
            }
        }
    }

    /// 5단계 목록에서 [마침]: 권장 배치는 도움말 > 배치 > FnCaps 권장에서 다시 볼 수 있다고 알린다.
    /// [마침]이면 처음 설정을 마치고, [취소]면 5단계에 남는다. 창이 안 보이거나 다른 시트가 있으면 요청을 버린다.
    private func presentFinishAlert() {
        guard window.isVisible, ui.windowVisible, window.attachedSheet == nil else {
            ui.finishPromptRequested = false
            return
        }
        let path = [L("sidebar.help"), L("help.setup.title"), L("help.setup.segment.fncaps")].joined(separator: " > ")
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = L("setup.finish.confirm.title")
        alert.informativeText = LF("setup.finish.confirm.body", path)
        alert.addButton(withTitle: L("setup.finish"))
        let cancel = alert.addButton(withTitle: L("help.cand.confirm.cancel"))
        cancel.keyEquivalent = "\u{1b}"
        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self else { return }
            self.ui.finishPromptRequested = false
            let finish = response == .alertFirstButtonReturn
            AppLog.info("setup finish alert result=\(finish ? "finish" : "cancel")")
            if finish, self.ui.setupMode { self.ui.finishSetup() }
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

    /// 평소 690×675, 처음 설정 600×500(내용 폭 560 + 좌우 여백). 창 왼쪽 위 모서리는 그대로 둔다.
    private func applyWindowSize(setup: Bool) {
        let size = setup
            ? NSSize(width: DS.s(600), height: DS.s(500))
            : NSSize(width: DS.s(690), height: DS.s(675))
        window.contentMinSize = size
        window.contentMaxSize = size
        let content = window.contentRect(forFrameRect: window.frame)
        guard content.size != size else { return }
        let top = window.frame.maxY
        var frame = window.frameRect(forContentRect: NSRect(origin: content.origin, size: size))
        frame.origin.y = top - frame.height
        window.setFrame(frame, display: true, animate: window.isVisible)
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
            // 쪽을 지정한 열기는 평소 창으로 연다. 처음 설정 중이었다면 [나중에]와 같이 left를 기록한다(D-16).
            if ui.setupMode { ui.leaveSetup() }
            ui.selectedPage = page
        } else if ui.firstRun.opensInSetupMode {
            ui.enterSetup(globeOK: !model.snapshot.globeNotice)
        } else if model.snapshot.permissionPanel != .hidden {
            ui.selectedPage = .general
        }
        NSApp.setActivationPolicy(.regular)
        if !centered {
            window.center()
            centered = true
        }
        bringToFront()
        ui.windowVisible = true
        model.setWindowOpen(true)
        AppLog.info("window show setup=\(ui.setupMode) step=\(ui.setupStep)")
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

    /// 사용자가 창을 닫으면 [나중에]와 같다(orchestrator decision 4). 앱 종료·재시작은 이 경로를 지나지 않아
    /// left를 쓰지 않으므로, 권한 뒤 자동 재시작에서도 처음 설정이 이어진다(D-18).
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if ui.setupMode {
            ui.leaveSetup()
            AppLog.info("setup left via=close")
        }
        return true
    }

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
        NSApp.setActivationPolicy(.accessory)
        model.setWindowOpen(false)
    }
}
