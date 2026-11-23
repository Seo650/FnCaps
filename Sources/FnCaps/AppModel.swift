// 구조 참고: LinearMouse EventTapRecovery·GlobalEventTapWatchdog, gksdud forgetUnusablePermissions (MIT), GuardedEventTap gist(개념만, 코드 복사 없음)
import AppKit
import Combine
import FnCapsCore
import FnCapsSystem

/// UI가 읽는 단일 상태 스냅샷.
struct AppSnapshot: Equatable {
    var status: AppStatus
    var trusted: Bool
    var enabled: Bool
    var iconHidden: Bool
    var iconVisible: Bool
    var cancelOnLongPress: Bool
    var permissionLost: Bool
    var login: LoginItemPresentation
    var hasActiveList: Bool
    var strategyName: String
    var globeNotice: Bool
    var permissionPanel: PermissionPanel
    var resetting: Bool
    /// 다른 Caps 매핑이나 빈 F 키 없음으로 Caps 전환을 켜지 않았다.
    var capsBlocked: Bool = false
    /// 키별 목록 화면용 행. 켜진 소스만 넣는다(꺼진 소스는 저장 목록에 자리만 남는다, M2).
    var capsRows: [SourceRow] = []
    var fnRows: [SourceRow] = []
    /// 지정 단축키 상자 행(D-46).
    var assignedRows: [SourceRow] = []
    /// 지정 소스의 표시 단축키. 저장하지 않고 그릴 때 계산한다(자판이 바뀌면 따라간다, 연구 §4).
    var assignedChordText: [SourceID: String] = [:]
    /// 시스템 기호 단축키와 겹치는 조합을 가진 지정 소스. 겹쳐도 저장·동작은 그대로다(D-46).
    var assignedConflictIDs: Set<SourceID> = []
    /// ⇧ 하나짜리 조합으로 대문자 입력을 가로채는 지정 소스(T-04-65).
    var assignedTypingIDs: Set<SourceID> = []
    /// 지정 단축키가 하나 이상 있는가. 상태 문구가 「두 목록이 비어 대기 중」을 쓰지 않게 한다.
    var hasShortcuts: Bool = false
    var unassignedRows: [SourceRow] = []
    var pendingNewSourceIDs: [SourceID] = []
    var newSourcesMenuTitle: String? = nil
    /// 키별 진입 언어(엔진이 켜진 소스 기준으로 정리한 값, D-01).
    var entry: EntryChoices = EntryChoices()
    var capsLongEnabled: Bool = true
    var settleGlobalMs: Int = SettleTimePolicy.defaultMs
    var settleExceptions: [SettleException] = []
    /// 지금 입력 소스 ID. 입력 소스가 바뀌면 스냅숏만 다시 만든다.
    var currentSourceID: SourceID? = nil
    /// 실행 중인 충돌 앱 이름(ConflictApps 순서). D-40.
    var conflictApps: [String] = []
    /// 사용자가 충돌 앱 경고를 X로 닫았다. 손쉬운 사용 권한이 풀리면 다시 보인다(2026-11-13).
    var conflictDismissed: Bool = false
    /// 앱 도메인 AppleLanguages에서 읽은 앱 언어(D-42). 적용은 다시 열 때.
    var appLanguage: AppLanguage = .system
    /// 도움말 쪽이 그릴 켜 둔 선택 가능 키보드 소스(D-26). `service.sources` 그대로다.
    var helpSources: [SourceInfo] = []
    /// macOS 시스템 언어(전역 AppleLanguages 첫 값). D-27 중심 언어 판정에 쓴다.
    var systemLanguage: String? = nil
}

struct SourceRow: Equatable {
    let id: SourceID
    let name: String
    /// 늘 true(꺼진 소스는 행으로 만들지 않는다). 필드 삭제는 뒤 계획 몫.
    let enabled: Bool
    /// 아이콘이 없을 때 타일에 쓰는 1~2자 기호(SourceGlyph).
    let glyph: String
}

/// 상태·설정의 단일 출처. 메인 스레드 전용.
/// 탭은 TapInstallPolicy가 true일 때만 존재한다(SAFE-04).
final class AppModel: ObservableObject {
    @Published private(set) var snapshot: AppSnapshot
    let isFirstLaunch: Bool

    let service: SwitchService
    let strategy: SwitchStrategy
    /// 소유자는 모델. Phase 3 Caps가 공유한다.
    var heuristic = CompositionHeuristic()
    let tap = FnTap()
    /// Caps 경로. 모델을 더 키우지 않으려고 따로 둔다.
    private(set) lazy var caps = CapsController(
        tap: tap, service: service, globe: strategy as? RealGlobeStrategy, defaults: UserDefaults.standard,
        log: { AppLog.info($0) })
    let monitor = PermissionMonitor()
    let loginItem = LoginItem()

    private let defaults = UserDefaults.standard
    private var trusted = false
    private var wasTrusted = false
    private var lastLoggedStatus: AppStatus? = nil
    private var windowOpen = false
    private var currentIsInputMethod = false
    private lazy var promptMemory = PromptMemory(defaults: defaults)
    private var lastTapInstalled = false
    private var lastAx: Bool?
    /// 마지막 시도의 값. `permission` 줄의 probe 자리에 남겨 이전 로그와 비교한다.
    private var lastProbe: Bool?
    private var lastWatchdogProbe: Bool?
    private lazy var restartMemory = RestartMemory(defaults: defaults)
    /// 마지막 허용 뒤 탭을 깐 적이 있는지(G-08.1-4). 권한 잃음과 허용 직후 실패를 가른다.
    private var grantSession = GrantSession()
    private lazy var recovery = TapRecovery(
        attempt: { [weak self] done in self?.attemptTap(done) },
        onFailure: { [weak self] result in self?.recoveryFailed(result) })
    private lazy var watchdog = ProbeWatchdog(
        probe: PermissionMonitor.probeTapCreateAsync,
        onResult: { [weak self] ok in self?.watchdogResult(ok) })
    private var watchdogTimer: Timer?
    private var stability = RestartStability()
    private var rebuildGeneration = 0
    private var rebuildPending = false
    private var stuck = false
    private var resetFailed = false
    private var resetting = false
    private var awaitingRegrant = false
    private var screenLocked = false
    /// 탭이 사라진 시각. 5초 유예 동안 #60을 쓰거나 내리지 않는다.
    private var tapGoneAt: TimeInterval?
    /// 사용자가 끈 경로의 복원이 진행 중이다. 이때만 recompute의 탭 내리기를 미룬다.
    private var userRestoring = false
    /// 참이면 어떤 경로로도 탭을 만들거나 복구를 시작하지 않는다.
    private var tapBlocked: Bool { rebuildPending || resetting || awaitingRegrant || screenLocked }
    private var globe: RealGlobeStrategy? { strategy as? RealGlobeStrategy }
    private var globeUsage: Int?
    private var repeatGuard = FnRepeatGuard()
    private var fnSeq = 0
    private var now: TimeInterval { ProcessInfo.processInfo.systemUptime }
    /// 마지막으로 전환을 일으킨 키. 앱별 대기 시간은 fn에만 쓴다(D-26). 콜백에서는 값만 대입한다.
    private var lastFnEnabled: Bool?
    private var lastCapsLongEnabled: Bool?
    /// 맨 앞 앱 번들 ID. 메인 큐에서 앱 전환 알림으로만 갱신한다. 탭 콜백에서는 NSWorkspace를 부르지 않는다(Pitfall 10).
    private var frontBundleID: String?
    /// 「FnCaps 끄기」 앱이 맨 앞이다(FINAL-REVIEW §7 R1). 앱 전환과 앱별 설정 저장 때만 다시 계산한다.
    private var appOff = false
    private var conflictApps: [String] = []
    private var workspaceObservers: [NSObjectProtocol] = []
    /// 시스템 기호 단축키 집합(읽기 전용). 녹화 확정과 창 열기 때만 새로 읽는다(연구 §3-1).
    private var systemChords = SystemChordSet(carbonEntries: [])

    private enum Key {
        static let enabled = "enabled"
        static let iconHidden = "menuBarIconHidden"
        static let cancelOnLongPress = "cancelOnLongPress"
        static let launched = "hasLaunchedBefore"
        /// Dev comparison keys (quick 261028): hold typed keys while a switch settles.
        static let keyHold = "keyHold"
        static let keyHoldSettleMs = "keyHoldSettleMs"
        /// 옛 Caps 담당 소스 ID. 읽기 전용 이전 입력이며 지우지 않는다(되돌릴 수 있게).
        static let capsSourceID = "capsSourceID"
        static let keyLists = KeyLists.defaultsKey
        static let keyListsCorrupt = KeyLists.corruptKey
        static let outsideRule = OutsideRule.defaultsKey
        /// Caps 길게 누르기 기준 시간(ms, 300~1000, 기본 500)과 「입력기에서는 반응하지 않기」(기본 꺼짐).
        static let capsLongPressMs = "capsLongPressMs"
        static let capsLongLayoutsOnly = "capsLongLayoutsOnly"
        static let capsLongEnabled = "capsLongEnabled"
        static let settleExceptions = SettleExceptions.defaultsKey
        static let pendingNewSources = "pendingNewSources"
        static let conflictDismissed = "conflictWarningDismissed"
    }

    private func bool(_ key: String, _ fallback: Bool) -> Bool {
        defaults.object(forKey: key) as? Bool ?? fallback
    }

    private var enabled: Bool { bool(Key.enabled, true) }
    private var iconHidden: Bool { bool(Key.iconHidden, false) }
    private var cancelLong: Bool { bool(Key.cancelOnLongPress, false) }

    init() {
        isFirstLaunch = !(UserDefaults.standard.object(forKey: Key.launched) as? Bool ?? false)
        let name = ProductStrategy.resolve(stored: UserDefaults.standard.string(forKey: ProductStrategy.overrideDefaultsKey))
        let strat = ProductStrategy.make(named: name)
        strategy = strat
        let lister = FreshSourceLister(log: { AppLog.info($0) })
        service = SwitchService(
            strategy: strat, freshList: { lister.list(completion: $0) }, log: { AppLog.info($0) })
        snapshot = AppSnapshot(
            status: .permissionNeeded, trusted: false, enabled: true, iconHidden: false,
            iconVisible: true, cancelOnLongPress: false, permissionLost: false,
            login: .off, hasActiveList: false, strategyName: strat.name, globeNotice: false,
            permissionPanel: .grant, resetting: false)
        snapshot = makeSnapshot(status: .permissionNeeded)
    }

    private var trace = PermissionTrace()

    /// 옛 설정을 읽기만 한다. 옛 키는 지우지 않는다.
    private func loadLegacyInputs() {
        service.legacyCapsSourceID = defaults.string(forKey: Key.capsSourceID).flatMap { $0.isEmpty ? nil : $0 }
        service.legacyFnModeKeys = CycleOrder.decoded(defaults.data(forKey: CycleOrder.defaultsKey)).modeKeys
    }

    func start() {
        startWorkspaceObservers()
        globe?.composingHint = { [weak self] in self?.heuristic.mayBeComposing ?? true }
        globe?.onExtendHold = { [weak self] in self?.tap.extendHold() }
        globe?.log = { AppLog.info($0) }
        (strategy as? NativeHopStrategy)?.composingHint = { [weak self] in self?.heuristic.mayBeComposing ?? true }
        // D-03: 옛 전역 outsideRule을 두 키의 진입 언어로 이전한다. 옛 키는 지우지 않는다.
        let legacyEntry = EntryLanguage(OutsideRule.decoded(defaults.string(forKey: Key.outsideRule)))
        service.legacyEntry = legacyEntry
        switch KeyLists.decoded(defaults.data(forKey: Key.keyLists), legacyEntry: legacyEntry) {
        case .valid(let saved):
            service.setLists(saved)
            // D-03: entry가 없던 옛 JSON이면 이전한 값을 한 번 저장해 둔다(wave 3 검토 WR-02).
            if let data = defaults.data(forKey: Key.keyLists),
               let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               object["entry"] == nil {
                defaults.set(saved.encoded(), forKey: Key.keyLists)
                AppLog.info("keyLists entry migrated entry=\(saved.entry.storageText)")
            }
        case .corrupt:
            // 깨진 원본은 보관하고 옛 규칙으로 다시 만든다(T-04-09).
            defaults.set(defaults.data(forKey: Key.keyLists), forKey: Key.keyListsCorrupt)
            AppLog.info("keyLists corrupt kept=\(Key.keyListsCorrupt)")
            loadLegacyInputs()
        case .missing:
            loadLegacyInputs()
        }
        service.onListsChanged = { [weak self] lists, added in
            guard let self else { return }
            // 04-REVIEW IN-09: reconciled의 added에는 넘침으로 밀려난 기존 소스도 들어온다.
            // 이전 목록(저장된 값)에도 있던 ID는 「새」 소스가 아니므로 뺀다.
            let previousKnown: Set<SourceID>
            switch KeyLists.decoded(self.defaults.data(forKey: Key.keyLists), legacyEntry: self.service.legacyEntry) {
            case .valid(let previous): previousKnown = previous.known
            case .corrupt, .missing: previousKnown = []
            }
            self.defaults.set(lists.encoded(), forKey: Key.keyLists)
            let newIDs = added.filter { !previousKnown.contains($0) }
            if !newIDs.isEmpty {
                var pending = self.pendingNewSourceList
                for id in newIDs where !pending.contains(id) { pending.append(id) }
                self.defaults.set(pending, forKey: Key.pendingNewSources)
            }
            AppLog.info("keyLists saved caps=\(lists.caps.count) fn=\(lists.fn.count) added=\(newIDs.count)")
        }
        service.onChange = { [weak self] in
            self?.recompute()
        }
        globe?.seed(current: service.currentID, history: service.recentHistory())
        globeUsage = GlobeSettingReader.readUsage()
        AppLog.info("globe usage=\(globeUsage.map(String.init) ?? "nil")")
        service.onSelectedChanged = { [weak self] id in
            self?.globe?.observe(selected: id)
            self?.heuristic.handle(.sourceChanged)
            self?.updateInputMethodFlag(id)
            self?.refreshSnapshot()
        }
        service.start()
        updateInputMethodFlag(service.currentID)

        tap.cancelOnLongPress = cancelLong
        tap.holdEnabled = bool(Key.keyHold, true)
        tap.log = { AppLog.info($0) }
        service.onIdle = { [weak self] in self?.scheduleHoldRelease() }
        tap.onLoneFn = { [weak self] in self?.fnTapped() }
        if globe != nil {
            // 콜백 안 동기: 무거운 일과 로그 금지(로그는 main.async).
            tap.onLoneFnSync = { [weak self] in
                guard let self, let globe = self.globe else { return false }
                globe.clearPreparation()
                let t = self.now
                let sinceMs = self.repeatGuard.lastPressAt.map { Int((t - $0) * 1000) }
                let rapid = self.repeatGuard.notePress(now: t)
                let switching = self.service.isSwitching
                let d = self.service.preview(.fn)
                var targetID: SourceID?
                if case .switchTo(let id) = d { targetID = id }
                let isSwitch = targetID != nil
                let route = FnRoutePolicy.decide(
                    isSwitch: isSwitch, usage: self.globeUsage, rapid: rapid, alreadySwitching: switching)
                var primeNote = "-"
                if route == .passToOS, let id = targetID,
                    let target = self.service.sources.first(where: { $0.id == id })
                {
                    if globe.preparedTarget != id {
                        let origin = self.service.sources.first(where: { $0.id == self.service.currentID })
                        primeNote = globe.prepare(
                            target: target, origin: origin, catalog: self.service.catalog, at: .release)
                    }
                    globe.arm(target: id)
                } else {
                    globe.clearPreparation()
                }
                // Commit the previewed target itself. Re-deciding with handle(.fn) after priming read a
                // current source the priming had just moved, so the app and the OS chose different targets
                // (02-20 part 3: dozens of `fn preview mismatch`).
                let committed: Decision
                if let id = targetID {
                    self.service.switchTo(id)
                    committed = d
                } else {
                    committed = self.service.handle(.fn)
                }
                let mismatch = committed != d
                if mismatch { globe.clearPreparation() }
                self.fnSeq += 1
                let seq = self.fnSeq
                let usage = self.globeUsage
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    if mismatch { AppLog.info("fn preview mismatch preview=\(d) committed=\(committed)") }
                    AppLog.info("fnpass seq=\(seq) route=\(route.rawValue) rapid=\(rapid) "
                        + "sinceMs=\(sinceMs.map(String.init) ?? "-") usage=\(usage.map(String.init) ?? "nil") "
                        + "target=\(targetID ?? "-") prime=\(primeNote) switching=\(switching)")
                    AppLog.info("fn decision=\(d) sync")
                    if targetID == nil {
                        let n = self.tap.releaseHold()
                        if n > 0 { AppLog.info("hold released n=\(n) reason=noSwitch") }
                    }
                }
                if d == .passThrough {
                    globe.clearPreparation()
                    DispatchQueue.main.async { AppLog.info("fn passThrough to OS") }
                }
                return (route == .passToOS && isSwitch) || d == .passThrough
            }
        }
        tap.onKeyDown = { [weak self] code, cmd, ctrl in
            guard let self else { return }
            self.caps.cancelLong()
            self.heuristic.handle(
                .keyDown(keyCode: code, command: cmd, control: ctrl,
                         sourceIsInputMethod: self.currentIsInputMethod))
        }
        tap.onMouseDown = { [weak self] in self?.heuristic.handle(.mouseDown) }
        tap.onCapsPress = { [weak self] capsOn in self?.caps.pressBegan(capsOn: capsOn) }
        tap.onCapsSwitch = { [weak self] press, capsOn, at, trigger in
            self?.caps.switchDecided(press: press, capsOn: capsOn, at: at, trigger: trigger)
        }
        tap.onCapsLong = { [weak self] press in
            self?.caps.longDecided(press: press)
        }
        tap.onAssignedShortcut = { [weak self] id, at in
            guard let self else { return }
            self.caps.shortcutDecided(id: id, at: at)
        }
        tap.capsLongDelay = Double(capsLongPressMs) / 1000
        caps.longLayoutsOnly = { [weak self] in self?.capsLongLayoutsOnly ?? false }

        monitor.onTick = { [weak self] in self?.tick() }
        monitor.onAccessibilityChanged = { [weak self] in self?.accessibilityChanged() }
        caps.onRecover = { [weak self] in self?.recompute() }
        monitor.onResume = { [weak self] reason in self?.resume(reason: reason) }
        monitor.onScreenLock = { [weak self] in
            self?.screenLocked = true
            self?.caps.cancelLong()
            AppLog.info("screen locked")
            // 알림 즉시 매핑을 내린다. 1초 타이머를 기다리면 잠금 화면에서 Caps가 잠깐 죽는다(CAPS-04).
            self?.recompute()
        }
        tap.onTapDisabled = { [weak self] in
            self?.caps.cancelLong()
            self?.checkWatchdog()
        }
        monitor.start(interval: 1)
        watchdog.start()
        let timer = Timer(timeInterval: 10, repeats: true) { [weak self] _ in self?.checkWatchdog() }
        RunLoop.main.add(timer, forMode: .common)
        watchdogTimer = timer

        if isFirstLaunch { loginItem.registerOnFirstLaunch(.standard) }
        // 처음 설치는 hasLaunchedBefore를 쓰기 전에 명시값 false를 저장해야 이주 규칙이 기존 설치로 착각하지 않는다.
        if isFirstLaunch && defaults.object(forKey: PromptMemory.key) == nil {
            defaults.set(false, forKey: PromptMemory.key)
        }
        // D-19: launched를 쓰기 전에 시드한다. 업데이트 사용자는 시드되지 않는다.
        // 재시작 뒤 isFirstLaunch는 false라 이후는 저장값만 본다(RESEARCH Pitfall 3).
        FirstRunSetup.seedIfFirstLaunch(isFirstLaunch, defaults: defaults)
        // 04.2 D-50 옛 값 청소(04.4 D-20).
        defaults.removeObject(forKey: "setupHandoffPending")
        defaults.set(true, forKey: Key.launched)

        screenLocked = PermissionMonitor.sessionScreenLocked()
        // lastAx를 먼저 채워야 첫 시도와 첫 tick 사이에 켜진 권한도 false→true로 잡힌다.
        noteAx(PermissionMonitor.axTrusted())
        recovery.start()
        tick()
        AppLog.info("start strategy=\(strategy.name) modes=\(service.classified.modes.count) "
            + "keyHold=\(tap.holdEnabled) settle=\(settleGlobalMs) fnEnabled=\(tap.fnEnabled) capsLongEnabled=\(tap.capsLongEnabled) primeAt=\(PrimeTiming.defaultValue.rawValue) "
            + "repeatWindowMs=\(Int(FnRepeatGuard.defaultWindowMs)) usage=\(globeUsage.map(String.init) ?? "nil") "
            + "capsPath=\(globe != nil)")
        AppLog.info("signing " + PermissionMonitor.signingSummary())
    }

    private func updateInputMethodFlag(_ id: SourceID?) {
        if let type = service.sources.first(where: { $0.id == id })?.type {
            currentIsInputMethod = type != "TISTypeKeyboardLayout"
        } else {
            currentIsInputMethod = false
        }
    }

    /// 전역 대기 시간(ms). 옛 값이 Double로 저장돼 있어도 Int로 읽는다.
    private var settleGlobalMs: Int {
        guard let n = defaults.object(forKey: Key.keyHoldSettleMs) as? NSNumber else { return SettleTimePolicy.defaultMs }
        return SettleTimePolicy.clamp(Int(n.doubleValue.rounded()))
    }

    private var settleExceptionList: [SettleException] {
        SettleExceptions.decoded(defaults.data(forKey: Key.settleExceptions))
    }

    private var pendingNewSourceList: [SourceID] {
        defaults.stringArray(forKey: Key.pendingNewSources) ?? []
    }

    private func fnTapped() {
        let d = service.handle(.fn)
        AppLog.info("fn decision=\(d)")
        if case .switchTo = d { return }
        // 04-REVIEW WR-06: 진행 중인 전환이 있으면 그 전환의 해제에 맡긴다.
        guard !service.isSwitching else { return }
        let n = tap.releaseHold()
        if n > 0 { AppLog.info("hold released n=\(n) reason=noSwitch") }
    }

    /// Replays keys held during the switch once the input context has had `holdSettleMs` to follow.
    private func scheduleHoldRelease() {
        let generation = tap.holdGeneration
        let ms = settleGlobalMs
        DispatchQueue.main.asyncAfter(deadline: .now() + Double(ms) / 1000) { [weak self] in
            guard let self, self.tap.holdGeneration == generation else { return }
            let n = self.tap.releaseHold()
            if n > 0 { AppLog.info("hold released n=\(n)") }
        }
    }

    // MARK: 권한 판정

    /// 02-20: ax=true·probe=false가 잦은 프로브 생략과 무관하게 재현. 판정은 시도·감시 두 곳에서만 한다.
    /// 그래서 tick은 tapCreate를 부르지 않고, 복구를 시작하거나 탭을 내리기만 한다.
    private func tick() {
        syncScreenLock()
        let ax = PermissionMonitor.axTrusted()
        noteAx(ax)
        // 권한이 풀리면 닫아 둔 충돌 경고를 다시 보이게 한다. 다시 허용한 뒤 처음 보인다.
        if !ax, bool(Key.conflictDismissed, false) {
            objectWillChange.send()
            defaults.set(false, forKey: Key.conflictDismissed)
        }
        if tapBlocked {
            if !ax {
                tap.uninstall()
                trusted = false
                stuck = false
            }
        } else if tap.isInstalled {
            if !ax {
                tap.uninstall()
                trusted = false
            } else if !tap.isEnabled {
                tap.reenable()
                if !tap.isEnabled {
                    tap.uninstall()
                    recovery.restart()
                }
            }
        } else if !ax {
            trusted = false
            stuck = false
        } else if !trusted && !recovery.isActive {
            recovery.start()
        }
        if let line = trace.record(
            ax: ax, probe: lastProbe, tapInstalled: tap.isInstalled,
            tapEnabled: tap.isInstalled ? tap.isEnabled : nil)
        {
            AppLog.info(line)
        }
        let usageNow = GlobeSettingReader.readUsage()
        if usageNow != globeUsage {
            globeUsage = usageNow
            AppLog.info("globe usage=\(usageNow.map(String.init) ?? "nil")")
        }
        recompute()
    }

    /// 잠금·해제 알림을 놓쳐도 복구가 영구히 막히지 않게 한다.
    private func syncScreenLock() {
        let locked = PermissionMonitor.sessionScreenLocked()
        if locked && !screenLocked {
            screenLocked = true
            AppLog.info("screen locked reason=poll")
        } else if !locked && screenLocked {
            resume(reason: "unlock-poll")
        }
    }

    private func noteAx(_ ax: Bool) {
        let previous = lastAx
        lastAx = ax
        guard let previous, previous != ax else { return }
        logHidAccess(ax: ax, reason: "ax-change")
        if ax {
            grantSession.noteGrant()
            restartMemory.clear()
            awaitingRegrant = false
            if !tapBlocked { recovery.restart() }
        } else {
            recovery.stop()
            stability.noteFailure()
        }
    }

    /// 탭 시도 한 번. TapRecovery와 알림 0.3 s 판단이 부른다. 성공으로 재시작 기록을 지우지 않는다.
    /// 지우면 재시작 → 성공 → 감시 실패 → 3.5 s 복구 실패 → 재시작 고리가 생긴다.
    private func attemptTap(_ done: (TapRecovery.StartResult) -> Void) {
        if tapBlocked {
            AppLog.info("recovery result=cancelled")
            done(.cancelled)
            return
        }
        guard PermissionMonitor.axTrusted() else {
            trusted = false
            lastProbe = nil
            AppLog.info("recovery result=permissionRequired")
            done(.permissionRequired)
            recompute()
            return
        }
        let needsTap = TapInstallPolicy.shouldInstall(
            trusted: true, enabled: enabled, hasActiveList: service.layout.hasActiveList,
            hasShortcuts: !shortcutTable.isEmpty)
        let ok = needsTap ? tap.install() : PermissionMonitor.probeTapCreate()
        lastProbe = ok
        if ok {
            trusted = true
            wasTrusted = true
            grantSession.noteTapStarted()
            stuck = false
            resetFailed = false
            AppLog.info("recovery result=started")
            done(.started)
        } else {
            trusted = false  // 시도 실패 = 미신뢰
            stability.noteFailure()
            AppLog.info("recovery result=failed")
            done(.failed)
        }
        recompute()
    }

    private func recoveryFailed(_ result: TapRecovery.StartResult) {
        let canRestart = restartMemory.canRestart
        let tapSinceGrant = grantSession.tapStartedSinceGrant
        let action = RecoveryFailureAction.decide(result: result, canRestart: canRestart, tapStartedSinceGrant: tapSinceGrant)
        AppLog.info("recovery failed action=\(action) canRestart=\(canRestart) tapSinceGrant=\(tapSinceGrant)")
        logHidAccess(ax: PermissionMonitor.axTrusted(), reason: "recovery-failed")
        switch action {
        case .autoRestart:
            restartMemory.markRestarted()
            if AppRestart.relaunchAfterExit() {
                NSApp.terminate(nil)
            } else {
                stuck = true
            }
        case .showReset:
            stuck = true
        case .showPermissionNeeded:
            // G-08.1-4: 이미 탭을 깔았던 프로세스가 권한을 잃으면 재시작하지 않고 제자리에서 권한 없음을 보인다.
            // 탭이 없으니 Caps 매핑과 #60은 유예 뒤 CapsMappingPolicy가 내린다.
            trusted = false
            grantSession.noteLossShown()
        case .ignore:
            break
        }
        recompute()
    }

    /// L5: 켠 채 철회해도 입력이 멈추지 않도록 판단 전에 탭부터 내린다(GAP-08).
    private func accessibilityChanged() {
        grantSession.noteAccessibilityNotification()
        rebuildGeneration += 1
        recovery.stop()
        tap.uninstall()
        let generation = rebuildGeneration
        AppLog.info("accessibility notify gen=\(generation)")
        if resetting || awaitingRegrant {
            rebuildPending = false
            recompute()
            return
        }
        rebuildPending = true
        // 진행 중 프로브 결과는 알림 전 상태이므로 버린다.
        watchdog.stop()
        watchdog.start()
        recompute()
        DispatchQueue.main.asyncAfter(deadline: .now() + TapRebuildSchedule.firstAttempt) { [weak self] in
            guard let self, self.rebuildGeneration == generation else { return }
            self.rebuildPending = false
            self.logHidAccess(ax: PermissionMonitor.axTrusted(), reason: "notify")
            self.attemptTap { result in
                AppLog.info("rebuild t=0.3 gen=\(generation) result=\(result)")
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + TapRebuildSchedule.finalCheck) { [weak self] in
            guard let self, self.rebuildGeneration == generation else { return }
            AppLog.info("rebuild t=1.5 gen=\(generation) result=\(self.trusted ? "watchdog" : "recovery")")
            if self.trusted {
                self.checkWatchdog()
            } else {
                self.recovery.restart()
            }
        }
    }

    /// 프로브를 부르는 단 하나의 입구.
    private func checkWatchdog() {
        guard !tapBlocked, PermissionMonitor.axTrusted() else { return }
        watchdog.check()
    }

    private func watchdogResult(_ ok: Bool) {
        // 막힌 동안 받은 결과는 버린다. 1.5 s 판단이나 잠금 해제가 다시 묻는다.
        if tapBlocked { return }
        var action = "none"
        if ok {
            if !trusted {
                action = "recover"
                recovery.restart()
            } else if stability.noteSuccess(now: now) {
                restartMemory.clear()
            }
        } else {
            stability.noteFailure()
            if tap.isInstalled || trusted {
                action = "uninstall"
                tap.uninstall()
                trusted = false
                recovery.restart()
            }
            logHidAccess(ax: PermissionMonitor.axTrusted(), reason: "watchdog")
        }
        if ok != lastWatchdogProbe || action != "none" {
            AppLog.info("watchdog probe=\(ok) action=\(action)")
        }
        lastWatchdogProbe = ok
        recompute()
    }

    /// wake는 잡힌 키와 제스처만 초기화한다. 잠금 화면의 프로브 실패가 재시작이나 재설정 패널로 번지지 않게
    /// 프로브·복구는 unlock으로 미룬다. 잠금 없이 깨어난 경우는 다음 10 s 타이머와 tick이 맡는다(L8).
    private func resume(reason: String) {
        AppLog.info("resume reason=\(reason)")
        tap.resetForResume()
        caps.cancelLong()
        repeatGuard.reset()
        // 깨어남에서도 재조정이 돌아야 하므로 wake 분기 앞에 둔다(CAPS-05).
        caps.scheduleRecovery()
        guard reason != "wake" else { return }
        screenLocked = false
        if tap.isInstalled && !tap.isValid { tap.uninstall() }
        if !tap.isInstalled && !tapBlocked && PermissionMonitor.axTrusted() { recovery.restart() }
        checkWatchdog()
        recompute()
    }

    /// 진단 전용(L1). 결과는 로그로만 남고 판정에 쓰지 않는다.
    private func logHidAccess(ax: Bool, reason: String) {
        PermissionMonitor.hidPostEventAccess { hid in
            AppLog.info("permission hid=\(hid) ax=\(ax) reason=\(reason)")
        }
    }

    private func makeSnapshot(status: AppStatus) -> AppSnapshot {
        AppSnapshot(
            status: status, trusted: trusted, enabled: enabled, iconHidden: iconHidden,
            iconVisible: IconVisibility.isVisible(hidden: iconHidden, trusted: trusted),
            cancelOnLongPress: cancelLong, permissionLost: wasTrusted && !trusted,
            login: loginItem.presentation,
            hasActiveList: service.layout.hasActiveList, strategyName: strategy.name,
            globeNotice: strategy is RealGlobeStrategy && GlobeSettingAdvisor.needsNotice(usage: globeUsage),
            permissionPanel: PermissionPanel.resolve(trusted: trusted, stuck: stuck, resetFailed: resetFailed),
            resetting: resetting,
            capsBlocked: caps.capsBlocked,
            capsRows: rows(.caps), fnRows: rows(.fn), assignedRows: rows(.assigned),
            assignedChordText: assignedChordText(), assignedConflictIDs: assignedConflictIDs(),
            assignedTypingIDs: assignedTypingIDs(), hasShortcuts: !shortcutTable.isEmpty,
            unassignedRows: unassignedRowList(),
            pendingNewSourceIDs: pendingIDs, newSourcesMenuTitle: newSourcesTitle(pendingIDs),
            entry: service.layout.entry, capsLongEnabled: capsLongEnabledSetting,
            settleGlobalMs: settleGlobalMs, settleExceptions: settleExceptionList,
            currentSourceID: service.currentID,
            conflictApps: conflictApps, conflictDismissed: bool(Key.conflictDismissed, false),
            appLanguage: appLanguage,
            helpSources: service.sources, systemLanguage: globalSystemLanguage())
    }

    /// macOS 시스템 언어(전역 AppleLanguages의 첫 값). 앱 언어(D-42)는 앱 도메인 값을 쓰므로
    /// 화면·진단의 「시스템 언어」는 전역 값을 따로 읽는다.
    private func globalSystemLanguage() -> String? {
        let key = "AppleLanguages" as CFString
        guard let value = CFPreferencesCopyValue(
            key, kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost),
            let list = value as? [String] else { return nil }
        return list.first
    }

    /// 진단(04.2-05)이 화면과 같은 전역 값을 쓰도록 연다.
    func systemLanguageForDiagnostics() -> String? { globalSystemLanguage() }

    /// 스냅숏만 다시 만든다. recompute(탭 설치, Caps 매핑 재조정)는 부르지 않는다.
    private func refreshSnapshot() {
        #if DEBUG
        if debugSnapshotOverride != nil { return }
        #endif
        let next = makeSnapshot(status: snapshot.status)
        if next != snapshot { snapshot = next }
    }

    #if DEBUG
    /// 렌더 도구 전용. 값이 있으면 스냅숏을 이 값으로 고정한다(recompute·refreshSnapshot이 덮어쓰지 않는다).
    var debugSnapshotOverride: AppSnapshot? {
        didSet { if let s = debugSnapshotOverride { snapshot = s } }
    }
    #endif

    private func displayName(_ id: SourceID) -> String {
        if let s = service.sources.first(where: { $0.id == id }) { return s.localizedName }
        if let n = service.lists?.names[id] { return n }
        return id.split(separator: ".").last.map(String.init) ?? id
    }

    private var liveIDs: Set<SourceID> { Set(service.sources.map(\.id)) }

    private func row(_ id: SourceID) -> SourceRow {
        let name = displayName(id)
        let languages = service.sources.first(where: { $0.id == id })?.languages ?? []
        return SourceRow(
            id: id, name: name, enabled: true,
            glyph: SourceGlyph.text(id: id, languages: languages, name: name))
    }

    /// 켜진 소스만 행으로 만든다. 꺼진 소스는 저장 목록에 자리만 남는다(M2).
    private func rows(_ list: SourceList) -> [SourceRow] {
        guard let lists = service.lists else { return [] }
        let live = liveIDs
        return lists.ids(list).filter { live.contains($0) }.map(row)
    }

    private func unassignedRowList() -> [SourceRow] {
        guard let lists = service.lists else { return [] }
        let live = liveIDs
        return lists.ids(.excluded).filter { live.contains($0) }.map(row)
    }

    // MARK: 지정 단축키 (D-46)

    /// 지정 소스의 표시 문자열. 저장하지 않고 스냅숏을 만들 때마다 다시 계산한다(연구 §4).
    private func assignedChordText() -> [SourceID: String] {
        guard let lists = service.lists else { return [:] }
        var out: [SourceID: String] = [:]
        for id in lists.assigned {
            guard let chord = lists.chords[id] else { continue }
            out[id] = ChordFormatter.text(chord, keyName: KeyNames.character)
        }
        return out
    }

    /// 시스템 기호 단축키와 겹치는 지정 소스. 겹쳐도 저장·동작은 막지 않는다(D-46).
    private func assignedConflictIDs() -> Set<SourceID> {
        guard let lists = service.lists else { return [] }
        return Set(
            lists.assigned.filter { id in
                lists.chords[id].map(systemChords.contains) ?? false
            })
    }

    /// ⇧ 하나짜리 조합으로 대문자 입력을 가로채는 지정 소스(시스템 호출 없이 계산한다).
    private func assignedTypingIDs() -> Set<SourceID> {
        guard let lists = service.lists else { return [] }
        return Set(
            lists.assigned.filter { id in
                lists.chords[id].map(ChordValidation.blocksTyping) ?? false
            })
    }

    /// 시스템 기호 단축키를 읽어 겹침 집합을 새로 만든다. 부르는 곳은 녹화 확정과 창 열기뿐이다.
    private func refreshShortcutConflicts() {
        systemChords = SystemHotkeys.enabledChords()
        refreshSnapshot()
    }

    /// 지정 단축키 녹화를 시작한다. 녹화 중에는 탭이 지정 단축키를 맞추지 않는다(fn·Caps는 그대로).
    func startShortcutRecording() {
        guard !tap.shortcutsPaused else { return }
        tap.shortcutsPaused = true
        AppLog.info("shortcut recording on")
    }

    /// 멱등. 창 닫힘·종료·목록 초기화에서도 부른다(T-04-68).
    func endShortcutRecording() {
        guard tap.shortcutsPaused else { return }
        tap.shortcutsPaused = false
        AppLog.info("shortcut recording off")
    }

    /// 녹화기가 확정 전에 부른다. 시스템에 닿지 않고 표만 본다.
    func validateChord(keyCode: UInt16, flags: UInt64, for id: SourceID) -> ChordValidation.Result {
        ChordValidation.validate(
            keyCode: keyCode, flags: flags, for: id,
            existing: service.lists?.chords ?? [:], reservedKeyCode: tap.capsKeyCode)
    }

    /// 지정 소스의 단축키를 정한다(nil이면 지운다). 같은 조합은 이전 소유자에게서 가져온다(W4).
    func setAssignedChord(_ chord: KeyChord?, for id: SourceID) {
        editLists("chord") { $0.settingChord(chord, for: id) }
        refreshShortcutConflicts()
    }

    /// 목록(caps·fn·excluded)에 있고 켜진 ID만 남긴다(T-04-16). excluded에는 꽉 찬 목록이나
    /// 넘침 때문에 밀려난 새 소스만 들어온다(pendingNewSources는 reconciled의 added만 받는다).
    private var pendingIDs: [SourceID] {
        guard let lists = service.lists else { return [] }
        let valid = lists.known.intersection(liveIDs)
        return pendingNewSourceList.filter { valid.contains($0) }
    }

    private func newSourcesTitle(_ ids: [SourceID]) -> String? {
        guard !ids.isEmpty else { return nil }
        let excluded = service.lists?.excluded ?? []
        let outside = ids.filter(excluded.contains).count
        let inLists = ids.count - outside
        // 04-REVIEW IN-09: 목록과 「사용 안 함」에 나뉘어 들어가면 그 사실을 말한다.
        if inLists > 0, outside > 0 { return LF("menu.newSources.mixed", inLists, outside) }
        if outside == ids.count {
            // 꽉 찬 목록 때문에 「사용 안 함」에 들어간 새 소스(D-30, M1)
            return LF("menu.newSources.outside", ids.count)
        }
        switch ids.count {
        case 1:
            let id = ids[0]
            let listName = service.lists?.caps.contains(id) == true ? L("keys.caps.title") : L("keys.fn.title")
            return LF("menu.newSources.one", listName, displayName(id))
        default: return LF("menu.newSources.many", ids.count)
        }
    }

    /// 탭에 넘길 지정 단축키 맞춤 표. 켜진 지정 소스 중 조합이 있는 것만(조합 값은 로그·진단에 쓰지 않는다).
    private var shortcutTable: [KeyChord: SourceID] {
        service.lists?.chordTable(live: liveIDs) ?? [:]
    }

    /// 멱등.
    private func recompute() {
        let hasActiveList = service.layout.hasActiveList
        let isEnabled = enabled
        // 앱이 꺼졌거나 「FnCaps 끄기」 앱이 맨 앞이면 단축키도 통과시킨다(D-46 사용자 확정).
        // 녹화 중 멈춤은 탭의 matcher.paused가 맡는다.
        let assignedTable = shortcutTable
        tap.assignedShortcuts =
            AssignedShortcutPolicy.isActive(enabled: isEnabled, appOff: appOff) ? assignedTable : [:]
        let hasShortcuts = !assignedTable.isEmpty
        let want = TapInstallPolicy.shouldInstall(
            trusted: trusted, enabled: isEnabled, hasActiveList: hasActiveList, hasShortcuts: hasShortcuts)
        if want && !tap.isInstalled && !tapBlocked {
            if !PermissionMonitor.axTrusted() {
                trusted = false  // ax=false인 동안 tapCreate를 부르지 않는다. 다음 tick이 나머지를 맡는다.
            } else if !tap.install() {
                trusted = false  // 설치 실패 = 미신뢰
                stability.noteFailure()
                recovery.start()  // 소진 뒤에는 무시되므로 고리 없음
            }
        } else if !want && tap.isInstalled && !userRestoring {
            tap.uninstall()
        }
        if tap.isInstalled {
            tapGoneAt = nil
        } else if tapGoneAt == nil {
            tapGoneAt = now
        }
        let fnOn = service.layout.fnListActive
        // 영어가 어느 목록에 있든 길게 누르기가 동작한다(quick 261121-cle). 끈 설정만 본다.
        let longOn = capsLongEnabledSetting
        // 끈 앱에서는 fn을 기존 bypass 경로로 OS에 넘긴다. 사용자 설정값 enabled와 상태 표시는 그대로.
        tap.fnEnabled = service.layout.fnListActive && !appOff
        tap.capsLongEnabled = longOn
        if lastFnEnabled != fnOn {
            lastFnEnabled = fnOn
            AppLog.info("fn enabled=\(fnOn)")
        }
        if lastCapsLongEnabled != longOn {
            lastCapsLongEnabled = longOn
            AppLog.info("caps long enabled=\(longOn)")
        }
        caps.reconcile(target: CapsMappingPolicy.target(
            axTrusted: PermissionMonitor.axTrusted(), enabled: isEnabled, tapInstalled: tap.isInstalled,
            tapAbsentSeconds: tapGoneAt.map { now - $0 } ?? 0, capsListActive: service.layout.capsListActive,
            sessionAway: screenLocked || PermissionMonitor.sessionAway(), appOff: appOff,
            capsTaken: caps.capsBlocked, hasPulseRoute: globe != nil))
        // recovery.start가 안에서 다시 recompute할 수 있으므로 상태는 맨 뒤에 계산한다.
        let status = AppStatus.resolve(
            trusted: trusted, enabled: isEnabled, hasActiveList: hasActiveList, hasShortcuts: hasShortcuts)
        if tap.isInstalled != lastTapInstalled {
            lastTapInstalled = tap.isInstalled
            AppLog.info(lastTapInstalled ? "tap installed" : "tap uninstalled")
        }
        monitor.setInterval(
            PollInterval.seconds(trusted: trusted, tapInstalled: tap.isInstalled, windowOpen: windowOpen))
        let next = makeSnapshot(status: status)
        if next.permissionPanel != snapshot.permissionPanel {
            AppLog.info("permission panel=\(next.permissionPanel)")
        }
        #if DEBUG
        let frozen = debugSnapshotOverride != nil
        #else
        let frozen = false
        #endif
        if !frozen, next != snapshot { snapshot = next }
        if status != lastLoggedStatus {
            lastLoggedStatus = status
            AppLog.info(
                "status=\(status.rawValue) trusted=\(trusted) lists=\(hasActiveList) "
                    + "shortcuts=\(assignedTable.count) tap=\(tap.isInstalled)")
        }
    }

    // MARK: 사용자 동작

    func setEnabled(_ on: Bool) {
        defaults.set(on, forKey: Key.enabled)
        if !on { caps.cancelLong() }
        if on {
            caps.clearBlocked()
            recompute()
            return
        }
        // 끄기: 저장 -> 복원 완료 -> recompute. 복원 중에는 탭 내리기를 미룬다.
        userRestoring = true
        caps.restore(force: true) { [weak self] _ in
            self?.userRestoring = false
            self?.recompute()
        }
        recompute()
    }

    /// 메뉴 「원래대로 되돌리기」(SAFE-03). 꺼짐을 먼저 저장하므로 복원이 도중에 실패해도
    /// 다음 조정은 재적용이 아니라 복원을 재시도한다. 끄기와 달리 보류 상태도 지운다.
    func restoreSystemState() {
        defaults.set(false, forKey: Key.enabled)
        caps.clearPending()
        userRestoring = true
        caps.restore(force: true) { [weak self] _ in
            self?.userRestoring = false
            self?.recompute()
        }
        recompute()
    }

    func setIconHidden(_ hidden: Bool) {
        defaults.set(hidden, forKey: Key.iconHidden)
        recompute()
    }

    // MARK: 키별 목록 편집

    private func editLists(_ op: String, _ note: String = "", _ change: (KeyLists) -> KeyLists) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard let current = service.lists else { return }
        let next = change(current)
        if next == current {
            AppLog.info("lists set op=\(op) refused")  // 꽉 찬 목록 거절(D-30) 등 바뀐 것 없음
            return
        }
        objectWillChange.send()
        service.setLists(next)
        // setLists의 reload가 진입 언어를 더 정리했을 수 있으니 엔진이 조정한 값을 저장한다
        // (wave 3 검토 WR-01, D-08 / 04-REVIEW IN-05: 고치기 전 next를 저장하면 저장값과 엔진이 어긋난다).
        if let encoded = service.lists?.encoded() { defaults.set(encoded, forKey: Key.keyLists) }
        recompute()
        AppLog.info(
            "lists set op=\(op)\(note.isEmpty ? "" : " " + note) "
                + "caps=\(next.caps.count) fn=\(next.fn.count)")
    }

    /// from 목록의 한 칸만 옮긴다(복제는 그대로). index는 대상의 보이는 자리, nil이면 끝.
    /// to가 「사용 안 함」이면 from에서만 뺀다.
    func moveSource(id: SourceID, from: SourceList, to list: SourceList, at index: Int? = nil) {
        editLists("move") { $0.moved(id, from: from, to: list, at: index, live: liveIDs) }
    }

    /// 다른 목록에 하나 더 넣는다(복제, 2026-11-11). 같은 목록·꽉 찬 목록이면 그대로.
    func copySource(id: SourceID, to list: SourceList, at index: Int? = nil) {
        editLists("copy") { $0.copied(id, to: list, at: index, live: liveIDs) }
    }

    /// 그 목록에서만 뺀다. 남은 복제가 없으면 「사용 안 함」으로 간다.
    func removeSource(id: SourceID, from list: SourceList) {
        editLists("remove") { $0.removed(id, from: list) }
    }

    func nudgeSource(id: SourceID, in list: SourceList, by delta: Int) {
        // 꺼진(숨은) 소스를 건너뛰고 보이는 이웃과 자리를 바꾼다(M2).
        let live = liveIDs
        editLists("nudge") { lists in
            let visible = lists.ids(list).filter { live.contains($0) }
            guard let i = visible.firstIndex(of: id), visible.indices.contains(i + delta) else { return lists }
            return lists.moved(id, from: list, to: list, at: i + delta, live: live)
        }
    }

    // MARK: 설정

    /// 「일반」 충돌 앱 경고의 X(2026-11-13). 권한이 풀릴 때까지 다시 보이지 않는다.
    func dismissConflictWarning() {
        objectWillChange.send()
        defaults.set(true, forKey: Key.conflictDismissed)
        recompute()
    }

    /// 키별 진입 언어(D-01). 별도 저장 키 없이 keyLists.v1에 함께 저장된다.
    /// `settingEntry`는 그 키 목록에 없는 `.source`를 거절하므로 목록 밖 ID는 저장되지 않는다.
    func setEntry(_ key: TriggerKey, _ value: EntryLanguage) {
        editLists("entry", "key=\(key.rawValue) entry=\(value.storageText)") {
            $0.settingEntry(value, for: key)
        }
    }

    // MARK: 권장 후보 적용 (04.4, D-09~D-11)

    /// 확인 창이 보일 값(「사용 안 함 N개」, 직접 정할 단축키). 목록을 아직 읽지 못했으면 nil.
    func candidatePreview(_ plan: GuidancePlan) -> CandidatePreview? {
        guard let lists = service.lists else { return nil }
        return lists.candidatePreview(plan, live: liveIDs)
    }

    /// D-09: 후보의 Caps·fn·지정 목록과 두 키의 진입 언어를 한 번에 적용한다.
    /// 목록·진입 언어·저장이 `editLists` 한 번을 지나므로 중간 상태가 엔진·저장에 새지 않는다.
    /// D-10: 조합키를 새로 넣지 않는다(`applying`이 기존 `chords`만 넘긴다).
    /// T-04.4-07: 녹화 중이면 먼저 끝낸다(멱등). T-04.4-08: 로그에는 개수와 진입 값만 남긴다.
    /// 반환값: 목록을 읽어 적용 계산이 돌았으면 true(이미 같은 배치여도 true), 목록을 아직 못 읽었으면 false(WR-05).
    @discardableResult
    func applyCandidate(_ plan: GuidancePlan) -> Bool {
        guard service.lists != nil else {
            AppLog.info("candidate apply skipped lists=nil")
            return false
        }
        endShortcutRecording()
        let live = liveIDs
        let note = "caps=\(plan.caps.count) fn=\(plan.fn.count) assigned=\(plan.assigned.count)"
            + " entry=caps:\(plan.entry.caps.storageText),fn:\(plan.entry.fn.storageText)"
        editLists("candidate", note) { $0.applying(plan, live: live) }
        refreshShortcutConflicts()
        return true
    }

    private var capsLongEnabledSetting: Bool { bool(Key.capsLongEnabled, true) }

    func setCapsLongEnabled(_ on: Bool) {
        objectWillChange.send()
        defaults.set(on, forKey: Key.capsLongEnabled)
        recompute()
    }

    /// 전환 뒤 키를 붙잡는 전역 대기 시간(0~150 ms). 전환마다 읽으므로 바로 적용된다.
    func setSettleGlobalMs(_ ms: Int) {
        objectWillChange.send()
        defaults.set(SettleTimePolicy.clamp(ms), forKey: Key.keyHoldSettleMs)
        recompute()
    }

    /// 앱 번들의 Info.plist에서 번들 ID만 읽는다. 앱을 실행하지 않는다(T-04-15).
    func addSettleException(appURL: URL) -> Bool {
        guard let id = Bundle(url: appURL)?.bundleIdentifier, SettleExceptions.isValidBundleID(id) else { return false }
        guard let result = SettleExceptions.adding(settleExceptionList, bundleID: id) else {
            return false
        }
        saveSettleExceptions(result.list)
        return true
    }

    func removeSettleException(bundleID: String) {
        saveSettleExceptions(SettleExceptions.removing(settleExceptionList, bundleID: bundleID))
    }

    private func saveSettleExceptions(_ list: [SettleException]) {
        objectWillChange.send()
        defaults.set(SettleExceptions.encoded(list), forKey: Key.settleExceptions)
        updateAppOff(recomputeAlways: true)
    }

    // MARK: 앱별 끄기, 충돌 앱

    private func startWorkspaceObservers() {
        let ws = NSWorkspace.shared
        let center = ws.notificationCenter
        frontBundleID = ws.frontmostApplication?.bundleIdentifier
        appOff = SettleTimePolicy.isOff(exceptions: settleExceptionList, frontBundleID: frontBundleID)
        if appOff { AppLog.info("app off on=true") }
        conflictApps = ConflictApps.detected(runningBundleIDs: ws.runningApplications.compactMap(\.bundleIdentifier))
        workspaceObservers.append(center.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            self?.frontBundleID = app?.bundleIdentifier
            self?.updateAppOff(recomputeAlways: false)
        })
        // 백그라운드 에이전트에도 두 알림이 오는지는 확인되지 않았다. 설정창을 열 때 다시 읽는 것이 대비책.
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            workspaceObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.refreshConflicts()
            })
        }
    }

    /// 값이 바뀔 때만 Caps 경로를 다시 맞춘다(T-04-58). 번들 ID는 로그에 남기지 않는다.
    private func updateAppOff(recomputeAlways: Bool) {
        let next = SettleTimePolicy.isOff(exceptions: settleExceptionList, frontBundleID: frontBundleID)
        if next != appOff {
            appOff = next
            caps.cancelLong()
            AppLog.info("app off on=\(appOff)")
            recompute()
        } else if recomputeAlways {
            recompute()
        }
    }

    private func refreshConflicts() {
        let next = ConflictApps.detected(
            runningBundleIDs: NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        guard next != conflictApps else { return }
        // 충돌 앱이 새로 켜지면 닫아 둔 경고를 다시 보인다(05-11 UAT 사용자 결정).
        if !Set(next).subtracting(conflictApps).isEmpty, bool(Key.conflictDismissed, false) {
            defaults.set(false, forKey: Key.conflictDismissed)
        }
        conflictApps = next
        AppLog.info("conflict apps=\(next.joined(separator: ","))")
        recompute()
    }

    // MARK: 초기화 (FINAL-REVIEW §3-1 D)

    /// 키 목록만 기본 구성(D-05/D-22)으로 되돌린다. 끈 소스의 기억된 자리도 사라진다.
    /// 지정 목록과 단축키도 함께 지워진다(KeyLists.initial).
    func resetKeyLists() {
        endShortcutRecording()
        editLists("reset") { _ in KeyLists.initial(for: service.sources) }
        objectWillChange.send()
        defaults.removeObject(forKey: Key.pendingNewSources)
        AppLog.info("settings reset scope=lists")
        recompute()
    }

    /// 「고급」 쪽 설정 키만 지우고 키 목록을 기본으로 되돌린다.
    /// 지우지 않는 것: enabled, menuBarIconHidden, 로그인 항목, AppleLanguages, update.*, keyHold,
    /// 권한 프롬프트 기록, hasLaunchedBefore, 옛 설정 키, keyLists 보관본.
    func resetAllSettings() {
        objectWillChange.send()
        for key in Self.advancedKeys { defaults.removeObject(forKey: key) }
        tap.cancelOnLongPress = false
        tap.capsLongDelay = Double(CapsPressJudge.defaultMs) / 1000
        AppLog.info("settings reset scope=all")
        updateAppOff(recomputeAlways: false)
        resetKeyLists()
    }

    private static let advancedKeys = [
        Key.outsideRule, Key.capsLongEnabled, Key.capsLongPressMs, Key.capsLongLayoutsOnly,
        Key.cancelOnLongPress, Key.keyHoldSettleMs, Key.settleExceptions,
    ]

    // MARK: 앱 언어 (D-42)

    /// 앱 도메인만 읽는다. standard.object(forKey:)는 전역·인수 도메인 값이 섞이므로 쓰지 않는다(ADDENDUM L5).
    var appLanguage: AppLanguage {
        let domain = defaults.persistentDomain(forName: Bundle.main.bundleIdentifier ?? "")
        return AppLanguage.from(stored: domain?[AppLanguage.defaultsKey] as? [String])
    }

    /// 다시 열 때 적용된다. 다른 저장 키를 만들지 않는다.
    func setAppLanguage(_ lang: AppLanguage) {
        objectWillChange.send()
        if let values = lang.appleLanguages {
            defaults.set(values, forKey: AppLanguage.defaultsKey)
        } else {
            defaults.removeObject(forKey: AppLanguage.defaultsKey)
        }
        AppLog.info("app language set=\(lang.rawValue)")
        refreshSnapshot()
    }

    // MARK: 진단 정보 (FINAL-REVIEW §3-1 F)

    /// D-32: 번들 ID·지정 조합 포함(T-04-56·T-04-64 대체). 메모·메일은 넣지 않는다(D-40).
    /// 복사는 화면이 한다. 메인 스레드에서만 부른다. IOHID 열거·hidutil 읽기가 있어
    /// 쪽이 나타날 때 한 번만 부른다.
    func diagnosticsText() -> String {
        let info = Bundle.main.infoDictionary ?? [:]
        let list = settleExceptionList
        var status = snapshot.status.rawValue
        if snapshot.capsBlocked { status += " capsBlocked" }
        let settings: [String: String] = [
            "enabled": String(enabled),
            "capsLongEnabled": String(capsLongEnabledSetting),
            "capsLongPressMs": String(capsLongPressMs),
            "capsLongLayoutsOnly": String(capsLongLayoutsOnly),
            "cancelOnLongPress": String(cancelLong),
            "settleGlobalMs": String(settleGlobalMs),
            "appRulesOff": String(list.count),
            "entryCaps": service.layout.entry.caps.storageText,
            "entryFn": service.layout.entry.fn.storageText,
            "language": appLanguage.rawValue,
            "conflictApps": conflictApps.joined(separator: ","),
            "assignedShortcuts": String(service.lists?.chords.count ?? 0),
        ]
        let chords = service.lists?.chords ?? [:]
        let assignedChords = chords.keys.sorted().compactMap { id -> String? in
            guard let chord = chords[id] else { return nil }
            return "\(id) \(snapshot.assignedChordText[id] ?? "-") (keyCode \(chord.keyCode) mods \(chord.modifiers))"
        }
        let appRows = list.sorted { $0.bundleID < $1.bundleID }
        var userKeyMapping: [String] = []
        var seenMappings = Set<String>()
        for device in KeyboardMapper.keyboards() ?? [] {
            for m in (try? device.readMappings()) ?? [] {
                let line = "0x" + String(m.src, radix: 16, uppercase: true)
                    + "->0x" + String(m.dst, radix: 16, uppercase: true)
                if seenMappings.insert(line).inserted { userKeyMapping.append(line) }
            }
        }
        let input = DiagnosticsInput(
            appVersion: info["CFBundleShortVersionString"] as? String ?? "-",
            build: info["CFBundleVersion"] as? String ?? "-",
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            strategy: strategy.name, status: status,
            sources: service.sources.map { DiagnosticsSource(id: $0.id, name: $0.localizedName) },
            caps: service.lists?.caps ?? [], fn: service.lists?.fn ?? [],
            notUsed: service.lists?.excluded ?? [], assigned: service.lists?.assigned ?? [],
            settings: settings, logLines: AppLog.recentLines(),
            assignedChords: assignedChords,
            appsOff: appRows.map(\.bundleID),
            appsSettle: appRows.map { "\($0.bundleID) \($0.ms)" },
            loginItem: String(describing: snapshot.login),
            appLanguage: appLanguage.rawValue,
            systemLanguage: systemLanguageForDiagnostics() ?? "-",
            globeUsage: globeUsage.map(String.init) ?? "nil",
            hotkey60: SymbolicHotkeyReader.status(id: 60).note(id: 60),
            userKeyMapping: userKeyMapping,
            accessibility: String(trusted),
            macModel: MachineInfoReader.macModel(),
            keyboards: ["layout " + MachineInfoReader.layoutType()] + MachineInfoReader.keyboards())
        return DiagnosticsReport.text(input)
    }

    func markNewSourcesSeen() {
        objectWillChange.send()
        defaults.removeObject(forKey: Key.pendingNewSources)
        recompute()
    }

    /// Caps 길게 누르기 기준 시간(ms). 300~1000으로 자른다. 다음 누름부터 적용된다.
    var capsLongPressMs: Int {
        CapsPressJudge.clampMs(defaults.object(forKey: Key.capsLongPressMs) as? Int ?? CapsPressJudge.defaultMs)
    }

    func setCapsLongPressMs(_ ms: Int) {
        objectWillChange.send()
        let v = CapsPressJudge.clampMs(ms)
        defaults.set(v, forKey: Key.capsLongPressMs)
        tap.capsLongDelay = Double(v) / 1000
    }

    /// true면 입력기에서 길게 눌러도 아무 일도 없고, 일반 자판에서는 언어를 바꾸지 않고 잠금만 바꾼다.
    var capsLongLayoutsOnly: Bool { bool(Key.capsLongLayoutsOnly, false) }

    func setCapsLongLayoutsOnly(_ on: Bool) {
        objectWillChange.send()
        defaults.set(on, forKey: Key.capsLongLayoutsOnly)
    }

    func setCancelOnLongPress(_ on: Bool) {
        defaults.set(on, forKey: Key.cancelOnLongPress)
        tap.cancelOnLongPress = on
        recompute()
    }

    func setLoginItem(_ on: Bool) {
        loginItem.setEnabled(on)
        recompute()
    }

    func openAccessibilitySettings() {
        switch PermissionButton.action(didRequestPrompt: promptMemory.shown) {
        case .prompt:
            PermissionMonitor.requestPrompt()
            promptMemory.markShown()
            AppLog.info("permission button action=prompt persisted=\(promptMemory.shown)")
        case .openSettings:
            _ = PermissionMonitor.openAccessibilitySettings()
            AppLog.info("permission button action=openSettings persisted=\(promptMemory.shown)")
        }
    }

    /// 설정 창의 재설정 버튼에서만 부른다(L6). 자동 경로는 없다.
    func resetPermission() {
        guard snapshot.permissionPanel == .stuck || snapshot.permissionPanel == .stuckResetFailed,
            !resetting
        else { return }
        rebuildPending = false
        resetFailed = false
        resetting = true
        recovery.stop()
        tap.uninstall()
        recompute()
        PermissionReset.run(bundleID: Bundle.main.bundleIdentifier ?? "") { [weak self] failed in
            guard let self else { return }
            self.resetting = false
            self.awaitingRegrant = true
            AppLog.info("permission reset failed=\(failed)")
            if failed.contains("Accessibility") {
                self.resetFailed = true
                _ = PermissionMonitor.openAccessibilitySettings()  // −/+ 안내에 필요
            } else {
                // PostEvent만 실패해도 같게 처리한다. 설정 화면은 grant 패널 버튼으로 연다.
                PermissionMonitor.requestPrompt()
                self.promptMemory.markShown()
                self.stuck = false
            }
            self.recompute()
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
                // ax가 여전히 참이면 재설정이 효과 없던 경우다. 거짓이면 사용자가 허용할 때까지 기다린다.
                guard let self, self.awaitingRegrant, !self.resetting, PermissionMonitor.axTrusted() else { return }
                self.awaitingRegrant = false
                self.recovery.restart()
                self.recompute()
            }
        }
    }

    func openLoginItemsSettings() {
        loginItem.openSystemSettings()
    }

    func setWindowOpen(_ open: Bool) {
        windowOpen = open
        if open {
            refreshConflicts()
            refreshShortcutConflicts()
        } else {
            // 녹화가 남아 단축키가 영영 멈추는 일을 막는다(T-04-68).
            endShortcutRecording()
        }
        tick()
    }

    func refreshLoginStatus() {
        recompute()
    }

    func shutdown() {
        endShortcutRecording()
        recovery.stop()
        watchdog.stop()
        watchdogTimer?.invalidate()
        watchdogTimer = nil
        tap.uninstall()
        monitor.stop()
        for o in workspaceObservers { NSWorkspace.shared.notificationCenter.removeObserver(o) }
        workspaceObservers.removeAll()
    }
}
