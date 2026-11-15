import Carbon
import Foundation

/// Observes TIS distributed notifications. Payloads are never trusted; handlers re-read TIS.
public final class SourceNotifications {
    public var onSelectedChanged: (() -> Void)?
    public var onEnabledChanged: (() -> Void)?
    private var tokens: [NSObjectProtocol] = []

    public init() {}
    deinit { stop() }

    public func start() {
        guard tokens.isEmpty else { return }
        let center = DistributedNotificationCenter.default()
        let selected = Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String)
        let enabled = Notification.Name(kTISNotifyEnabledKeyboardInputSourcesChanged as String)
        tokens.append(
            center.addObserver(forName: selected, object: nil, queue: .main) { [weak self] _ in
                self?.onSelectedChanged?()
            })
        tokens.append(
            center.addObserver(forName: enabled, object: nil, queue: .main) { [weak self] _ in
                self?.onEnabledChanged?()
            })
    }

    public func stop() {
        let center = DistributedNotificationCenter.default()
        for t in tokens { center.removeObserver(t) }
        tokens.removeAll()
    }
}
