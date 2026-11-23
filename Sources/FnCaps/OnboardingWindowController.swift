import AppKit
import Combine
import FnCapsCore
import SwiftUI

/// 처음 설정 창(08.1 D-01, D-02). 창은 하나뿐이고, 이미 열려 있으면 새로 만들지 않고 앞으로만 가져온다.
/// 틀은 중요 업데이트 창과 같은 `AuxiliaryWindow.make`를 쓰고, 내용 크기는 모든 단계에서 `DS.s(600)×DS.s(500)`로
/// 고정한다(크기 조절·확대 불가). 처음 만들 때만 가운데로 옮기고 같은 실행 안에서는 사용자가 옮긴 자리를 지킨다.
///
/// - 여는 길이 모두 사용자 행동이므로(첫 실행, 권한 허용 뒤 자동 재시작, 사이드바·메뉴 클릭) 중요 업데이트 창의
///   60초 예외를 따르지 않고 열 때마다 활성화한다.
/// - 닫기 버튼·⌘W·Esc는 [나중에]와 같다: `markLeft()` 뒤 이 창만 닫는다. 앱 종료·재시작은 이 경로를 지나지 않아
///   `left`를 쓰지 않는다(04.4 D-18).
/// - 후보 [이 설정 사용하기]와 [마침] 확인 시트는 설정 창이 아니라 이 창에 붙는다(D-07, D-09).
final class OnboardingWindowController: NSObject, NSWindowDelegate {
    private let model: AppModel
    private let ui: OnboardingUIState
    private let presence: WindowPresence
    /// 처음 설정을 마쳤을 때 부른다. 강조할 빈 단축키 칸을 넘긴다(D-07).
    private let onFinished: (Set<SourceID>) -> Void
    private var window: NSWindow?
    private var host: NSHostingController<OnboardingView>?
    private var centered = false
    private var cancellables = Set<AnyCancellable>()

    /// 창이 지금 보이는지.
    var isOpen: Bool { window?.isVisible ?? false }

    init(model: AppModel, ui: OnboardingUIState, presence: WindowPresence,
         onFinished: @escaping (Set<SourceID>) -> Void) {
        self.model = model
        self.ui = ui
        self.presence = presence
        self.onFinished = onFinished
        super.init()
        // 후보 [이 설정 사용하기] 확인 창(D-09). 요청은 OnboardingUIState가 한 번에 하나만 받는다.
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
        // 단계가 바뀌면 새 제목을 VoiceOver로 한 번 읽는다(UI-SPEC 「접근성과 키보드」).
        // receive(on:)을 걸지 않아야 창을 여는 순간(setupStep을 다시 저장하는 차례)을 창이 보이기 전에 거른다.
        ui.$setupStep
            .removeDuplicates()
            .sink { [weak self] step in self?.announceStep(step) }
            .store(in: &cancellables)
    }

    // MARK: 열기, 닫기

    /// 처음 설정 창을 저장된 단계로 연다. 열 때마다 활성화한다.
    func show() {
        let reused = window != nil
        if let window, window.isVisible {
            bringToFront()
            AppLog.info("setup window front")
            return
        }
        // 권한이 없으면 2단계로 연다(G-08.1-4). 이미 보이는 창은 위 분기에서 앞으로만 가져오고 단계를
        // 옮기지 않는다(보수적 선택: 보던 화면이 권한 변화로 갑자기 바뀌지 않게).
        ui.enterSetup(globeOK: !model.snapshot.globeNotice, needsGrant: model.snapshot.permissionPanel == .grant)
        let size = NSSize(width: DS.s(600), height: DS.s(500))
        if let window, let host {
            // 닫았다 다시 여는 경우: 창을 새로 만들지 않고 내용만 새 단계로 바꾼다.
            host.rootView = makeView()
            window.setContentSize(size)
        } else {
            let host = NSHostingController(rootView: makeView())
            host.sizingOptions = []
            let window = AuxiliaryWindow.make(identifier: "onboarding", title: L("setup.title"), contentSize: size, delegate: self, content: host)
            window.contentMinSize = size
            window.contentMaxSize = size
            self.window = window
            self.host = host
            if !centered {
                window.center()
                centered = true
            }
        }
        present()
        AppLog.info("setup window show step=\(ui.setupStep) reused=\(reused)")
    }

    /// [나중에]·Esc가 부른다. windowShouldClose가 markLeft를 남긴다.
    func close() {
        window?.performClose(nil)
    }

    private func makeView() -> OnboardingView {
        OnboardingView(
            model: model, ui: ui,
            close: { [weak self] in self?.close() },
            finish: { [weak self] in self?.finish(highlight: [], via: "direct") })
    }

    /// 처음 설정을 마치고 창을 닫은 뒤 설정 창을 「키와 언어」로 연다(D-07). 창 닫기는
    /// `performClose`가 아니라 `close`라 windowShouldClose를 지나지 않는다(markLeft를 쓰지 않는다).
    private func finish(highlight: Set<SourceID>, via: String) {
        ui.finishSetup()
        AppLog.info("setup finished via=\(via)")
        window?.close()
        onFinished(highlight)
    }

    /// 열 때마다 활성화한다(중요 업데이트 창의 60초 예외를 따르지 않는다). 설정 창 `show()`와 같은 방식이며,
    /// macOS 14의 협조적 활성화가 무시될 때를 대비해 두 번 더 올린다.
    /// 활성화 정책과 창 닫힘은 설정 창과 합산한다(08.1 D-03).
    private func present() {
        presence.opened(WindowPresence.setup)
        bringToFront()
        for delay in [0.15, 0.5] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, let window = self.window, window.isVisible, !window.isKeyWindow else { return }
                self.bringToFront(force: true)
            }
        }
    }

    /// 단계가 바뀌면 새 단계 제목을 VoiceOver로 한 번 읽는다. 창이 아직 안 보이는 열기 순간에는 알리지 않는다.
    private func announceStep(_ step: Int) {
        guard let window, window.isVisible else { return }
        NSAccessibility.post(element: window, notification: .announcementRequested, userInfo: [
            .announcement: L(Self.titleKey(step: step)),
            .priority: NSAccessibilityPriorityLevel.high.rawValue,
        ])
    }

    /// 단계별 제목 문구 키. 5단계 「직접 설정」 쪽도 5단계 목록과 같은 제목을 쓴다.
    private static func titleKey(step: Int) -> String {
        switch step {
        case 1: return "setup.welcome.title"
        case 2: return "settings.permission.title"
        case 3: return "setup.globe.title"
        case 4: return "setup.basics.title"
        default: return "setup.layout.title"
        }
    }

    /// 창을 맨 앞으로. force는 협조적 활성화가 무시됐을 때 쓰는 대비책이다.
    private func bringToFront(force: Bool = false) {
        if force {
            NSApp.activate(ignoringOtherApps: true)
        } else {
            NSApp.activate()
        }
        window?.orderFrontRegardless()
        window?.makeKeyAndOrderFront(nil)
    }

    // MARK: 시트

    /// D-09~D-11: 후보 적용 확인 시트. 창이 안 보이거나 다른 시트가 있으면 요청을 버린다(T-04.4-12).
    private func presentCandidateAlert(_ plan: GuidancePlan) {
        guard let window, window.isVisible, window.attachedSheet == nil else {
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
            AppLog.info("candidate alert result=\(apply ? "apply" : "cancel") unused=\(preview?.unusedCount ?? 0) emptyChords=\(emptyIDs.count) window=setup")
            guard apply else { return }
            // WR-05: 적용되지 않았으면(목록을 아직 못 읽음) 처음 설정을 마치지 않고 5단계에 남는다.
            guard self.model.applyCandidate(plan) else { return }
            self.finish(highlight: Set(emptyIDs), via: "candidate")
        }
    }

    /// 5단계 목록에서 [마침]: 배치를 고르지 않고 마칠지 묻는다(D-09).
    /// 기본(파랑, Return) 버튼은 「돌아가서 고르기」라 시트를 닫고 5단계에 남고, 강조 없는 둘째 버튼
    /// 「고르지 않고 마치기」만 처음 설정을 끝낸다. 창이 안 보이거나 다른 시트가 있으면 요청을 버린다.
    private func presentFinishAlert() {
        guard let window, window.isVisible, window.attachedSheet == nil else {
            ui.finishPromptRequested = false
            return
        }
        let path = [L("sidebar.help"), L("help.setup.title"), L("help.setup.segment.fncaps")].joined(separator: " > ")
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = L("setup.finish.confirm.title")
        alert.informativeText = LF("setup.finish.confirm.body", path)
        // D-09: 첫 버튼이 기본(파랑·Return·오른쪽 끝)이고, 둘째 버튼은 키가 없는 강조 없는 버튼이다.
        alert.addButton(withTitle: L("setup.finish.confirm.back"))
        let finish = alert.addButton(withTitle: L("setup.finish.confirm.finish"))
        finish.keyEquivalent = ""
        // NSAlert는 한 버튼에 Return과 Esc를 함께 줄 수 없다. 시트가 붙은 동안만 Esc를 돌아가기로 받는다(D-09, UI-SPEC).
        let alertWindow = alert.window
        let escMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.keyCode == 53, window.attachedSheet === alertWindow else { return event }
            window.endSheet(alertWindow, returnCode: .alertFirstButtonReturn)
            return nil
        }
        alert.beginSheetModal(for: window) { [weak self] response in
            // 시트가 닫히면 맨 먼저 감시자를 지운다(한 번만 등록한다).
            if let escMonitor { NSEvent.removeMonitor(escMonitor) }
            guard let self else { return }
            self.ui.finishPromptRequested = false
            if response == .alertFirstButtonReturn {
                AppLog.info("setup finish alert result=back")
            } else {
                AppLog.info("setup finish alert result=finish")
                self.finish(highlight: [], via: "alert")
            }
        }
    }

    // MARK: NSWindowDelegate

    /// 버튼을 흐리게 해도 제목 막대 두 번 클릭·창 메뉴로 zoom이 불린다. 여기서 막는다.
    func windowShouldZoom(_ window: NSWindow, toFrame newFrame: NSRect) -> Bool { false }

    /// 사용자가 창을 닫으면 [나중에]와 같다. 앱 종료·재시작은 이 경로를 지나지 않아 left를 쓰지 않으므로,
    /// 권한 뒤 자동 재시작에서도 같은 단계로 처음 설정이 이어진다(04.4 D-18).
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if ui.isActive {
            ui.leaveSetup()
            AppLog.info("setup left via=close")
        }
        return true
    }

    func windowWillClose(_ notification: Notification) {
        ui.pendingCandidate = nil
        ui.finishPromptRequested = false
        ui.setupBranch = false
        ui.setupCustomHover = false
        // 마지막 창이 닫힐 때만 .accessory로 돌아간다(08.1 D-03).
        presence.closed(WindowPresence.setup)
        AppLog.info("setup window closed")
    }
}
