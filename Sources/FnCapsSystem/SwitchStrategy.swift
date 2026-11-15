import Carbon
import Foundation
import FnCapsCore

public struct SwitchOutcome: Sendable {
    public var tisLanded: Bool
    public var tisLatencyMs: Double
    public var notes: String

    public init(tisLanded: Bool, tisLatencyMs: Double, notes: String) {
        self.tisLanded = tisLanded
        self.tisLatencyMs = tisLatencyMs
        self.notes = notes
    }
}

/// Main thread only. `completion` is called exactly once, on main.
public protocol SwitchStrategy: AnyObject {
    var name: String { get }
    func switchTo(
        _ target: SourceInfo, from origin: SourceInfo?, catalog: InputSourceCatalog,
        completion: @escaping (SwitchOutcome) -> Void)
}

public enum LandingWaiter {
    /// 01-REVIEW L-04: TIS selected-source changes are announced before the menu bar settles.
    /// Payloads are never trusted (T-05-27): the handlers re-read `catalog.currentID()`.
    private static var selectedSourceChanged: Notification.Name {
        Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String)
    }

    /// Waits until `catalog.currentID()` equals `id` or the timeout elapses.
    /// Landing proves only that the system/menu-bar source changed, not that the focused
    /// app's IME took over; real proof comes from the bench TargetField.
    ///
    /// The TIS notification wakes the wait; `pollMs` is the fallback when it never arrives.
    public static func wait(
        for id: SourceID, catalog: InputSourceCatalog, timeoutMs: Double = 500,
        pollMs: Double = LandingPoll.pollMs, start: CFAbsoluteTime,
        completion: @escaping (Bool, Double) -> Void
    ) {
        dispatchPrecondition(condition: .onQueue(.main))
        func ms() -> Double { (CFAbsoluteTimeGetCurrent() - start) * 1000 }
        if catalog.currentID() == id {
            completion(true, ms())
            return
        }
        var finished = false
        var observer: NSObjectProtocol?
        var timer: Timer?
        func finish(_ landed: Bool) {
            guard !finished else { return }
            finished = true
            timer?.invalidate()
            timer = nil
            if let observer {
                DistributedNotificationCenter.default().removeObserver(observer)
            }
            observer = nil
            completion(landed, ms())
        }
        func check() {
            guard !finished else { return }
            if catalog.currentID() == id {
                finish(true)
            } else if ms() >= timeoutMs {
                finish(false)
            }
        }
        let poll = Timer(timeInterval: pollMs / 1000, repeats: true) { _ in check() }
        timer = poll
        RunLoop.main.add(poll, forMode: .common)
        if LandingPoll.notificationFirst {
            observer = DistributedNotificationCenter.default().addObserver(
                forName: selectedSourceChanged, object: nil, queue: .main
            ) { _ in check() }
        }
    }

    /// S10 armed path: the current source must keep reading as `id` for `stableMs` (`LandingStability`).
    ///
    /// The TIS notification wakes the wait. The notification arrives when the source becomes the
    /// target, while the stable window ends later, so one extra check is scheduled for
    /// `stableMs + 1` ms. `pollMs` remains the fallback when the notification never arrives.
    public static func waitStable(
        for id: SourceID, catalog: InputSourceCatalog, timeoutMs: Double, stableMs: Double,
        pollMs: Double = LandingPoll.pollMs, start: CFAbsoluteTime,
        completion: @escaping (Bool, Double) -> Void
    ) {
        dispatchPrecondition(condition: .onQueue(.main))
        func ms() -> Double { (CFAbsoluteTimeGetCurrent() - start) * 1000 }
        var stability = LandingStability(timeoutMs: timeoutMs, stableMs: stableMs)
        var finished = false
        var observer: NSObjectProtocol?
        var timer: Timer?
        var pendingCheck: DispatchWorkItem?
        func finish(_ landed: Bool) {
            guard !finished else { return }
            finished = true
            pendingCheck?.cancel()
            pendingCheck = nil
            timer?.invalidate()
            timer = nil
            if let observer {
                DistributedNotificationCenter.default().removeObserver(observer)
            }
            observer = nil
            completion(landed, ms())
        }
        func check() {
            guard !finished else { return }
            let result = stability.observe(isTarget: catalog.currentID() == id, elapsedMs: ms())
            if result != .waiting {
                finish(result == .landed)
            }
        }
        func checkOnNotification() {
            guard !finished else { return }
            let result = stability.observe(isTarget: catalog.currentID() == id, elapsedMs: ms())
            if result != .waiting {
                finish(result == .landed)
                return
            }
            guard catalog.currentID() == id, pendingCheck == nil else { return }
            let work = DispatchWorkItem {
                pendingCheck = nil
                check()
            }
            pendingCheck = work
            DispatchQueue.main.asyncAfter(deadline: .now() + (stableMs + 1) / 1000, execute: work)
        }
        check()
        if finished { return }
        let poll = Timer(timeInterval: pollMs / 1000, repeats: true) { _ in check() }
        timer = poll
        RunLoop.main.add(poll, forMode: .common)
        if LandingPoll.notificationFirst {
            observer = DistributedNotificationCenter.default().addObserver(
                forName: selectedSourceChanged, object: nil, queue: .main
            ) { _ in checkOnNotification() }
        }
    }
}
