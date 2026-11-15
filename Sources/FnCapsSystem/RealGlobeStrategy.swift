// Caps 경로 구조 참고: gksdud main.swift nativeSwitchPulse (MIT)
import Carbon
import CoreGraphics
import Foundation
import FnCapsCore

/// S10-RealGlobe (제품 기본 전략, FN-07, 사용자 결정 2026-10-29): 진짜 fn 해제와 🌐(179)을 OS에 넘겨
/// OS의 「🌐 키로 입력 소스 변경」이 직접 전환하게 한다. 직전 소스가 목표가 아닐 때만 TIS로
/// 목표 -> 원래 순서로 골라 최근 사용 순서를 맞춘다(준비). 메인 스레드 전용.
///
/// 「무장(arm)」된 목표만 OS 직접 전환을 기다린다. 무장되지 않은 요청(연타, 줄 선 전환,
/// 🌐 설정이 1이 아님)은 준비 없이 TIS로 바로 간다.
public final class RealGlobeStrategy: SwitchStrategy {
    public let name = "S10-RealGlobe"
    /// 준비 직후 현재 소스를 믿기 전에 목표로 이어서 읽혀야 하는 시간(추정값, 2026-11-04 로그).
    public let primedStableMs: Double
    public init(primedStableMs: Double = 30) {
        self.primedStableMs = primedStableMs
    }

    public private(set) var recent = RecentSources()
    public private(set) var preparedTarget: SourceID?
    public private(set) var armedTarget: SourceID?
    private var preparedNote = ""
    private var primed = false
    private let inApp = TISReselectStrategy()

    /// Caps(F 키) 누름이 무장한 전환. 한 번 쓰면 지워진다.
    private struct CapsArm {
        let target: SourceID
        let keyCode: CGKeyCode
        let press: CGEvent?
        let capsOn: Bool
        let pressedAt: CFAbsoluteTime
        /// 전환 판정 이유(release, key, long). 로그의 `plan=` 줄에 붙는다.
        let trigger: String
        /// 단계 기록 기준(순번, 판정 시각).
        let trace: StepTrace
    }
    private var capsArmed: CapsArm?
    private var capsSeq = 0
    /// 마지막 Caps 판정의 기록 창(판정 뒤 1초, plan B가 돌면 그 시작부터 1초). 창 안의 실제 소스 변경만 기록한다.
    private var stepWindow: StepTrace?
    /// 마지막 무장 fn 전환의 기록 창. plan B가 돌 때만 열린다. Caps 창과 순번이 달라 `capsFallback`의
    /// seq 비교에 섞이면 안 되므로 따로 둔다. 다음 fn 눌림의 `clearPreparation`이 지우면 늦은 착지가
    /// 안 보이므로 거기서 지우지 않는다.
    private var fnStepSeq = 0
    private var fnStepWindow: StepTrace?
    /// Caps 단계 기록 출력. 없으면 기록하지 않는다.
    public var log: ((String) -> Void)?

    /// Caps 전환 판정을 무장한다. 다음 `switchTo`가 이 대상이면 F 키 펄스로 OS가 직접 전환하게 한다.
    /// `pressedAt`은 전환 판정 시각(뗌 또는 다른 키)이다.
    public func armCaps(
        target: SourceID, keyCode: CGKeyCode, press: CGEvent?, capsOn: Bool, pressedAt: CFAbsoluteTime,
        trigger: String
    ) {
        capsSeq += 1
        capsArmed = CapsArm(
            target: target, keyCode: keyCode, press: press, capsOn: capsOn, pressedAt: pressedAt, trigger: trigger,
            trace: StepTrace(label: "caps step", seq: capsSeq, decidedAt: pressedAt))
    }

    public func seed(current: SourceID?, history: [SourceID]) {
        recent.seed(current: current, history: history)
    }

    public func observe(selected: SourceID?) {
        recent.observe(selected: selected)
        guard let log else { return }
        let now = CFAbsoluteTimeGetCurrent()
        if let trace = stepWindow {
            if trace.isInWindow(at: now) { log(trace.line(sourceEvent(selected), at: now)) } else { stepWindow = nil }
        }
        if let trace = fnStepWindow {
            if trace.isInWindow(at: now) { log(trace.line(sourceEvent(selected), at: now)) } else { fnStepWindow = nil }
        }
    }

    private func sourceEvent(_ selected: SourceID?) -> String {
        "source id=\(Self.word(selected)) recentCurrent=\(Self.word(recent.current)) recentPrevious=\(Self.word(recent.previous))"
    }

    private static func word(_ id: SourceID?) -> String { id ?? "nil" }

    /// Caps 단계 줄 하나. log가 없으면 event를 평가하지 않는다.
    private func step(_ caps: CapsArm, _ event: @autoclosure () -> String) {
        guard let log else { return }
        log(caps.trace.line(event(), at: CFAbsoluteTimeGetCurrent()))
    }

    /// fn 단계 줄 하나. log가 없으면 event를 평가하지 않는다.
    private func fnStep(_ trace: StepTrace, _ event: @autoclosure () -> String) {
        guard let log else { return }
        log(trace.line(event(), at: CFAbsoluteTimeGetCurrent()))
    }

    /// fn 해제 콜백 안에서 부른다(채택값 release, 02-25). 콜백 안 TIS 호출은
    /// FnTap 규칙의 예외로 S10 준비에만 허용한다(사용자 결정 2026-10-29).
    @discardableResult
    public func prepare(
        target: SourceInfo, origin: SourceInfo?, catalog: InputSourceCatalog, at timing: PrimeTiming
    ) -> String {
        let t = timing.rawValue
        primed = false
        guard let origin, origin.id != target.id,
            let tsrc = catalog.tisSource(for: target.id),
            let osrc = catalog.tisSource(for: origin.id)
        else {
            return remember(target.id, "prime=none at=\(t)")
        }
        if PrimeDecision.decide(target: target.id, origin: origin.id, recent: recent) == .skip {
            return remember(target.id, "prime=skip at=\(t)")
        }
        let start = CFAbsoluteTimeGetCurrent()
        let s1 = TISSelectInputSource(tsrc)
        let s2 = TISSelectInputSource(osrc)
        let ms = (CFAbsoluteTimeGetCurrent() - start) * 1000
        primed = true
        return remember(target.id, "prime=\(s1)/\(s2) primeMs=\(String(format: "%.1f", ms)) at=\(t)")
    }

    private func remember(_ id: SourceID, _ note: String) -> String {
        preparedTarget = id
        preparedNote = note
        return note
    }

    public func arm(target: SourceID) { armedTarget = target }

    /// 무장만 지운다(준비 기록은 남김).
    public func disarm() { armedTarget = nil }

    public func clearPreparation() {
        preparedTarget = nil
        armedTarget = nil
        capsArmed = nil
        preparedNote = ""
        primed = false
    }

    public func switchTo(
        _ target: SourceInfo, from origin: SourceInfo?, catalog: InputSourceCatalog,
        completion: @escaping (SwitchOutcome) -> Void
    ) {
        dispatchPrecondition(condition: .onQueue(.main))
        let caps = capsArmed
        capsArmed = nil
        if let caps, caps.target == target.id {
            switchCaps(caps, target: target, from: origin, catalog: catalog, completion: completion)
            return
        }
        let start = CFAbsoluteTimeGetCurrent()
        guard armedTarget == target.id else {
            clearPreparation()
            inApp.switchTo(target, from: origin, catalog: catalog) { outcome in
                completion(SwitchOutcome(
                    tisLanded: outcome.tisLanded, tisLatencyMs: outcome.tisLatencyMs,
                    notes: "path=inApp " + outcome.notes))
            }
            return
        }
        let note = preparedNote
        let stableMs = primed ? primedStableMs : 0
        armedTarget = nil
        preparedTarget = nil
        primed = false
        // 이 seq는 전략 안의 순번이며 AppModel의 `fnpass seq=`와 다르다. 시각과 target으로 맞춰 본다.
        fnStepSeq += 1
        let trace = StepTrace(label: "fn step", seq: fnStepSeq, decidedAt: start)
        // Armed: the OS is already switching. Do not read `origin` here: right after priming the current
        // source can still read as the target, and an extra TIS select raced the OS (02-20 part 3:
        // `path=noOrigin` then the OS landed on the previous source, "Chinese twice").
        // 넘긴 fn 해제는 취소할 수 없어 한도까지 plan B를 미룬다. OS가 KeyHold 한도보다 늦으면
        // 붙잡은 키는 한도에서 풀린다(사용자가 받아들임, 2026-11-09).
        LandingWaiter.waitStable(
            for: target.id, catalog: catalog, timeoutMs: SignalTiming.perSignalLimitMs, stableMs: stableMs, start: start
        ) { [weak self, inApp] landed, ms in
            self?.fnStep(trace, "wait target=\(target.id) landed=\(landed) timeoutMs=\(SignalTiming.perSignalLimitMs) waitMs=\(String(format: "%.1f", ms)) stableMs=\(stableMs) current=\(Self.word(catalog.currentID()))")
            if landed {
                completion(SwitchOutcome(tisLanded: true, tisLatencyMs: ms, notes: "path=native \(note)"))
                return
            }
            self?.fnStepWindow = trace.extendingWindow(from: CFAbsoluteTimeGetCurrent())
            self?.fnStep(trace, "fallback reason=timeout")
            self?.fnStep(trace, "inApp start")
            // Plan B is the S2 switch itself: select, wait, select again (user decision 2026-11-04).
            inApp.switchTo(target, from: origin, catalog: catalog) { [weak self] outcome in
                self?.fnStep(trace, "inApp done landed=\(outcome.tisLanded) current=\(Self.word(catalog.currentID())) \(outcome.notes)")
                completion(SwitchOutcome(
                    tisLanded: outcome.tisLanded, tisLatencyMs: (CFAbsoluteTimeGetCurrent() - start) * 1000,
                    notes: "path=fallback \(outcome.notes) \(note)"))
            }
        }
    }

    /// 대문자 잠금의 현재 값. 펄스를 게시하는 시점마다 다시 읽는다(낡은 값은 잠금을 되돌린다, T-03-14).
    /// 읽지 못하면 누름 시점 값을 쓴다.
    public var capsLockState: (() -> Bool?)?
    /// 조합 중일 수 있는가. AppModel이 `CompositionHeuristic`을 넣는다. 없으면 보수적으로 참.
    public var composingHint: (() -> Bool)?
    /// 홉의 둘째 다리 앞에서 부른다. 키 붙잡기 한도를 늘린다.
    public var onExtendHold: (() -> Void)?

    private static let layoutType = "TISTypeKeyboardLayout"

    /// Caps 경로. 계획은 `CapsSwitchPlan`이 정한다. origin이 없으면 준비할 수 없어 앱 안 전환으로 간다.
    private func switchCaps(
        _ caps: CapsArm, target: SourceInfo, from origin: SourceInfo?, catalog: InputSourceCatalog,
        completion: @escaping (SwitchOutcome) -> Void
    ) {
        stepWindow = caps.trace
        step(caps, "entry trigger=\(caps.trigger) target=\(target.id)")
        guard let origin else {
            step(caps, "plan=noOrigin target=\(target.id)")
            capsInApp(caps, target: target, origin: nil, catalog: catalog, notes: "path=inApp plan=noOrigin", completion)
            return
        }
        let composing = composingHint?() ?? true
        let plan = CapsSwitchPlan.decide(
            target: target.id, origin: origin.id, recent: recent,
            originIsLayout: origin.type == Self.layoutType, targetIsLayout: target.type == Self.layoutType,
            mayBeComposing: composing)
        step(caps, "plan=\(Self.planWord(plan)) origin=\(origin.id) target=\(target.id) recentCurrent=\(Self.word(recent.current)) recentPrevious=\(Self.word(recent.previous)) composing=\(composing)")
        switch plan {
        case .pulse:
            guard let postedAt = postPulse(caps, leg: "first") else {
                capsInApp(caps, target: target, origin: origin, catalog: catalog, notes: "path=inApp plan=pulse", completion)
                return
            }
            waitCaps(caps, id: target.id, target: target, origin: origin, catalog: catalog,
                     postedAt: postedAt, stableMs: 0, plan: "pulse", leg: "first", completion: completion)
        case .primeThenPulse:
            guard let tsrc = catalog.tisSource(for: target.id), let osrc = catalog.tisSource(for: origin.id),
                let postedAt = postPulseAfter({ self.selectPair(caps, first: tsrc, second: osrc, leg: "first") }, caps, leg: "first")
            else {
                capsInApp(caps, target: target, origin: origin, catalog: catalog, notes: "path=inApp plan=prime", completion)
                return
            }
            waitCaps(caps, id: target.id, target: target, origin: origin, catalog: catalog,
                     postedAt: postedAt, stableMs: primedStableMs, plan: "prime",
                     leg: "first", completion: completion)
        case .hopThenPrime:
            hop(caps, target: target, origin: origin, catalog: catalog, completion: completion)
        }
    }

    private static func planWord(_ plan: CapsSwitchPlan) -> String {
        switch plan {
        case .pulse: return "pulse"
        case .primeThenPulse: return "prime"
        case .hopThenPrime: return "hop"
        }
    }

    /// 준비 TIS: first 다음 second 순서로 고르고 걸린 시간과 상태값을 기록한다.
    private func selectPair(_ caps: CapsArm, first: TISInputSource, second: TISInputSource, leg: String) {
        let start = CFAbsoluteTimeGetCurrent()
        let s1 = TISSelectInputSource(first)
        let s2 = TISSelectInputSource(second)
        let ms = (CFAbsoluteTimeGetCurrent() - start) * 1000
        step(caps, "prime leg=\(leg) ms=\(String(format: "%.1f", ms)) status=\(s1)/\(s2)")
    }

    /// 펄스로 직전 소스에 가고(OS가 조합을 확정), 거기서 TIS로 대상 -> 그곳을 골라 다시 펄스한다.
    private func hop(
        _ caps: CapsArm, target: SourceInfo, origin: SourceInfo, catalog: InputSourceCatalog,
        completion: @escaping (SwitchOutcome) -> Void
    ) {
        guard let hopID = recent.previous, let postedAt = postPulse(caps, leg: "first") else {
            capsInApp(caps, target: target, origin: origin, catalog: catalog, notes: "path=inApp plan=hop", completion)
            return
        }
        LandingWaiter.waitStable(
            for: hopID, catalog: catalog, timeoutMs: SignalTiming.perSignalLimitMs, stableMs: 0, start: postedAt
        ) { [weak self] landed, sincePostMs in
            guard let self else { return }
            self.step(caps, "wait leg=first id=\(hopID) landed=\(landed) timeoutMs=\(SignalTiming.perSignalLimitMs) sincePostMs=\(String(format: "%.1f", sincePostMs)) stableMs=0.0 current=\(Self.word(catalog.currentID()))")
            guard landed, let tsrc = catalog.tisSource(for: target.id), let hsrc = catalog.tisSource(for: hopID) else {
                self.capsFallback(caps, target: target, origin: origin, catalog: catalog, plan: "hop",
                                  leg: "first", reason: landed ? "noSource" : "timeout", completion)
                return
            }
            self.selectPair(caps, first: tsrc, second: hsrc, leg: "second")
            self.onExtendHold?()
            guard let secondPostedAt = self.postPulse(caps, leg: "second") else {
                self.capsFallback(caps, target: target, origin: origin, catalog: catalog, plan: "hop",
                                  leg: "second", reason: "postFailed", completion)
                return
            }
            self.waitCaps(caps, id: target.id, target: target, origin: origin, catalog: catalog,
                          postedAt: secondPostedAt, stableMs: self.primedStableMs, plan: "hop", leg: "second",
                          completion: completion)
        }
    }

    private func waitCaps(
        _ caps: CapsArm, id: SourceID, target: SourceInfo, origin: SourceInfo?, catalog: InputSourceCatalog,
        postedAt: CFAbsoluteTime, stableMs: Double, plan: String, leg: String,
        completion: @escaping (SwitchOutcome) -> Void
    ) {
        LandingWaiter.waitStable(
            for: id, catalog: catalog, timeoutMs: SignalTiming.perSignalLimitMs, stableMs: stableMs, start: postedAt
        ) { [weak self] landed, sincePostMs in
            self?.step(caps, "wait leg=\(leg) id=\(id) landed=\(landed) timeoutMs=\(SignalTiming.perSignalLimitMs) sincePostMs=\(String(format: "%.1f", sincePostMs)) stableMs=\(stableMs) current=\(Self.word(catalog.currentID()))")
            if landed {
                // 결과 시간은 판정 시각 기준이다.
                completion(SwitchOutcome(tisLanded: true, tisLatencyMs: (CFAbsoluteTimeGetCurrent() - caps.pressedAt) * 1000, notes: "path=pulse plan=\(plan) trigger=\(caps.trigger)"))
                return
            }
            self?.capsFallback(caps, target: target, origin: origin, catalog: catalog, plan: plan,
                               leg: leg, reason: "timeout", completion)
        }
    }

    private func capsFallback(
        _ caps: CapsArm, target: SourceInfo, origin: SourceInfo?, catalog: InputSourceCatalog, plan: String,
        leg: String, reason: String, _ completion: @escaping (SwitchOutcome) -> Void
    ) {
        // plan B가 돌면 늦게 닿는 펄스가 보이도록 기록 창을 그 시작부터 1초로 늘린다.
        if (stepWindow?.seq ?? caps.trace.seq) <= caps.trace.seq {
            stepWindow = caps.trace.extendingWindow(from: CFAbsoluteTimeGetCurrent())
        }
        step(caps, "fallback plan=\(plan) leg=\(leg) reason=\(reason)")
        capsInApp(caps, target: target, origin: origin, catalog: catalog, notes: "path=fallback plan=\(plan)", completion)
    }

    private func capsInApp(
        _ caps: CapsArm, target: SourceInfo, origin: SourceInfo?, catalog: InputSourceCatalog, notes: String,
        _ completion: @escaping (SwitchOutcome) -> Void
    ) {
        step(caps, "inApp start \(notes)")
        inApp.switchTo(target, from: origin, catalog: catalog) { [weak self] outcome in
            self?.step(caps, "inApp done landed=\(outcome.tisLanded) current=\(Self.word(catalog.currentID())) \(outcome.notes)")
            completion(SwitchOutcome(
                tisLanded: outcome.tisLanded, tisLatencyMs: (CFAbsoluteTimeGetCurrent() - caps.pressedAt) * 1000,
                notes: notes + " trigger=\(caps.trigger) " + outcome.notes))
        }
    }

    /// 게시 시점의 잠금 값을 싣고 펄스를 게시한다. 만들지 못하면 false.
    private func postPulse(_ caps: CapsArm, leg: String) -> CFAbsoluteTime? {
        guard let pulse = Self.capsPulse(caps, capsOn: capsLockState?() ?? caps.capsOn) else {
            step(caps, "pulse leg=\(leg) failed")
            return nil
        }
        let start = CFAbsoluteTimeGetCurrent()
        pulse.0.post(tap: .cghidEventTap)
        pulse.1.post(tap: .cghidEventTap)
        let postedAt = CFAbsoluteTimeGetCurrent()
        step(caps, "pulse leg=\(leg) postMs=\(String(format: "%.2f", (postedAt - start) * 1000))")
        return postedAt
    }

    /// 준비 TIS 호출을 하고 펄스를 게시한다. 펄스를 만들 수 없으면 TIS 호출 전에 false(아무것도 안 함).
    private func postPulseAfter(_ prepare: () -> Void, _ caps: CapsArm, leg: String) -> CFAbsoluteTime? {
        guard Self.capsPulse(caps, capsOn: caps.capsOn) != nil else {
            step(caps, "pulse leg=\(leg) failed")
            return nil
        }
        prepare()
        return postPulse(caps, leg: leg)
    }

    /// 눌림 복사본에서 만든다. 플래그는 fn·숫자패드 표식만 남기고 게시 시점 잠금 값을 싣는다.
    /// `SyntheticKeys.post`는 플래그를 비워 F 키 식별을 지우므로 쓰지 않는다.
    private static func capsPulse(_ caps: CapsArm, capsOn: Bool) -> (CGEvent, CGEvent)? {
        guard let base = caps.press ?? CGEvent(keyboardEventSource: nil, virtualKey: caps.keyCode, keyDown: true),
            let down = base.copy(), let up = base.copy()
        else { return nil }
        down.type = .keyDown
        up.type = .keyUp
        var flags = base.flags.intersection([.maskSecondaryFn, .maskNumericPad])
        if capsOn { flags.insert(.maskAlphaShift) }
        for e in [down, up] {
            e.flags = flags
            e.setIntegerValueField(.keyboardEventAutorepeat, value: 0)
            e.setIntegerValueField(.eventSourceUserData, value: fncapsEventMarker)
        }
        return (down, up)
    }
}
