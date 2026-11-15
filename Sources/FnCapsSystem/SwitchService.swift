import Carbon
import Foundation
import FnCapsCore

/// Engine host: catalog + classifier + tracker + coordinator + strategy + notifications.
/// Main thread only. Does not intercept keys (Phase 2/3).
/// 켜진 소스의 기준: `freshList`가 있으면 새 프로세스 목록을 쓰고, 앱 안 TIS는 시작할 때 한 번만 읽는다.
/// 앱 안 TIS는 삭제를 못 보고 지운 소스를 되살리기 때문이다(02-20 1부). 알림이 오면 `DebouncedRefresh`가
/// 새 프로세스를 읽어 바뀐 목록만 반영한다. 선택 실패(-50)가 연속되면 해당 소스를 제외한다(보조 경로).
/// `freshList`가 nil이면(FnCapsSpike, 테스트) 앱 안 TIS를 알림 즉시 + 300 ms 뒤에 다시 읽는다.
public final class SwitchService {
    public let catalog: InputSourceCatalog
    public var strategy: SwitchStrategy
    public private(set) var sources: [SourceInfo] = []
    public private(set) var classified: ClassifiedSources
    /// 키별 목록(Caps, fn). nil이면 아직 이전 전이다. 저장은 AppModel이 `onListsChanged`로 한다.
    public private(set) var lists: KeyLists?
    /// 옛 설정 이전 입력. AppModel이 start 전에 넣는다. 옛 키는 지우지 않는다.
    public var legacyCapsSourceID: SourceID?
    public var legacyFnModeKeys: [String]?
    /// 옛 전역 규칙 값의 이전 입력(04.3 D-03). AppModel이 start 전에 넣는다. 옛 키는 지우지 않는다.
    public var legacyEntry: EntryLanguage = .next
    public private(set) var layout: KeyLayout = .empty
    private var started = false
    public var tracker: ListTracker { pipeline.tracker }
    /// 목록이 바뀌어 저장해야 할 때. `added`는 새로 켜져 목록 끝에 들어간 소스다(첫 이전은 비어 있다).
    public var onListsChanged: ((KeyLists, _ added: [SourceID]) -> Void)?
    public var onChange: (() -> Void)?
    public var onSelectedChangeTimestamp: ((CFAbsoluteTime, SourceID?) -> Void)?
    /// Called on every selected-source change, including FnCaps's own switches (heuristic reset, D-17).
    public var onSelectedChanged: ((SourceID?) -> Void)?
    /// Called when the last queued switch has finished (normal, timeout or vanished source).
    public var onIdle: (() -> Void)?

    private let notifications = SourceNotifications()
    private let log: (String) -> Void
    private var pipeline = SwitchPipeline()
    private var completions: [SwitchPipeline.Token: (SwitchOutcome) -> Void] = [:]
    /// Watchdog for a strategy that never calls its completion. Derived from the strategy's own signal
    /// limits so the Caps hop's worst case (1560 ms) never outlives it (04-REVIEW WR-02).
    private var watchdogSeconds: Double { SignalTiming.switchWatchdogMs / 1000 }
    private var rejected = RejectedSources()
    private let delayedReloadSeconds = 0.3
    /// 새 프로세스가 준 목록. `refresh`가 있으면 start 뒤로 항상 값이 있다.
    private var authoritative: [SourceInfo]?
    private var refresh: DebouncedRefresh?

    public var isSwitching: Bool { pipeline.isSwitching }
    public var currentID: SourceID? {
        dispatchPrecondition(condition: .onQueue(.main))
        return catalog.currentID()
    }

    public init(
        catalog: InputSourceCatalog = InputSourceCatalog(), strategy: SwitchStrategy,
        freshList: ((@escaping ([SourceInfo]?) -> Void) -> Void)? = nil,
        log: @escaping (String) -> Void = { _ in }
    ) {
        self.catalog = catalog
        self.strategy = strategy
        self.log = log
        self.classified = SourceClassifier.classify([])
        if let freshList {
            refresh = DebouncedRefresh(
                schedule: { delay, work in DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work) },
                read: freshList,
                apply: { [weak self] list in
                    self?.authoritative = list
                    self?.reload(reason: "fresh")
                })
        }
    }

    /// 저장된 목록을 넣는다. 값이 다르면 반영하고, 시작 뒤라면 다시 풀이한다.
    public func setLists(_ next: KeyLists) {
        guard lists != next else { return }
        lists = next
        if started { reloadSources() }
    }

    public func start() {
        dispatchPrecondition(condition: .onQueue(.main))
        reloadSources()
        started = true
        // 첫 새 프로세스 결과가 이 값과 같으면 apply가 불리지 않는다. 여기서 정하지 않으면 authoritative가
        // nil로 남아 이후 reload가 앱 안 TIS로 돌아가고 유령 소스(9개, modes=6)가 들어온다.
        if refresh != nil { authoritative = sources }
        pipeline.seed(
            current: catalog.currentID(), history: catalog.historySourceIDs(among: sources),
            layout: layout)
        refresh?.seed(sources)
        notifications.onSelectedChanged = { [weak self] in self?.selectedChanged() }
        notifications.onEnabledChanged = { [weak self] in self?.enabledSourcesChanged() }
        notifications.start()
        log("base=\(classified.base) foreign=\(classified.foreign) unclassified=\(classified.unclassified)")
        log(
            "caps=\(lists?.caps ?? []) fn=\(lists?.fn ?? []) excluded=\(lists?.excluded ?? []) "
                + "assigned=\(lists?.assigned ?? []) entry=\(lists?.entry.storageText ?? EntryChoices().storageText)")
        log("enabledPrefIDs=\(catalog.enabledPrefIDs())")
        refresh?.trigger()  // 시작 직후에도 새 프로세스 기준으로 맞춘다.
    }

    public func reloadSources() {
        reload(reason: "explicit")
    }

    private func reload(reason: String) {
        dispatchPrecondition(condition: .onQueue(.main))
        // A3: 선택 실패(-50)를 적용하기 전에 읽은 켜진 목록. 진입 언어 정리는 이 목록으로 한다.
        let enabled = authoritative ?? catalog.loadEnabled()
        sources = rejected.apply(enabled)
        classified = SourceClassifier.classify(sources)
        if let current = lists {
            let (next, added) = current.reconciled(with: sources, enabled: enabled)
            if next != current {
                lists = next
                onListsChanged?(next, added)
            }
        } else if !sources.isEmpty {
            let migrated = KeyLists.first(
                sources: sources, legacyCapsSourceID: legacyCapsSourceID,
                legacyFnModeKeys: legacyFnModeKeys, legacyEntry: legacyEntry)
            lists = migrated
            onListsChanged?(migrated, [])
        }
        layout = KeyLayout(
            caps: lists?.caps ?? [], fn: lists?.fn ?? [], assigned: lists?.assigned ?? [],
            sources: sources, entry: lists?.entry ?? EntryChoices())
        pipeline.reconcile(layout: layout)
        onChange?()
        log(
            "sources reloaded reason=\(reason) caps=\(layout.sources(for: .caps).count) "
                + "fn=\(layout.sources(for: .fn).count) rejected=\(rejected.ids.count)")
    }

    private func enabledSourcesChanged() {
        rejected.clear()
        reload(reason: "notify")  // refresh가 있으면 authoritative를 쓰므로 유령 소스가 들어오지 않는다.
        if let refresh {
            refresh.trigger()
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + delayedReloadSeconds) { [weak self] in
            self?.reload(reason: "delayed")
        }
    }

    private func selectedChanged() {
        let now = CFAbsoluteTimeGetCurrent()
        let current = catalog.currentID()
        if let current, rejected.contains(current) {
            rejected.unreject(current)
            reload(reason: "reselected")
        }
        onSelectedChangeTimestamp?(now, current)
        onSelectedChanged?(current)
        if isSwitching { return }
        if let current { pipeline.observeUser(selected: current, layout: layout) }
        onChange?()
    }

    /// Requests a switch. `completion` is called exactly once: normal finish, superseded,
    /// flushed (already there), timeout or unknown_source.
    public func switchTo(_ id: SourceID, completion: ((SwitchOutcome) -> Void)? = nil) {
        dispatchPrecondition(condition: .onQueue(.main))
        var target = sources.first { $0.id == id }
        if target == nil {
            reloadSources()
            target = sources.first { $0.id == id }
        }
        guard target != nil else {
            refresh?.trigger()
            log("switchTo: unknown source \(id)")
            completion?(SwitchOutcome(tisLanded: false, tisLatencyMs: 0, notes: "unknown_source"))
            return
        }
        handleRequest(pipeline.request(id, layout: layout), completion: completion)
    }

    @discardableResult
    public func handle(_ key: TriggerKey) -> Decision {
        dispatchPrecondition(condition: .onQueue(.main))
        let result = pipeline.press(key, actual: catalog.currentID(), layout: layout)
        if let request = result.request { handleRequest(request, completion: nil) }
        return result.decision
    }

    public func preview(_ key: TriggerKey) -> Decision {
        dispatchPrecondition(condition: .onQueue(.main))
        return pipeline.preview(key, actual: catalog.currentID(), layout: layout)
    }

    /// 지정 단축키(D-46) 대상 미리보기. 지금 소스가 이미 대상이면 `.noop`이고 상태를 바꾸지 않는다.
    public func previewAssigned(_ id: SourceID) -> Decision {
        dispatchPrecondition(condition: .onQueue(.main))
        return pipeline.previewAssigned(id, actual: catalog.currentID(), layout: layout)
    }

    public func recentHistory() -> [SourceID] {
        dispatchPrecondition(condition: .onQueue(.main))
        return catalog.historySourceIDs(among: sources)
    }

    private func handleRequest(
        _ request: SwitchPipeline.RequestResult, completion: ((SwitchOutcome) -> Void)?
    ) {
        let token: SwitchPipeline.Token
        var superseded: [SwitchPipeline.Token] = []
        var start: (SourceID, SwitchPipeline.RunID)?
        switch request {
        case .start(let id, let run, let t):
            token = t
            start = (id, run)
        case .queued(let t, let s), .joined(let t, let s):
            token = t
            superseded = s
        }
        if let completion { completions[token] = completion }
        resolve(superseded, outcome: SwitchOutcome(tisLanded: false, tisLatencyMs: 0, notes: "superseded"))
        if let (id, run) = start { self.run(id, run) }
    }

    private func resolve(_ tokens: [SwitchPipeline.Token], outcome: SwitchOutcome) {
        for t in tokens {
            if let c = completions.removeValue(forKey: t) { c(outcome) }
        }
    }

    private func run(_ id: SourceID, _ runID: SwitchPipeline.RunID) {
        guard let target = sources.first(where: { $0.id == id }) else {
            log("run: source vanished \(id)")
            finish(
                pipeline.completed(run: runID, actual: catalog.currentID(), layout: layout),
                outcome: SwitchOutcome(tisLanded: false, tisLatencyMs: 0, notes: "unknown_source"))
            return
        }
        let origin = catalog.currentID().flatMap { cur in sources.first { $0.id == cur } }
        let strat = strategy
        DispatchQueue.main.asyncAfter(deadline: .now() + watchdogSeconds) { [weak self] in
            guard let self else { return }
            let c = self.pipeline.timedOut(
                run: runID, actual: self.catalog.currentID(), layout: self.layout)
            if c.finished.isEmpty { return }  // already finished normally
            self.log("\(strat.name) -> \(target.id) timeout")
            self.finish(
                c,
                outcome: SwitchOutcome(
                    tisLanded: false, tisLatencyMs: self.watchdogSeconds * 1000, notes: "timeout"))
        }
        strat.switchTo(target, from: origin, catalog: catalog) { [weak self] outcome in
            guard let self else { return }
            let c = self.pipeline.completed(
                run: runID, actual: self.catalog.currentID(), layout: self.layout)
            if c.finished.isEmpty {
                self.log("\(strat.name) -> \(target.id) late completion ignored")
                return
            }
            self.log(
                "\(strat.name) -> \(target.id) landed=\(outcome.tisLanded) "
                    + "ms=\(String(format: "%.1f", outcome.tisLatencyMs)) \(outcome.notes)")
            if outcome.tisLanded {
                self.rejected.noteSuccess(target.id)
                self.finish(c, outcome: outcome)
                return
            }
            if SelectFailure.indicatesMissingSource(outcome.notes) {
                if self.rejected.noteFailure(target.id) {
                    self.log("source rejected \(target.id) hint=select-or-readd")
                    self.reload(reason: "rejected")
                    self.finish(c, outcome: outcome)
                    return
                }
                self.log("source select failed \(target.id) streak=1")
            }
            self.finish(c, outcome: outcome)
        }
    }

    private func finish(_ c: SwitchPipeline.Completion, outcome: SwitchOutcome) {
        resolve(c.finished, outcome: outcome)
        onChange?()
        if let next = c.next { run(next.id, next.run) } else { onIdle?() }
    }
}
