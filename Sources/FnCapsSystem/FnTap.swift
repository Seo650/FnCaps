import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import FnCapsCore

/// Marker on events re-posted by `releaseHold()` ("FNCR"); lets the tap count echoes of its own replays.
public let fncapsReplayMarker: Int64 = 0x464E4352

/// Active session event tap wrapper for the fn (Globe) path.
///
/// The tap lifetime is decided by AppModel via TapInstallPolicy; this class only installs,
/// removes and re-enables. The callback is O(1): it only converts events to `FnGesture` inputs.
/// Forbidden inside the callback: TIS calls, strategy execution, logging, reading key characters,
/// storing key codes. Switch requests are deferred with `DispatchQueue.main.async`.
/// Exception: while a switch settles (`KeyHold`), key events are kept as opaque event copies in memory
/// and replayed in order by `releaseHold()`; they are never inspected or logged. Until the replayed
/// events (FNCR) pass the tap again, new keys are held too so typing order is kept.
/// Exception: the S10 preparation TIS calls inside `onLoneFnSync` are allowed (user decision 2026-10-29).
/// 지정 단축키 맞춤은 설정 표와 keyCode·수정 키 비트를 비교만 하고, 짝 keyUp을 위해 삼킨 keyCode 하나만
/// 다음 keyUp까지 기억한다. 글자를 읽거나 기록하지 않는다(D-46, T-04-66).
public final class FnTap {
    public var onLoneFn: (() -> Void)?
    /// S10 product path (FN-07): when set, called synchronously inside the callback for a lone fn.
    /// true = pass the real fn release and the following Globe key (179) to the OS, which switches
    /// natively (the caller finished preparing and arming inside the callback).
    /// false = consume the release and let the app handle the switch.
    public var onLoneFnSync: (() -> Bool)?
    /// Called on the main queue when fn goes down. Whether this becomes an fn combo is not known yet;
    /// the caller (02-19) prepares only when the prime timing is `down`.
    public var onFnDown: (() -> Void)?
    /// Caps 대신 오는 F 키의 키코드. nil이면 Caps 경로는 꺼져 있고 아래 분기는 아무 일도 하지 않는다.
    /// nil이 되면 판정 전 누름을 버린다(뒤이은 뗌은 전환하지 않는다).
    public var capsKeyCode: UInt16? {
        didSet {
            if capsKeyCode == nil { clearCapsPress() }
        }
    }
    /// 길게 누르기 기준 시간(초). 새 누름이 시작될 때 읽는다(바꾸면 다음 누름부터 적용).
    public var capsLongDelay: TimeInterval = Double(CapsPressJudge.defaultMs) / 1000
    /// false: 길게 누르기 끄기(D-17) 또는 Caps 목록에 영어계 없음(D-26). 새 누름부터 적용.
    public var capsLongEnabled = true
    /// false: fn 목록이 비었다(D-10). fn과 🌐을 제스처에 보내지 않고 통과시킨다.
    public var fnEnabled = true {
        didSet {
            dispatchPrecondition(condition: .onQueue(.main))
            if !fnEnabled && oldValue {
                _ = gesture.handle(.reset)
                globeWindow.close()
            }
        }
    }

    /// fn(63 flagsChanged)과 🌐(179 keyDown/keyUp)를 건드리지 않고 OS에 넘길지 정한다.
    public static func bypassesFn(type: CGEventType, keycode: UInt16, fnEnabled: Bool) -> Bool {
        !fnEnabled
            && ((type == .flagsChanged && keycode == 63)
                || ((type == .keyDown || type == .keyUp) && keycode == 179))
    }
    /// 새 F 키 누름이 시작될 때 메인 큐에서 부른다. 누른 순간의 잠금 값. 전환은 아직 정해지지 않았다.
    public var onCapsPress: ((_ capsOn: Bool) -> Void)?
    /// 전환 판정(뗌 또는 다른 키) 순간 메인 큐에서 부른다. (눌림 이벤트 복사본, 판정 시점 잠금 값, 판정 시각, 이유)
    public var onCapsSwitch: ((_ press: CGEvent?, _ capsOn: Bool, _ at: CFAbsoluteTime, _ trigger: CapsTrigger) -> Void)?
    /// 길게 누르기 판정(타이머, 또는 늦은 타이머를 뗄 때 잡은 경우) 순간 메인 큐에서 부른다. 키는 붙잡지 않는다.
    public var onCapsLong: ((_ press: CGEvent?) -> Void)?
    /// 지정 단축키 판정 순간 메인 큐에서 부른다. (대상 소스, 판정 시각). 조합 값은 넘기지 않는다.
    public var onAssignedShortcut: ((_ id: SourceID, _ at: CFAbsoluteTime) -> Void)?
    /// 지정 단축키 맞춤 표. 콜백도 메인 런루프에서 돌아 잠금이 필요 없다(연구 §1-3).
    public var assignedShortcuts: [KeyChord: SourceID] {
        get { shortcutMatcher.table }
        set {
            dispatchPrecondition(condition: .onQueue(.main))
            shortcutMatcher.table = newValue
        }
    }
    /// 녹화 중이거나 꺼진 동안 true. 맞춤은 쉬고 이미 삼킨 키의 나머지 이벤트만 삼킨다.
    public var shortcutsPaused: Bool {
        get { shortcutMatcher.paused }
        set {
            dispatchPrecondition(condition: .onQueue(.main))
            shortcutMatcher.paused = newValue
        }
    }
    /// 판정 상태의 유일한 소유자. 탭 콜백과 기준 시간 타이머는 모두 메인 스레드(메인 런루프, 메인 큐)에서 돌아 겹치지 않는다.
    private var capsJudge = CapsPressJudge()
    private var shortcutMatcher = ShortcutMatcher()
    /// 판정 전까지 보관하는 눌림 이벤트 복사본(펄스에 쓴다). 판정 후 또는 취소·재설정 시 해제한다.
    private var capsPressCopy: CGEvent?
    /// 새 누름과 재설정마다 올려 낡은 타이머를 무효로 한다.
    private var capsPressSeq = 0
    private var capsGate = CapsPressGate()
    /// 탭을 지난(표식 없는) 키 이벤트에서 마지막으로 본 대문자 잠금 값. 아직 못 봤으면 nil.
    /// 콜백에서 IPC를 부르지 않으려고 이벤트 플래그에서만 갱신한다(T-03-14).
    public private(set) var lastCapsOn: Bool?
    private var globeWindow = GlobePassWindow()
    private var fnDownAt: TimeInterval = 0
    private var lastFnPressMs: Double = 0
    public var onKeyDown: ((_ keyCode: UInt16, _ command: Bool, _ control: Bool) -> Void)?
    public var onMouseDown: (() -> Void)?
    /// Called on the main queue after the system disabled the tap and `reenable()` ran.
    public var onTapDisabled: (() -> Void)?
    /// Counts and reasons only; never key content.
    public var log: ((String) -> Void)?

    public var cancelOnLongPress: Bool {
        get { gesture.cancelOnLongPress }
        set {
            dispatchPrecondition(condition: .onQueue(.main))
            gesture.cancelOnLongPress = newValue
        }
    }

    public private(set) var isInstalled = false

    public var isEnabled: Bool {
        dispatchPrecondition(condition: .onQueue(.main))
        guard isInstalled, let tap else { return false }
        return CGEvent.tapIsEnabled(tap: tap)
    }

    /// Main queue only. Installed, the mach port is still valid, and the tap is enabled.
    public var isValid: Bool {
        dispatchPrecondition(condition: .onQueue(.main))
        guard isInstalled, let tap else { return false }
        return CFMachPortIsValid(tap) && CGEvent.tapIsEnabled(tap: tap)
    }

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var gesture = FnGesture()
    private var hold = KeyHold()
    private var held: [CGEvent] = []
    /// Increments on every hold start so a stale release cannot end a newer hold.
    public private(set) var holdGeneration = 0
    /// Off: switches never hold keys (comparison/escape hatch).
    public var holdEnabled = true

    public init() {}

    deinit { teardown() }

    @discardableResult
    public func install() -> Bool {
        dispatchPrecondition(condition: .onQueue(.main))
        if isInstalled { return true }
        let types: [CGEventType] = [.keyDown, .keyUp, .flagsChanged, .leftMouseDown, .rightMouseDown, .otherMouseDown]
        var mask: CGEventMask = 0
        for t in types { mask |= (1 << CGEventMask(t.rawValue)) }
        mask |= (1 << 14) // systemDefined
        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else { return Unmanaged.passUnretained(event) }
            let me = Unmanaged<FnTap>.fromOpaque(userInfo).takeUnretainedValue()
            return me.handle(type: type, event: event) ? nil : Unmanaged.passUnretained(event)
        }
        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }
        let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        tap = port
        source = src
        _ = gesture.handle(.reset)
        isInstalled = true
        return true
    }

    public func uninstall() {
        dispatchPrecondition(condition: .onQueue(.main))
        teardown()
    }

    public func reenable() {
        dispatchPrecondition(condition: .onQueue(.main))
        let n = releaseHold()
        if n > 0 {
            DispatchQueue.main.async { [weak self] in self?.log?("hold released n=\(n) reason=reenable") }
        }
        capsGate.reset()
        clearCapsPress()
        // 꺼진 동안 짝 keyUp을 놓쳤을 수 있다. 남은 기억이 다음 같은 키를 삼키지 않게 지운다(04-REVIEW WR-01).
        shortcutMatcher.reset()
        guard isInstalled, let tap else { return }
        CGEvent.tapEnable(tap: tap, enable: true)
        _ = gesture.handle(.reset)
    }

    /// 깨어남·잠금 해제 때 부른다. 메인 전용.
    /// 잠금 화면에서 키 해제가 탭에 오지 않으므로 잡힌 키를 해제된 것으로 친다(L8, gksdud).
    public func resetForResume() {
        dispatchPrecondition(condition: .onQueue(.main))
        let n = releaseHold()
        hold.reset()
        capsGate.reset()
        clearCapsPress()
        shortcutMatcher.reset()
        _ = gesture.handle(.reset)
        globeWindow.close()
        if n > 0 { log?("hold released n=\(n) reason=resume") }
    }

    /// 앱이 대문자 잠금을 바꾼 직후 부른다. 다음 재게시가 낡은 값으로 잠금을 되돌리지 않게 한다.
    public func noteCapsLock(on: Bool) {
        dispatchPrecondition(condition: .onQueue(.main))
        lastCapsOn = on
    }

    /// 재게시 이벤트에 표식과 게시 시점의 잠금 값을 싣는다. capsOn이 nil이면 플래그는 그대로 둔다.
    /// 세션은 게시된 이벤트의 플래그에서 잠금 상태를 가져가므로 낡은 값은 잠금을 되돌린다(Pitfall 3).
    public static func stampReplay(_ event: CGEvent, capsOn: Bool?) {
        event.setIntegerValueField(.eventSourceUserData, value: fncapsReplayMarker)
        guard let capsOn else { return }
        var flags = event.flags
        if capsOn { flags.insert(.maskAlphaShift) } else { flags.remove(.maskAlphaShift) }
        event.flags = flags
    }

    /// keyDown, keyUp, flagsChanged만 플래그에서 값을 갱신한다. 마우스와 systemDefined는 현재 값을 유지한다.
    public static func nextCapsOn(current: Bool?, type: CGEventType, flags: CGEventFlags) -> Bool? {
        switch type {
        case .keyDown, .keyUp, .flagsChanged: return flags.contains(.maskAlphaShift)
        default: return current
        }
    }

    /// 판정 전 누름을 지운다. 뒤이은 뗌은 전환하지 않는다.
    private func clearCapsPress() {
        capsJudge.reset()
        capsPressCopy = nil
        capsPressSeq &+= 1
    }

    /// 길게 누르기만 취소한다. 판정 전이면 뒤이은 뗌이나 다른 키는 그래도 전환한다. 메인 전용.
    public func cancelCapsLong() {
        dispatchPrecondition(condition: .onQueue(.main))
        capsJudge.cancel()
    }

    /// 붙잡기 한도를 늘린다(홉의 둘째 다리 앞). 대기 중인 이전 해제는 무효가 된다.
    public func extendHold() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard holdEnabled else { return }
        hold.begin(now: ProcessInfo.processInfo.systemUptime)
        holdGeneration &+= 1
        scheduleExpiry()
    }

    /// Replays held key events in order and ends the hold. Returns the number replayed.
    @discardableResult
    public func releaseHold() -> Int {
        dispatchPrecondition(condition: .onQueue(.main))
        let events = held
        held = []
        for e in events {
            Self.stampReplay(e, capsOn: lastCapsOn)
            e.post(tap: .cghidEventTap)
        }
        hold.flushed(posted: events.count, now: ProcessInfo.processInfo.systemUptime)
        if !events.isEmpty { scheduleExpiry() }
        return events.count
    }

    /// Releases held keys after `maxMs` even when no further key arrives.
    private func scheduleExpiry() {
        DispatchQueue.main.asyncAfter(deadline: .now() + hold.maxMs / 1000) { [weak self] in
            guard let self else { return }
            if self.hold.expire(now: ProcessInfo.processInfo.systemUptime) {
                let n = self.releaseHold()
                self.log?("hold released n=\(n) reason=maxMs")
            } else if self.hold.isBusy && self.hold.count > 0 {
                self.scheduleExpiry()
            }
        }
    }

    private func teardown() {
        let n = releaseHold()
        hold.reset()
        held = []
        if n > 0 { log?("hold released n=\(n) reason=teardown") }
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
        isInstalled = false
        capsGate.reset()
        clearCapsPress()
        shortcutMatcher.reset()
        _ = gesture.handle(.reset)
    }

    /// Returns true when the event must be swallowed.
    private func handle(type: CGEventType, event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            reenable()
            DispatchQueue.main.async { [weak self] in self?.onTapDisabled?() }
            return false
        }
        let userData = event.getIntegerValueField(.eventSourceUserData)
        if userData == fncapsReplayMarker {
            if type == .keyDown || type == .keyUp, hold.echoSeen() { releaseHold() }
            return false
        }
        if userData == fncapsEventMarker { return false }
        lastCapsOn = Self.nextCapsOn(current: lastCapsOn, type: type, flags: event.flags)
        let keycode = UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode))
        // 지정 단축키(D-46): Caps 판정과 붙잡기 분기보다 앞에서 맞춘다. 그래야 다른 전환이 안정되는
        // 동안 누른 단축키가 붙잡혔다가 글자로 새지 않는다(연구 §1-3).
        if type == .keyDown || type == .keyUp, keycode != 179, keycode != capsKeyCode {
            let action = shortcutMatcher.handle(
                isDown: type == .keyDown, keyCode: keycode, flags: event.flags.rawValue,
                autorepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0)
            switch action {
            case .pass:
                break
            case .swallow:
                return true
            case .switchTo(let id):
                // fn을 누른 채면 fn 단독 판정만 취소한다(handleCaps와 같은 처리).
                if gesture.isFnDown { _ = gesture.handle(.otherKeyDown(keyCode: keycode)) }
                // Caps를 누른 채 단축키를 누르면 단축키가 이긴다. Caps 뗌은 전환·잠금 없이 끝난다.
                if capsJudge.isPending { clearCapsPress() }
                if holdEnabled {
                    // 04-REVIEW WR-05 권장안: 앞 전환에 붙잡힌 키는 단축키 전환 전에 내보낸다.
                    // 새 붙잡기로 연장하면 그 키가 단축키 대상 언어로 다시 게시되기 때문이다.
                    // 아직 안정되지 않은 IME로 갈 수 있다(user away — review at UAT).
                    if hold.isBusy || !held.isEmpty {
                        let n = releaseHold()
                        if n > 0 { log?("hold released n=\(n) reason=assignedShortcut") }
                    }
                    hold.begin(now: ProcessInfo.processInfo.systemUptime)
                    holdGeneration &+= 1
                    scheduleExpiry()
                }
                let at = CFAbsoluteTimeGetCurrent()
                DispatchQueue.main.async { [weak self] in self?.onAssignedShortcut?(id, at) }
                return true
            }
        }
        // Caps 판정 전에 다른 글쇠(자동 반복·🌐 제외)가 눌리면 그 순간 전환한다. 그 키는 아래 붙잡기 흐름이 잡는다.
        if type == .keyDown, capsJudge.isPending, keycode != 179, keycode != capsKeyCode,
            event.getIntegerValueField(.keyboardEventAutorepeat) == 0,
            case .switchNow(let trigger) = capsJudge.otherKey()
        {
            decideCapsSwitch(trigger)
        }
        // Caps 경로: F 키는 항상 여기서 가르고 일반 제스처로 보내지 않는다(조합 판단 오염 방지).
        if let capsKeyCode, keycode == capsKeyCode, type == .keyDown || type == .keyUp {
            return handleCaps(type: type, event: event, keycode: keycode)
        }
        if Self.bypassesFn(type: type, keycode: keycode, fnEnabled: fnEnabled) { return false }
        let input: FnGesture.Input
        switch type {
        case .flagsChanged:
            if keycode == 63 {
                let down = event.flags.contains(.maskSecondaryFn)
                let now = ProcessInfo.processInfo.systemUptime
                if down, !gesture.isFnDown {
                    fnDownAt = now
                    DispatchQueue.main.async { [weak self] in self?.onFnDown?() }
                }
                if !down, gesture.isFnDown { lastFnPressMs = (now - fnDownAt) * 1000 }
                input = .fnFlags(down: down, now: now)
            } else {
                input = .otherFlagsChanged
            }
        case .keyDown:
            if keycode == 179 {
                input = .globeKey179
            } else {
                input = .otherKeyDown(keyCode: keycode)
                onKeyDown?(keycode, event.flags.contains(.maskCommand), event.flags.contains(.maskControl))
            }
        case .keyUp:
            input = keycode == 179 ? .globeKey179 : .otherKeyUp
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            input = .mouseDown
            onMouseDown?()
        default:
            if type.rawValue == 14 { input = .systemDefined } else { return false }
        }
        let output = gesture.handle(input)
        if keycode == 179, (type == .keyDown || type == .keyUp), onLoneFnSync != nil {
            let now = ProcessInfo.processInfo.systemUptime
            let pass = globeWindow.allows(now: now)
            let fnDown = gesture.isFnDown
            DispatchQueue.main.async { [weak self] in
                self?.log?("globe179 \(type == .keyDown ? "down" : "up") fnDown=\(fnDown) passed=\(pass)")
            }
            if pass { return false }
        }
        if output == .consumeAndSwitch, let sync = onLoneFnSync {
            if holdEnabled {
                hold.begin(now: ProcessInfo.processInfo.systemUptime)
                holdGeneration &+= 1
                scheduleExpiry()
            }
            if sync() {
                globeWindow.open(now: ProcessInfo.processInfo.systemUptime)
                let pressMs = Int(lastFnPressMs)
                DispatchQueue.main.async { [weak self] in self?.log?("fn release passed to OS pressMs=\(pressMs)") }
                return false
            }
            globeWindow.close()
            let pressMs = Int(lastFnPressMs)
            DispatchQueue.main.async { [weak self] in self?.log?("fn release consumed pressMs=\(pressMs)") }
            return true
        }
        if output == .consumeAndSwitch {
            if holdEnabled {
                hold.begin(now: ProcessInfo.processInfo.systemUptime)
                holdGeneration &+= 1
                scheduleExpiry()
            }
            DispatchQueue.main.async { [weak self] in self?.onLoneFn?() }
        }
        if output == .pass, (type == .keyDown || type == .keyUp), keycode != 179 {
            if hold.isBusy {
                guard let copy = event.copy() else {
                    releaseHold()
                    return false
                }
                switch hold.classify(isKey: true, now: ProcessInfo.processInfo.systemUptime) {
                case .pass: return false
                case .capture:
                    held.append(copy)
                    return true
                case .captureThenFlush:
                    held.append(copy)
                    releaseHold()
                    return true
                }
            }
        }
        return output != .pass
    }

    /// F 키(Caps) 누름·뗌. 콜백은 게이트와 판정과 붙잡기만 하고 전환은 main.async로 미룬다. TIS를 부르지 않는다.
    /// 항상 삼킨다(눌리지 않은 뗌만 통과). 전환은 OS가 아니라 이 앱이 F 키 쌍을 다시 게시해 일으킨다.
    /// 전환은 누름이 아니라 판정 순간(뗌 또는 다른 키)에 일어난다. 키 붙잡기도 그 순간 시작한다.
    private func handleCaps(type: CGEventType, event: CGEvent, keycode: UInt16) -> Bool {
        let down = type == .keyDown
        let autorepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
        let r = capsGate.handle(down: down, autorepeat: autorepeat)
        if !down {
            if r.consume { releaseCaps() }
            return r.consume
        }
        guard r.press else { return r.consume }
        // fn을 누른 채면 fn 단독 판정만 취소한다. F 키를 키 입력으로 집계하지 않는다.
        if gesture.isFnDown { _ = gesture.handle(.otherKeyDown(keyCode: keycode)) }
        capsPressCopy = event.copy()
        capsPressSeq &+= 1
        let seq = capsPressSeq
        let delay = capsLongDelay
        capsJudge.begin(now: ProcessInfo.processInfo.systemUptime, delay: delay, longEnabled: capsLongEnabled)
        let capsOn = event.flags.contains(.maskAlphaShift)
        DispatchQueue.main.async { [weak self] in self?.onCapsPress?(capsOn) }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.capsTimerFired(seq) }
        return true
    }

    private func releaseCaps() {
        switch capsJudge.release(now: ProcessInfo.processInfo.systemUptime) {
        case .none: break
        case .switchNow(let trigger): decideCapsSwitch(trigger)
        case .long: decideCapsLong()
        }
    }

    private func capsTimerFired(_ seq: Int) {
        guard seq == capsPressSeq else { return }
        if capsJudge.timer(now: ProcessInfo.processInfo.systemUptime) == .long { decideCapsLong() }
    }

    /// 전환 판정. 콜백 안에서 키 붙잡기를 시작해 판정 직후 친 키가 새 언어로 가게 한다.
    private func decideCapsSwitch(_ trigger: CapsTrigger) {
        let copy = capsPressCopy
        capsPressCopy = nil
        if holdEnabled {
            hold.begin(now: ProcessInfo.processInfo.systemUptime)
            holdGeneration &+= 1
            scheduleExpiry()
        }
        let capsOn = lastCapsOn ?? false
        let at = CFAbsoluteTimeGetCurrent()
        DispatchQueue.main.async { [weak self] in self?.onCapsSwitch?(copy, capsOn, at, trigger) }
    }

    /// 길게 누르기 판정. 키를 붙잡지 않는다.
    private func decideCapsLong() {
        let copy = capsPressCopy
        capsPressCopy = nil
        DispatchQueue.main.async { [weak self] in self?.onCapsLong?(copy) }
    }
}
