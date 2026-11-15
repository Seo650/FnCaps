import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import IOKit.hid
import Security

/// Accessibility permission watcher: timer plus the com.apple.accessibility.api distributed
/// notification both trigger `onTick`. Payloads are never trusted; handlers re-read state.
/// Also reports wake, unlock and lock (L8), which the owner uses to reset held keys and defer tap decisions.
public final class PermissionMonitor: NSObject {
    public var onTick: (() -> Void)?
    /// com.apple.accessibility.api arrived. Called on the main queue, before `onTick`.
    public var onAccessibilityChanged: (() -> Void)?
    /// "wake"(깨어남, 화면 깨어남, 세션 활성화) 또는 "unlock". 메인 큐에서 불린다.
    public var onResume: ((String) -> Void)?
    /// com.apple.screenIsLocked. 메인 큐에서 불린다.
    public var onScreenLock: (() -> Void)?
    public private(set) var interval: TimeInterval = 1.0
    private var timer: Timer?
    private var isObservingDistributed = false
    private var workspaceTokens: [NSObjectProtocol] = []

    /// IOHIDCheckAccess와 임시 탭은 메인을 막을 수 있어 이 큐에서만 돈다(L1, L4). 직렬이라 서로 겹치지 않는다.
    private static let probeQueue = DispatchQueue(label: "io.github.seo650.fncaps.permission-probe", qos: .utility)

    public override init() { super.init() }
    deinit { stop() }

    public func start(interval: TimeInterval) {
        if timer != nil || isObservingDistributed {
            setInterval(interval)
            return
        }
        self.interval = interval
        makeTimer()
        // NSDistributedNotificationCenter.h: 앱이 비활성이면 NSApplication이 전달을 멈출 수 있다.
        // 이 알림 이름들이 실제로 멈추는지는 추정이다. 메뉴 막대 앱은 대개 비활성이므로 바로 받도록 등록한다(L5).
        let center = DistributedNotificationCenter.default()
        let observers: [(Selector, String)] = [
            (#selector(accessibilityDidChange), "com.apple.accessibility.api"),
            (#selector(screenDidLock), "com.apple.screenIsLocked"),
            (#selector(screenDidUnlock), "com.apple.screenIsUnlocked")
        ]
        for (selector, name) in observers {
            center.addObserver(self, selector: selector, name: Notification.Name(name),
                               object: nil, suspensionBehavior: .deliverImmediately)
        }
        isObservingDistributed = true
        // 깨어남 계열은 모두 "wake"로 보낸다. 받는 쪽의 규칙(프로브·복구를 미룸)이 같게 적용된다.
        for name in [
            NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification,
            NSWorkspace.sessionDidBecomeActiveNotification,
        ] {
            workspaceTokens.append(
                NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) {
                    [weak self] _ in
                    self?.onResume?("wake")
                })
        }
    }

    @objc private func accessibilityDidChange() {
        DispatchQueue.main.async { [weak self] in
            self?.onAccessibilityChanged?()
            self?.onTick?()
        }
    }

    @objc private func screenDidLock() {
        DispatchQueue.main.async { [weak self] in self?.onScreenLock?() }
    }

    @objc private func screenDidUnlock() {
        DispatchQueue.main.async { [weak self] in self?.onResume?("unlock") }
    }

    public func setInterval(_ seconds: TimeInterval) {
        guard seconds != interval else { return }
        interval = seconds
        guard timer != nil else { return }
        makeTimer()
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
        DistributedNotificationCenter.default().removeObserver(self)
        isObservingDistributed = false
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        for t in workspaceTokens { workspaceCenter.removeObserver(t) }
        workspaceTokens.removeAll()
    }

    private func makeTimer() {
        timer?.invalidate()
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            self?.onTick?()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    /// 서명 식별자와 cdhash 앞 12자만 돌려준다(경로·팀·인증서 이름 없음). 재빌드 전후 TCC 불일치 비교용.
    public static func signingSummary() -> String {
        var code: SecCode?
        var st = SecCodeCopySelf([], &code)
        guard st == errSecSuccess, let code else { return "id=- cdhash=- status=\(st)" }
        var staticCode: SecStaticCode?
        st = SecCodeCopyStaticCode(code, [], &staticCode)
        guard st == errSecSuccess, let staticCode else { return "id=- cdhash=- status=\(st)" }
        var info: CFDictionary?
        st = SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info)
        guard st == errSecSuccess, let dict = info as? [String: Any] else {
            return "id=- cdhash=- status=\(st)"
        }
        let id = dict[kSecCodeInfoIdentifier as String] as? String ?? "-"
        let hash = (dict[kSecCodeInfoUnique as String] as? Data).map {
            String($0.map { String(format: "%02x", $0) }.joined().prefix(12))
        } ?? "-"
        return "id=\(id) cdhash=\(hash)"
    }

    public static func axTrusted() -> Bool { AXIsProcessTrusted() }

    /// 활성 탭을 만들어 보고 바로 버린다.
    /// L4(LinearMouse GlobalEventTapWatchdog): 권한 API는 철회 뒤에도 낡은 값을 줄 수 있어 탭이 살아 있어도 실제 tapCreate로 시험한다.
    /// 임시 탭은 실행 루프에 붙이지 않고 바로 끄고 무효화한다(L9). 이 제한은 02-13 시절의 미검증 예방책이었고 사용자 결정 4로 의도적으로 뺀다.
    /// 마스크가 scrollWheel인 이유: 10초마다 도는 임시 탭이 fn·수정 키 이벤트에 끼어들지 않게 한다.
    public static func probeTapCreate() -> Bool {
        let mask: CGEventMask = 1 << CGEventMask(CGEventType.scrollWheel.rawValue)
        let callback: CGEventTapCallBack = { _, _, event, _ in Unmanaged.passUnretained(event) }
        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: nil
        ) else { return false }
        CGEvent.tapEnable(tap: port, enable: false)
        CFMachPortInvalidate(port)
        return true
    }

    /// 전용 큐에서 프로브하고 결과를 메인 큐로 돌려준다.
    public static func probeTapCreateAsync(completion: @escaping (Bool) -> Void) {
        probeQueue.async {
            let ok = probeTapCreate()
            DispatchQueue.main.async { completion(ok) }
        }
    }

    /// 진단 전용. 판정에 쓰지 않는다. 02-25에서 낡은 상태를 구별하는지 본 뒤 결정(L1).
    /// IOHIDCheckAccess는 tccd로 동기 IPC를 하므로 전용 큐에서만 부른다. "granted"|"denied"|"unknown"을 메인 큐로 돌려준다.
    public static func hidPostEventAccess(completion: @escaping (String) -> Void) {
        probeQueue.async {
            let access = IOHIDCheckAccess(kIOHIDRequestTypePostEvent)
            let value: String
            if access == kIOHIDAccessTypeGranted {
                value = "granted"
            } else if access == kIOHIDAccessTypeDenied {
                value = "denied"
            } else {
                value = "unknown"
            }
            DispatchQueue.main.async { completion(value) }
        }
    }

    /// 이 키는 공개 API가 아니다. 알림을 놓쳤을 때 tick이 잠금 상태를 바로잡는 보조 수단이다.
    public static func sessionScreenLocked() -> Bool {
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
        return session["CGSSessionScreenIsLocked"] as? Bool ?? false
    }

    /// 이 세션에서 Caps가 대문자 잠금이어야 하는가: 화면이 잠겼거나, 다른 사용자가 콘솔을 쓰고 있다.
    /// 판정은 세션 사전으로만 한다. Secure Input은 잠금과 일치하지 않아 쓰지 않는다.
    /// `sessionScreenLocked()`는 권한 흐름이 쓰므로 그대로 두고 따로 둔다.
    public static func sessionAway() -> Bool {
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
        if session["CGSSessionScreenIsLocked"] as? Bool == true { return true }
        return session[kCGSessionOnConsoleKey as String] as? Bool == false
    }

    /// Registers the app in the Accessibility list by prompting once.
    public static func requestPrompt() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
    }

    @discardableResult
    public static func openAccessibilitySettings() -> Bool {
        let primary = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        let fallback = "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility"
        if let url = URL(string: primary), NSWorkspace.shared.open(url) { return true }
        if let url = URL(string: fallback) { return NSWorkspace.shared.open(url) }
        return false
    }
}
