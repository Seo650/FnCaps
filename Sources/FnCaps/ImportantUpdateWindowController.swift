import AppKit
import Combine
import FnCapsCore
import SwiftUI

/// 자동 확인이 중요 표시가 있는 릴리스를 찾았을 때 띄우는 창(D-14, D-17). 창은 하나뿐이다.
///
/// - 자동 확인의 `importantOffer`를 받아 연다. 「지금 확인」과 자동 확인을 켠 직후의 확인은 값을 넣지 않는다.
/// - 앱 시작 뒤 60초 안이면 협조적 활성화로 앞에 놓고, 그 밖에는 `orderFront`만 해 다른 앱 창 뒤에 둔다
///   (D-19-2). 활성화 정책(.accessory)은 바꾸지 않는다.
/// - 「나중에」·닫기 버튼·Esc는 창을 닫기만 한다. 다음 정기 확인에서 아직 업데이트하지 않았으면 다시 뜬다
///   (D-19-1). 버전을 저장하지 않는다.
final class ImportantUpdateWindowController: NSObject, NSWindowDelegate {
    private let updates: UpdateController
    private let launchedAt: Date
    private var window: NSWindow?
    private var host: NSHostingController<ImportantUpdateView>?
    private var offerCancellable: AnyCancellable?
    private var phaseCancellable: AnyCancellable?

    /// 창이 닫힐 때 부른다. DEBUG 실행이 종료를 알리는 데 쓴다.
    var onClose: (() -> Void)?

    /// 창이 지금 보이는지.
    var isOpen: Bool { window?.isVisible ?? false }

    init(updates: UpdateController, launchedAt: Date) {
        self.updates = updates
        self.launchedAt = launchedAt
        super.init()
        // 같은 값이어도 확인마다 한 번 받는다(중복 거르기를 걸지 않는다, D-19-1).
        offerCancellable = updates.$importantOffer
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] offer in self?.show(offer) }
        // 진행 단계가 바뀌면 닫기를 막고 높이를 다시 잰다(UI-SPEC 「상태와 동작」).
        phaseCancellable = updates.$phase
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] phase in self?.phaseChanged(phase) }
    }

    // MARK: 열기, 닫기

    /// 「나중에」·닫기 버튼·Esc가 모두 이 길로 온다. 창을 닫기만 한다.
    func close() {
        window?.performClose(nil)
    }

    private func makeView(_ offer: ImportantOffer) -> ImportantUpdateView {
        ImportantUpdateView(updates: updates, offer: offer) { [weak self] in self?.close() }
    }

    private func show(_ offer: ImportantOffer) {
        if let window, let host {
            // 이미 열려 있으면 새 창을 만들지 않고 내용만 바꾼다.
            host.rootView = makeView(offer)
            layout(window: window, host: host, recenter: false)
            present(window)
            return
        }
        let host = NSHostingController(rootView: makeView(offer))
        host.sizingOptions = []
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: DS.s(420), height: DS.s(300)),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered, defer: true)
        // 제목 글자는 숨기고 창 메뉴·접근성용으로만 둔다. 설정창과 같은 방식이다.
        window.title = L("update.important.title")
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        // 빈 도구 막대로 제목 막대를 높여 창 버튼을 모서리에서 안쪽으로 들인다. 설정창과 같다(06-02 V1).
        window.toolbar = NSToolbar(identifier: "importantUpdate")
        window.toolbarStyle = .unified
        window.isReleasedWhenClosed = false
        window.level = .normal
        window.collectionBehavior = [.moveToActiveSpace]
        window.standardWindowButton(.miniaturizeButton)?.isEnabled = false
        window.standardWindowButton(.zoomButton)?.isEnabled = false
        window.delegate = self
        window.contentViewController = host
        window.standardWindowButton(.closeButton)?.isEnabled = !isInstalling
        self.window = window
        self.host = host
        layout(window: window, host: host, recenter: true)
        present(window)
    }

    /// 폭 DS.s(420)을 고정하고 높이는 내용에 맞춘다. 다시 잴 때는 왼쪽 위 모서리를 그대로 둔다
    /// (SettingsWindowController.applyWindowSize와 같은 방식).
    private func layout(window: NSWindow, host: NSHostingController<ImportantUpdateView>, recenter: Bool) {
        let width = DS.s(420)
        // sizingOptions가 비어 있으면 host.view에 고유 크기 제약이 없어 fittingSize가 0에 가깝다(실제 창이
        // 높이 2로 떴다, 06-02 V1). 렌더 도구(SettingsRenderHarness)와 같은 NSHostingView로 따로 잰다.
        // sizeThatFits에 큰 높이를 주면 알림 상자(maxHeight)가 늘 최대 높이로 커진다(06-02 V1 두 번째 확인).
        let probe = NSHostingView(rootView: host.rootView)
        probe.frame = NSRect(x: 0, y: 0, width: width, height: DS.s(300))
        probe.layoutSubtreeIfNeeded()
        let height = max(probe.fittingSize.height, DS.s(1))
        if recenter {
            window.setContentSize(NSSize(width: width, height: height))
            window.center()
            return
        }
        let content = window.contentRect(forFrameRect: window.frame)
        guard abs(content.width - width) > 0.5 || abs(content.height - height) > 0.5 else { return }
        let top = window.frame.maxY
        var newFrame = window.frameRect(forContentRect: NSRect(
            origin: content.origin, size: NSSize(width: width, height: height)))
        newFrame.origin.y = top - newFrame.height
        window.setFrame(newFrame, display: true, animate: false)
    }

    /// 앱 시작 뒤 60초 안이면 협조적 활성화 뒤 키 창으로, 그 밖에는 활성화 없이 앞 순서에만 둔다(D-19-2).
    private func present(_ window: NSWindow) {
        let activate = ImportantNotice.activatesOnShow(launchedAt: launchedAt, now: Date())
        if activate {
            NSApp.activate()
            window.makeKeyAndOrderFront(nil)
        } else {
            window.orderFront(nil)
        }
        AppLog.info("update important window shown activate=\(activate)")
    }

    /// 창이 열려 있는 동안 메뉴의 「새 버전」 줄을 눌렀을 때(D-19-4). 사용자가 직접 부른 것이라
    /// 협조적 활성화와 `orderFrontRegardless`를 쓴다(설정창 `bringToFront`와 같은 방식).
    func bringToFront() {
        guard let window else { return }
        NSApp.activate()
        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)
        AppLog.info("update important window front")
    }

    // MARK: 진행 상태

    /// 설치 중에는 닫기를 막는다(설치기에 취소가 없다, UI-SPEC 「닫기, 나중에」).
    private var isInstalling: Bool {
        switch updates.phase {
        case .downloading, .verifying, .installing: return true
        default: return false
        }
    }

    private func stageText(_ phase: UpdateController.Phase) -> String? {
        switch phase {
        case .downloading: return L("about.update.downloading")
        case .verifying: return L("about.update.verifying")
        case .installing: return L("about.update.installing")
        default: return nil
        }
    }

    /// 단계가 바뀌면 닫기 버튼을 흐리게/되살리고, 높이를 다시 재고, 진행 단계면 한 번 읽어 준다.
    private func phaseChanged(_ phase: UpdateController.Phase) {
        guard let window else { return }
        window.standardWindowButton(.closeButton)?.isEnabled = !isInstalling
        // 뷰가 다시 그려진 다음 차례에 잰다.
        DispatchQueue.main.async { [weak self] in
            guard let self, let window = self.window, let host = self.host else { return }
            self.layout(window: window, host: host, recenter: false)
        }
        if let text = stageText(phase) {
            NSAccessibility.post(element: window, notification: .announcementRequested, userInfo: [
                .announcement: text,
                .priority: NSAccessibilityPriorityLevel.high.rawValue,
            ])
        }
    }

    // MARK: NSWindowDelegate

    /// 설치 중에는 닫기 버튼과 ⌘W 둘 다 막는다. 진행 중에는 cancelAction 버튼이 없어 Esc도 닫지 않는다.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        !isInstalling
    }

    func windowWillClose(_ notification: Notification) {
        updates.clearImportantOffer()
        window = nil
        host = nil
        onClose?()
        AppLog.info("update important window closed")
    }
}
