import AppKit
import CoreGraphics
import Foundation
import FnCapsCore
import FnCapsSystem

/// Caps 경로의 조정·복원·F 키 누름 처리의 연결점. 메인 스레드 전용.
/// 진입과 순서는 `CapsReconcileGate`가 정한다. 적용은 #60 → activate 완료 → 매핑, 복원은 매핑 → #60 순서다.
final class CapsController {
    private let tap: FnTap
    private let service: SwitchService
    private let globe: RealGlobeStrategy?
    private let log: (String) -> Void
    private let shortcut: ShortcutManager
    private let mappings: KeyMappingManager

    private var gate = CapsReconcileGate()
    private var restoreCompletions: [(Bool) -> Void] = []
    private var restoreForce = false
    private var lastResult: CapsSystemTarget?
    /// 마지막 실패 시각. 같은 실패를 매초 되풀이하지 않는다.
    private var failedAt: TimeInterval?
    private static let retrySeconds: TimeInterval = 5
    private var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    /// Caps 표시등(D-01~D-09). 경로는 `CapsLedPolicy.productPath` 하나로 고정했다
    /// (Phase 7 실기 판정 07-SPIKE.md: 경로 A, D-09).
    private let capsLed: CapsLedManager
    // 길게 누르기(CAPS-03). 대문자 잠금은 IOHID로만 바꾼다. 합성 Caps 이벤트는 쓰지 않는다.
    private let capsLock = CapsLockController()
    /// 누름 시점의 잠금 값. 늦게 읽으면 입력기가 바꾼 값이 된다.
    private var longStartCaps = false
    /// 누른 순간의 소스가 기준 언어인가, 일반 자판인가. 길게 누르기 동작 표의 입력이다.
    private var longFromBase = false
    private var longIsLayout = true
    private var longPress: CGEvent?
    private var longCode: CGKeyCode = 0
    /// 새 누름, 취소, 재전환마다 올려 낡은 완료를 무효로 한다.
    private var longGeneration = 0
    /// 「입력기에서는 길게 눌러도 반응하지 않기」 설정. 길게 누르기 판정 때 읽는다.
    var longLayoutsOnly: () -> Bool = { false }
    private var activateObserver: NSObjectProtocol?

    /// 이 Mac에서 Caps를 쓸 수 없다고 판단했다(다른 Caps 매핑, 빈 F 키 없음). 정책이 매핑을 내린다.
    private(set) var capsBlocked = false {
        didSet { if capsBlocked != oldValue { updateBlockedTimer() } }
    }
    /// 막힌 동안 30초마다 읽기 전용으로 다시 확인한다(WR-06).
    private var blockedTimer: Timer?
    private static let blockedRecheckSeconds: TimeInterval = 30
    /// 3회 연속 매핑 실패로 경고가 필요하다(설정 창 안내용).
    private(set) var mappingWarning = false

    // 1초 조정(CAPS-05). 키보드 재연결, Karabiner 가상 키보드 재생성, 사라진 매핑을 잡는다.
    private var reconcileTimer: Timer?
    private var appliedKey: CapsKey?
    private var cachedDevices: [KeyboardDevice] = []
    private var cachedSet: Set<UInt64>?
    private var coverage = KeyboardSetCoverage()
    private var recoveryGeneration = 0
    /// 깨어남 재조정이 정책을 다시 계산하게 한다. 모델이 recompute를 건다.
    var onRecover: (() -> Void)?
    /// #60 상실 자가 복구. Caps 펄스 시간 초과만 계수한다(사용자 결정 2026-11-16: 조용히 다시 적용,
    /// 1초 조정 틱에서는 #60을 읽지 않음).
    private var selfHeal = HotkeySelfHeal()
    /// 앱 안 대체 전환이 끝난 뒤에 읽고 쓰려고 확인을 미룬다.
    private static let selfHealDelay: TimeInterval = 1

    init(tap: FnTap, service: SwitchService, globe: RealGlobeStrategy?, defaults: UserDefaults, log: @escaping (String) -> Void) {
        self.tap = tap
        self.service = service
        self.globe = globe
        self.log = log
        shortcut = ShortcutManager(
            defaults: defaults, prefs: SymbolicHotkeyWriter.live, now: { ProcessInfo.processInfo.systemUptime })
        mappings = KeyMappingManager(defaults: defaults, bootSession: KeyboardMapper.bootSession())
        capsLed = CapsLedManager(
            writer: CapsLed(log: log),
            path: { CapsLedPolicy.productPath },
            log: log)
        globe?.capsLockState = { [capsLock] in capsLock.isOn() }
        globe?.onPulseWait = { [weak self] landed in self?.notePulseWait(landed: landed) }
        // 앞 앱이 바뀌면 우연한 잠금 변경을 막으려고 취소한다(T-03-16).
        activateObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.cancelLong() }
        // 강제 종료로 남은 On을 다음 실행에서 Auto로 정리한다(D-07). 중복 실행 검사는 main.swift가 먼저 끝낸다.
        capsLed.release(reason: "launch")
    }

    deinit {
        if let activateObserver { NSWorkspace.shared.notificationCenter.removeObserver(activateObserver) }
    }

    /// 복원할 기록이 남아 있는가. 시스템을 읽지 않는다.
    var needsRestore: Bool { mappings.hasRecords || shortcut.hasStoredState || tap.capsKeyCode != nil }

    func clearBlocked() { capsBlocked = false }

    /// 「원래대로 되돌리기」용. 보류 상태(점유 경고, 매핑 경고, 재시도 간격)를 모두 지운다.
    func clearPending() {
        capsBlocked = false
        mappingWarning = false
        failedAt = nil
        cancelLong()
    }

    func beginTermination() {
        gate.beginTermination()
        stopTimer()
        blockedTimer?.invalidate()
        blockedTimer = nil
        recoveryGeneration &+= 1
    }

    // MARK: 1초 조정 타이머

    private func updateTimer() {
        let needed = !gate.terminating && (lastResult == .full || mappings.hasRecords)
        if needed {
            guard reconcileTimer == nil else { return }
            let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.timerTick() }
            RunLoop.main.add(t, forMode: .common)
            reconcileTimer = t
        } else {
            stopTimer()
        }
    }

    private func stopTimer() {
        reconcileTimer?.invalidate()
        reconcileTimer = nil
    }

    private func timerTick() {
        switch CapsTickDecision.decide(
            sessionAway: PermissionMonitor.sessionAway(), lastTarget: lastResult, gateIdle: !gate.busy,
            terminating: gate.terminating)
        {
        case .stayIdle:
            return
        case .markAway:
            reconcile(target: .shortcutOnly)
        case .proceed:
            if let f = failedAt, now - f < Self.retrySeconds { return }
            reapplyMappings()
        }
    }

    /// 키보드 집합이 달라졌을 때만 다시 열거한다. 같으면 이미 있는 서비스의 값만 읽어 사라진 매핑을 다시 쓴다.
    /// 쓰기는 게이트의 request를 지난다.
    private func reapplyMappings() {
        guard let key = appliedKey else { return }
        let set = KeyboardMapper.kernelKeyboardSet()
        if set != cachedSet || cachedDevices.isEmpty {
            guard let list = KeyboardMapper.keyboards(), !list.isEmpty else { return }
            cachedDevices = list
            // 커널 목록을 목록이 모두 덮을 때만 확정한다. 아니면 다음 틱에 다시 열거한다(WR-05).
            cachedSet = coverage.confirmed(kernel: set, listed: Set(list.map(\.registryID)))
        }
        guard case .start(let generation) = gate.request(.full) else { return }
        switch gate.applyFinished(generation: generation, success: true) {
        case .skip:
            break
        case .writeMapping:
            let report = mappings.apply(devices: cachedDevices, target: key.usage)
            noteMappingReport(report)
            if report.allApplied {
                tap.capsKeyCode = UInt16(key.keyCode)
                failedAt = nil
            } else {
                if report.anyCapsTaken || report.anyConflict { capsBlocked = true }
                failedAt = now
                log("caps reconcile target=full key=\(key.keyCode) result=mappingFailed tick=1")
            }
        }
        finishApply()
    }

    private func noteMappingReport(_ report: MappingReport) {
        if report.shouldWarn {
            if !mappingWarning { log("caps reconcile warn=true") }
            mappingWarning = true
        } else if report.allApplied {
            mappingWarning = false
        }
    }

    /// 깨어남, 잠금 해제, 세션 활성화 뒤 0.5, 2, 5초에 강제로 다시 조정한다. 세대 번호로 낡은 예약을 버린다.
    func scheduleRecovery() {
        guard !gate.terminating else { return }
        tap.resetForResume()
        cancelLong()
        stopTimer()
        recoveryGeneration &+= 1
        let generation = recoveryGeneration
        for delay in [0.5, 2.0, 5.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, self.recoveryGeneration == generation, !self.gate.terminating else { return }
                // 키보드 집합과 마지막 결과를 버려 다음 조정이 모든 것을 다시 확인하게 한다.
                self.cachedSet = nil
                self.cachedDevices = []
                self.failedAt = nil
                if self.lastResult == .full { self.lastResult = nil }
                self.onRecover?()
                // 깨어남·잠금 해제 뒤 OS가 LED를 Auto로 되돌리므로 현재 잠금을 다시 읽어 맞춘다.
                // 새 타이머를 만들지 않고 이 기존 예약 안에서만 쓴다(D-04).
                let mappingUp = self.tap.capsKeyCode != nil
                self.capsLed.apply(reason: "recover", mappingUp: mappingUp, lockOn: self.capsLock.isOn())
                self.updateTimer()
            }
        }
        updateTimer()
    }

    // MARK: #60 자가 복구

    /// 메인 큐. Caps 펄스가 OS에 닿았는지(F 키가 #60을 거쳤는지) 받는다.
    private func notePulseWait(landed: Bool) {
        if landed {
            selfHeal.noteLanded()
            return
        }
        guard lastResult == .full, !gate.terminating else { return }
        if selfHeal.noteTimeout(at: now) {
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.selfHealDelay) { [weak self] in
                self?.runSelfHealCheck()
            }
        }
    }

    /// 예약한 확인. #60이 우리 값이 아니면 기존 조정 경로(#60 → activate → 매핑)로 다시 적용한다.
    /// #60을 새 길로 직접 쓰지 않는다(T-dvj-03). 읽지 못했거나 지금 손댈 수 없으면 쓰지 않는다.
    private func runSelfHealCheck() {
        guard !gate.terminating, !gate.busy, lastResult == .full, !service.isSwitching, let key = appliedKey else {
            selfHeal.skipCheck()
            return
        }
        let ours = SymbolicHotkeyWriter.live.read().map {
            ShortcutOwnership.isOurs(entry: $0["60"] as? [String: Any], keyCode: key.keyCode)
        }
        switch selfHeal.checked(ours: ours, at: now) {
        case .keep:
            log("caps hotkey selfheal check=ours")
        case .unreadable:
            log("caps hotkey selfheal check=unreadable")
        case .reapply:
            // 키코드는 남기지 않는다(T-dvj-04).
            log("caps hotkey selfheal check=notOurs result=reapply count=\(selfHeal.reapplies)")
            // scheduleRecovery와 같은 길: 정책을 다시 계산하면 recompute → reconcile(target:) → gate.request →
            // applyFull이 #60 → activate → 매핑 순서를 지킨다. ShortcutManager.apply가 지금 값(우리 값 아님)을
            // 원래 값으로 백업한다.
            failedAt = nil
            lastResult = nil
            onRecover?()
        case .giveUp:
            log("caps hotkey selfheal check=notOurs result=giveUp")
        }
    }

    // MARK: 조정

    func reconcile(target: CapsSystemTarget) {
        switch target {
        case .hold:
            return
        case .none:
            // 할 일이 없으면 시스템을 읽지 않는다.
            if !needsRestore && !gate.busy {
                lastResult = .none
                updateTimer()
                return
            }
            if let f = failedAt, now - f < Self.retrySeconds { return }
            restore(force: false) { _ in }
        case .shortcutOnly, .full:
            if lastResult == target && !gate.busy { return }
            if let f = failedAt, now - f < Self.retrySeconds { return }
            switch gate.request(target) {
            case .ignored, .remembered: return
            case .start(let generation):
                if target == .full { applyFull(generation: generation) } else { applyShortcutOnly() }
            }
        }
    }

    /// 잠금 화면과 다른 사용자 세션. 매핑만 내리고 기록은 away 표시로 남긴다. #60은 건드리지 않는다(activate가 수백 ms).
    private func applyShortcutOnly() {
        let report = mappings.markAway(devices: KeyboardMapper.keyboards())
        let ok = !report.enumerationFailed && !report.anyFailed
        if ok {
            tap.capsKeyCode = nil
            // 잠금 화면·다른 세션·「FnCaps 끄기」 앱에서는 진짜 Caps가 돌아오므로 OS가 LED를 맞춘다.
            capsLed.release(reason: "shortcutOnly")
            lastResult = .shortcutOnly
            failedAt = nil
        } else {
            failedAt = now
        }
        log("caps reconcile target=shortcutOnly key=- result=\(ok ? "away" : "failed")")
        finishApply()
        updateTimer()
    }

    private func applyFull(generation: Int) {
        guard let devices = KeyboardMapper.keyboards(), !devices.isEmpty else {
            failApply("noKeyboards", key: nil)
            return
        }
        guard let hotkeys = SymbolicHotkeyWriter.live.read() else {
            failApply("noHotkeys", key: nil)
            return
        }
        let key: CapsKey
        switch scanBlock(devices: devices, hotkeys: hotkeys) {
        case .readFailed:
            failApply("readFailed", key: nil)
            return
        case .noFreeKey:
            capsBlocked = true
            failApply("noFreeKey", key: nil)
            return
        case .blocked(let reason, let k):
            capsBlocked = true
            failApply(reason, key: k)
            return
        case .clear(let k):
            key = k
        }
        shortcut.apply(keyCode: key.keyCode) { [weak self] ok in
            guard let self else { return }
            switch self.gate.applyFinished(generation: generation, success: ok) {
            case .skip:
                self.log("caps reconcile target=full key=\(key.keyCode) result=\(ok ? "superseded" : "shortcutFailed")")
                if !ok { self.failedAt = self.now }
                self.finishApply()
            case .writeMapping:
                let report = self.mappings.apply(devices: devices, target: key.usage)
                self.noteMappingReport(report)
                if report.allApplied {
                    self.tap.capsKeyCode = UInt16(key.keyCode)
                    self.appliedKey = key
                    self.cachedDevices = devices
                    self.cachedSet = self.coverage.confirmed(
                        kernel: KeyboardMapper.kernelKeyboardSet(), listed: Set(devices.map(\.registryID)))
                    self.lastResult = .full
                    self.failedAt = nil
                    self.log("caps reconcile target=full key=\(key.keyCode) result=ok")
                } else {
                    if report.anyCapsTaken || report.anyConflict { self.capsBlocked = true }
                    self.failedAt = self.now
                    self.log("caps reconcile target=full key=\(key.keyCode) result=mappingFailed")
                }
                self.finishApply()
                self.updateTimer()
            }
        }
    }

    private enum BlockScan {
        case readFailed, noFreeKey
        case blocked(reason: String, key: CapsKey)
        case clear(CapsKey)
    }

    /// 쓰기 없이 빈 F 키와 Caps 점유를 확인한다. 적용 전 검사와 막힘 재확인이 함께 쓴다.
    private func scanBlock(devices: [KeyboardDevice], hotkeys: [String: Any]) -> BlockScan {
        // 다른 매핑이 내는 사용값만 사용 중으로 센다. 우리 Caps 항목(src == Caps)과 60번 항목은 세지 않는다.
        var mapped = Set<UInt64>()
        for d in devices {
            guard let list = try? d.readMappings() else { return .readFailed }
            for m in list where m.src != CapsKey.capsLockUsage { mapped.insert(m.dst) }
        }
        guard let key = CapsKey.pick(hotkeys: hotkeys, mappedTargets: mapped, preferred: shortcut.managedKeyCode) else {
            return .noFreeKey
        }
        let check = mappings.check(devices: devices, target: key.usage)
        if check.anyCapsTaken || check.anyConflict {
            return .blocked(reason: check.anyCapsTaken ? "capsTaken" : "conflict", key: key)
        }
        return .clear(key)
    }

    private func updateBlockedTimer() {
        if capsBlocked && !gate.terminating {
            guard blockedTimer == nil else { return }
            let t = Timer(timeInterval: Self.blockedRecheckSeconds, repeats: true) { [weak self] _ in
                self?.recheckBlocked()
            }
            RunLoop.main.add(t, forMode: .common)
            blockedTimer = t
        } else {
            blockedTimer?.invalidate()
            blockedTimer = nil
        }
    }

    /// 점유가 지나갔으면 풀고 정책을 다시 계산하게 한다. 읽기만 한다. 읽지 못하면 막힌 채로 둔다.
    private func recheckBlocked() {
        guard capsBlocked, !gate.busy, !gate.terminating else { return }
        guard let devices = KeyboardMapper.keyboards(), !devices.isEmpty,
            let hotkeys = SymbolicHotkeyWriter.live.read()
        else { return }
        guard case .clear = scanBlock(devices: devices, hotkeys: hotkeys) else { return }
        log("caps blocked cleared")
        failedAt = nil
        capsBlocked = false
        onRecover?()
    }

    private func failApply(_ reason: String, key: CapsKey?) {
        failedAt = now
        log("caps reconcile target=full key=\(key.map { String($0.keyCode) } ?? "-") result=\(reason)")
        finishApply()
    }

    /// 적용 경로를 마치고 다음 할 일(줄 선 복원, 기억해 둔 요청)을 처리한다.
    private func finishApply() {
        switch gate.applyDone() {
        case .idle: break
        case .startRestore: runRestore()
        case .reconcile(let t): reconcile(target: t)
        }
    }

    // MARK: 복원

    /// 순서: 매핑 → #60 → 탭의 F 키 분기 해제. 끄기, 되돌리기, 종료가 모두 이 길을 지난다(종료는 force).
    func restore(force: Bool, completion: @escaping (Bool) -> Void) {
        cancelLong()
        // 끄기, 「원래대로 되돌리기」(「지금 복구」), 종료에서 다시 적용 한도를 처음으로 돌린다.
        selfHeal.reset()
        lastResult = nil
        appliedKey = nil
        restoreCompletions.append(completion)
        restoreForce = restoreForce || force
        switch gate.beginRestore(force: force) {
        case .queued: return
        case .start: runRestore()
        }
    }

    private func runRestore() {
        capsLed.release(reason: "restore")
        // 복원 시작이 표시등 책임을 내려놓는 시점이다. 성공 경로에만 두면 mappingFailed와
        // 종료 2초 제한에서 On이 남는다(D-04, D-07).
        let force = restoreForce
        restoreForce = false
        let report = mappings.restore(devices: KeyboardMapper.keyboards())
        guard report.restoreComplete else {
            // 매핑이 돌아오지 않았으면 #60도 건드리지 않는다. 키가 F 키를 내는 동안 단축키를 복원하면 안 된다.
            log("caps restore result=mappingFailed")
            failedAt = now
            finishRestore(ok: false)
            return
        }
        shortcut.restore(force: force) { [weak self] ok in
            guard let self else { return }
            if ok {
                self.tap.capsKeyCode = nil
                self.lastResult = .none
                self.failedAt = nil
                self.mappingWarning = false
            } else {
                self.failedAt = self.now
            }
            self.log("caps restore result=\(ok ? "ok" : "failed")")
            self.finishRestore(ok: ok)
        }
    }

    private func finishRestore(ok: Bool) {
        defer { updateTimer() }
        if case .startRestore = gate.restoreFinished() {
            // 복원 중에 강제 복원이 들어왔다: 알림은 그 복원이 끝난 뒤에 한다.
            restoreForce = true
            runRestore()
            return
        }
        let done = restoreCompletions
        restoreCompletions = []
        done.forEach { $0(ok) }
        // WR-02: 복원 중 들어온 요청은 기억하지 않으므로, 끝난 시점의 정책을 다시 계산한다.
        // 끄기, 되돌리기는 저장된 꺼짐으로 정책이 .none이고 종료는 terminating이라 되살아나지 않는다.
        // 다시 계산해 .none이면 needsRestore가 거짓이거나 failedAt 간격 때문에 복원을 시작하지 않아 반복하지 않는다.
        // 복원 경로 안에서 recompute가 겹치지 않도록 다음 런루프에서 부른다.
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.gate.terminating else { return }
            self.onRecover?()
        }
    }

    // MARK: F 키 누름

    /// 메인 큐. 새 누름이 시작됐다. 전환은 아직 정해지지 않았으므로 누른 순간의 값만 적어 둔다.
    func pressBegan(capsOn: Bool) {
        longStartCaps = capsOn
        longFromBase = role(service.currentID) == .base
        let current = service.currentID
        longIsLayout = service.sources.first(where: { $0.id == current })?.type == Self.layoutType
        longGeneration &+= 1
    }

    /// 메인 큐. 전환 판정(뗌 또는 다른 키)이 났다. 전환 시작만 하고 TIS는 전략이 부른다.
    /// `at`은 판정 시각이며 지연 측정의 시작이다.
    func switchDecided(press: CGEvent?, capsOn: Bool, at: CFAbsoluteTime, trigger: CapsTrigger) {
        guard let globe, let code = tap.capsKeyCode else {
            releaseHold("noRoute")
            return
        }
        guard case .switchTo(let id) = service.preview(.caps) else {
            // 04-REVIEW WR-06: 진행 중인 전환이 있으면 그 전환의 onIdle 해제에 맡긴다. 여기서 풀면
            // 안정되기 전에 붙잡은 키가 이전 IME로 게시된다.
            if !service.isSwitching { releaseHold("noSwitch") }
            return
        }
        if !service.isSwitching {
            globe.armCaps(
                target: id, keyCode: CGKeyCode(code), press: press, capsOn: capsOn, pressedAt: at,
                trigger: trigger.rawValue)
        }
        service.switchTo(id)
    }

    // MARK: 지정 단축키 (D-46)

    /// 메인 큐. 지정 단축키 판정이 났다. Caps 경로가 있으면 그 펄스 전환을 그대로 재사용하고,
    /// 없으면 `switchTo`만으로 앱 안 전환(S2)을 한다. 새 대기나 호출을 더하지 않는다(연구 §5-1).
    func shortcutDecided(id: SourceID, at: CFAbsoluteTime) {
        guard case .switchTo(let target) = service.previewAssigned(id) else {
            // 지금 소스가 이미 대상이다. 키만 삼킨 채 끝난다(연구 §5-2).
            // 04-REVIEW WR-06: 진행 중인 전환이면 해제를 그 전환의 onIdle에 맡긴다.
            if !service.isSwitching { releaseHold("noSwitch") }
            return
        }
        if !service.isSwitching, let globe, let code = tap.capsKeyCode {
            globe.armCaps(
                target: target, keyCode: CGKeyCode(code), press: nil, capsOn: tap.lastCapsOn ?? false,
                pressedAt: at, trigger: "shortcut")
        }
        service.switchTo(target)
        log("shortcut target=\(target)")  // 조합 값은 남기지 않는다(T-04-70).
    }

    // MARK: 길게 누르기

    private static let layoutType = "TISTypeKeyboardLayout"

    private func role(_ id: SourceID?) -> SourceRole? { id.flatMap { service.classified.role(of: $0) } }

    /// 메인 큐. 길게 누르기 판정이 났다(기준 시간을 넘김). 전환 판정이 아니므로 키는 붙잡지 않는다.
    func longDecided(press: CGEvent?) {
        guard globe != nil, let code = tap.capsKeyCode else { return }
        longPress = press
        longCode = CGKeyCode(code)
        fireLong()
    }

    /// 앞 앱 변경, 다른 키(AppModel 훅), 탭 비활성화, 화면 잠금, 깨어남, 복원, 끄기에서 부른다.
    /// 길게 누르기만 취소한다. 판정 전이면 뒤이은 뗌은 그래도 전환한다.
    func cancelLong() {
        tap.cancelCapsLong()
        longGeneration &+= 1
        longPress = nil
    }

    private func fireLong() {
        let generation = longGeneration
        let from = longFromBase ? "base" : "foreign"
        let action = CapsLongRule.action(
            fromBase: longFromBase, isLayout: longIsLayout, layoutsOnly: longLayoutsOnly())
        if action == .ignore {
            log("caps long ignored reason=inputMethod")
            return
        }
        guard !service.isSwitching else {
            log("caps long cancelled reason=busy")
            return
        }
        if action == .flipLock {
            flipLock()
            log("caps long fired from=\(from)")
            return
        }
        if role(service.currentID) == .base {
            flipLock()
            log("caps long fired from=\(from)")
            return
        }
        // 영어가 어느 목록(Caps·fn·사용 안 함)에 있든 그 영어로 바꾼 뒤 잠근다.
        // 영어가 없으면 전환만 생략하고 잠금을 바꾼다(quick 261121-cle).
        guard let id = CapsLongRule.englishTarget(
            caps: service.lists?.caps ?? [], fn: service.lists?.fn ?? [],
            excluded: service.lists?.excluded ?? [], sources: service.sources
        ) else {
            flipLock()
            log("caps long fired from=\(from) switch=none")
            return
        }
        // 기준 언어에서 시작했다면 지금은 외국어다. 기준 언어로 되돌아온 뒤 0.5초 안에만 잠금을 바꾼다.
        guard let globe, role(id) == .base else {
            log("caps long cancelled reason=noBase")
            return
        }
        let started = now
        tap.extendHold()
        globe.armCaps(
            target: id, keyCode: longCode, press: longPress, capsOn: capsLock.isOn() ?? longStartCaps,
            pressedAt: CFAbsoluteTimeGetCurrent(), trigger: "long")
        service.switchTo(id) { [weak self] outcome in
            guard let self, self.longGeneration == generation else {
                self?.log("caps long cancelled reason=superseded")
                return
            }
            guard outcome.tisLanded, self.now - started <= CapsLongRule.baseReturnLimit else {
                self.log("caps long cancelled reason=noBase")
                return
            }
            self.flipLock()
            self.log("caps long fired from=\(from)")
        }
    }

    private func flipLock() {
        let next = !longStartCaps
        // 설정 직후 다시 읽어 확인하지 않는다(늦게 바뀐다).
        if capsLock.set(next) {
            tap.noteCapsLock(on: next)
            capsLed.apply(reason: "lock", mappingUp: tap.capsKeyCode != nil, lockOn: next)
        }
    }

    private func releaseHold(_ reason: String) {
        let n = tap.releaseHold()
        if n > 0 { log("hold released n=\(n) reason=\(reason)") }
    }
}
