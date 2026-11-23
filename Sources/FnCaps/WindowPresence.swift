import AppKit
import FnCapsCore

/// 설정 창과 처음 설정 창 중 하나라도 보이면 `.regular`(Dock 아이콘·Cmd-Tab, 권한 설정 앱에서 돌아올 길)를 두고,
/// 둘 다 닫혔을 때만 `.accessory`로 돌아가고 `model.setWindowOpen(false)`를 부른다(08.1 D-03, UI-SPEC 활성화 정책).
/// 판정은 Core `OpenWindowSet`이 한다. 열 때마다 `setWindowOpen(true)`를 불러 2단계의 키 변경 앱 경고
/// (`refreshConflicts`)를 새로 하던 지금 동작을 유지한다.
final class WindowPresence {
    static let settings = "settings"
    static let setup = "setup"

    private let model: AppModel
    private var open = OpenWindowSet()

    init(model: AppModel) {
        self.model = model
    }

    /// 창을 연 것으로 기록하고 Dock 아이콘을 세운다.
    func opened(_ id: String) {
        open.open(id)
        NSApp.setActivationPolicy(.regular)
        model.setWindowOpen(true)
    }

    /// 창을 닫은 것으로 기록한다. 마지막 창이 닫혔을 때만 Dock 아이콘을 내리고 창 닫힘을 알린다.
    func closed(_ id: String) {
        if open.close(id) {
            NSApp.setActivationPolicy(.accessory)
            model.setWindowOpen(false)
        }
        // 창 이름만 남긴다. 남은 창이 없으면 빈 값이다(CLAUDE.md 로그 규칙).
        AppLog.info("window presence closed=\(id) open=\(open.ids.sorted().joined(separator: ","))")
    }
}
