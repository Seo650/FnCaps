import AppKit

/// 설정 창 밖의 보조 창(중요 업데이트, 처음 설정) 공용 틀(D-01, 06-02 V1).
/// 제목 글자는 숨겨 창 메뉴·접근성용으로만 두고, 빈 도구 막대로 제목 막대를 높여 창 버튼을 모서리에서
/// 안쪽으로 들인다. 크기·포커스·닫기 규칙은 각 컨트롤러가 정한다.
/// 설정 창은 이 틀을 쓰지 않는다(모양을 바꾸지 않는다).
enum AuxiliaryWindow {
    static func make(
        identifier: String,
        title: String,
        contentSize: NSSize,
        delegate: NSWindowDelegate,
        content: NSViewController
    ) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered, defer: true)
        window.title = title
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        // 빈 도구 막대로 제목 막대를 높여 창 버튼을 모서리에서 안쪽으로 들인다. 설정 창과 같다(06-02 V1).
        window.toolbar = NSToolbar(identifier: identifier)
        window.toolbarStyle = .unified
        window.isReleasedWhenClosed = false
        window.level = .normal
        window.collectionBehavior = [.moveToActiveSpace]
        window.standardWindowButton(.miniaturizeButton)?.isEnabled = false
        window.standardWindowButton(.zoomButton)?.isEnabled = false
        window.delegate = delegate
        window.contentViewController = content
        // sizingOptions가 비어 있으면 contentViewController를 붙이는 순간 창이 0×0으로 줄어든다.
        // 그래서 크기를 붙인 뒤에 다시 준다(SettingsWindowController 36-41행).
        window.setContentSize(contentSize)
        return window
    }
}
