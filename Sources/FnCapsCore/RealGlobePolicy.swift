import Foundation

// S10-RealGlobe 판단 규칙의 순수 타입. 시험판(AdvancedStrategies.swift, FnTap.swift)에서 옮겼다.
// TIS·CoreGraphics에 의존하지 않는다.

/// 선택 변경 알림(FnCaps 자신의 전환과 준비 포함)으로 OS의 최근 사용 순서 앞 두 칸을 추정한다.
public struct RecentSources: Equatable, Sendable {
    public private(set) var current: SourceID?
    public private(set) var previous: SourceID?

    public init() {}

    /// history는 최근 사용이 앞. current가 nil이면 history.first를 current로 쓴다.
    public mutating func seed(current: SourceID?, history: [SourceID]) {
        let cur = current ?? history.first
        self.current = cur
        previous = history.first(where: { $0 != cur })
    }

    public mutating func observe(selected: SourceID?) {
        guard let selected, selected != current else { return }
        previous = current
        current = selected
    }
}

public enum PrimeAction: Equatable, Sendable {
    case skip
    case prime
}

public enum PrimeDecision {
    /// 준비의 「목표 켜기 -> 끄기」가 입력기에 늦게 닿아 미확정 `n`을 로마자로 확정한다(GAP-09,
    /// 02-VERIFICATION). 이미 OS의 최근 사용 앞 두 칸이 (origin, target)이면 생략한다.
    /// 생략하면 한<->일 왕복에서 확정 0건.
    public static func decide(target: SourceID, origin: SourceID, recent: RecentSources) -> PrimeAction {
        recent.previous == target && recent.current == origin ? .skip : .prime
    }
}

public enum PrimeTiming: String, Equatable, Sendable {
    case down
    case release

    /// 02-25 실기 측정 채택: release, 근거 release=0/11 down=-/10 (1차가 0건이라 down 비교는 하지 않음).
    public static let defaultValue: PrimeTiming = .release
}

/// fn 해제를 OS에 넘긴 뒤 OS가 만드는 🌐(179)도 넘긴다. 앱이 처리하는 누름(연타 등)에서는
/// 반드시 close해서 그 누름의 179가 OS에 가지 않게 한다.
public struct GlobePassWindow: Equatable, Sendable {
    public static let defaultSeconds: TimeInterval = 0.5
    public let seconds: TimeInterval
    private var openedAt: TimeInterval?

    public init(seconds: TimeInterval = GlobePassWindow.defaultSeconds) {
        self.seconds = seconds
    }

    public mutating func open(now: TimeInterval) { openedAt = now }

    public func allows(now: TimeInterval) -> Bool {
        guard let openedAt else { return false }
        return now < openedAt + seconds
    }

    public mutating func close() { openedAt = nil }
}

/// 연타 감지. 기준은 「직전에 OS로 넘긴 누름」이 아니라 「직전 누름」이다. 앱이 처리한 두 번째
/// 누름 뒤의 세 번째 누름도 OS의 연타 판정 안에 있을 수 있기 때문이다(추정, 02-20에서 측정).
/// 창 안의 두 번째 누름은 앱이 삼켜 OS는 누름 하나만 본다. 02-25에서 확인.
///
/// **user away — review at UAT, Phase 2 결정 500ms 변경.** 04.1-UAT O1·C7·R2·R3에서 0.6~1.0초
/// 간격의 fn 누름이 OS로 넘어갔다가 OS가 500 ms 안에 전환하지 못해 `fallback reason=timeout`으로
/// 약 0.55초 늦게 도착했다. 이 간격대를 앱 안 경로(inApp, 도착 40~49 ms)로 보내려고 1000 ms로
/// 넓혔다(05-06, `05-FN-TEMPO.md`). 실키에서 문제가 보이면 500으로 되돌린다.
public struct FnRepeatGuard: Equatable, Sendable {
    public static let defaultWindowMs: Double = 1000
    public var windowMs: Double
    public private(set) var lastPressAt: TimeInterval?

    public init(windowMs: Double = FnRepeatGuard.defaultWindowMs) {
        self.windowMs = windowMs
    }

    public func wouldBeRapid(now: TimeInterval) -> Bool {
        guard windowMs > 0, let last = lastPressAt else { return false }
        return (now - last) * 1000 < windowMs
    }

    public mutating func notePress(now: TimeInterval) -> Bool {
        let rapid = wouldBeRapid(now: now)
        lastPressAt = now
        return rapid
    }

    public mutating func reset() { lastPressAt = nil }
}

public enum FnRoute: String, Equatable, Sendable {
    case passToOS
    case inApp
}

public enum FnRoutePolicy {
    /// AppleFnUsageType: 0 없음, 1 입력 소스 변경, 2 이모지, 3 받아쓰기.
    public static let changeInputSourceUsage = 1

    /// 새 계정에는 AppleFnUsageType 키가 없고 시스템 설정은 「입력 소스 변경」으로 보인다(2026-11-20 관찰).
    /// 키가 없으면 1로 본다(D-10). 단계 끝 새 계정 실기로 확인하고, nil인데 fn 전환이 안 되면 되돌린다.
    public static func effectiveUsage(_ usage: Int?) -> Int {
        usage ?? changeInputSourceUsage
    }

    /// 1(또는 키 없음)이 아니면 fn 해제를 넘길 때 OS가 다른 동작(이모지 창 등)을 하거나 아무것도 안 하므로
    /// 넘기지 않는다. alreadySwitching이면 준비를 콜백 안에서 동기로 할 수 없으므로(전환이 줄
    /// 서 있음) 앱이 처리한다.
    public static func decide(isSwitch: Bool, usage: Int?, rapid: Bool, alreadySwitching: Bool) -> FnRoute {
        isSwitch && effectiveUsage(usage) == changeInputSourceUsage && !rapid && !alreadySwitching
            ? .passToOS : .inApp
    }
}

/// OS로 보낸 신호(Caps 펄스, fn 해제)가 닿기를 기다리는 시간.
public enum SignalTiming {
    /// 신호마다 따로 잰다. 보낸 신호는 취소할 수 없어 이 한도가 지난 뒤에만 plan B(TIS 재선택)로 간다
    /// (사용자 결정 2026-11-09).
    public static let perSignalLimitMs: Double = 500

    /// 준비(prime) 직후 목표로 이 시간 동안 이어서 읽혀야 도착으로 본다. `RealGlobeStrategy.primedStableMs`
    /// 기본값과 같은 값이다(추정, 2026-11-04 로그). Core는 System을 참조할 수 없어 값을 따로 적는다.
    public static let capsStableMs: Double = 30

    /// plan B(`TISReselectStrategy`)가 다시 고르기 전에 쉬는 시간. `TISReselectStrategy.reselectDelayMs`
    /// 기본값과 같은 값이다. Core는 System을 참조할 수 없어 값을 따로 적는다.
    public static let capsInAppDelayMs: Double = 30

    /// Caps 홉 `hopThenPrime`의 최악 시간: 첫 다리 대기 + 둘째 펄스 대기(안정 포함) + plan B 1회.
    /// 04-REVIEW WR-02. 500 + (500 + 30) + 30 + 500 = 1560 ms.
    public static var capsHopWorstCaseMs: Double {
        perSignalLimitMs + (perSignalLimitMs + capsStableMs) + capsInAppDelayMs + perSignalLimitMs
    }

    /// 전환 감시 한도: 홉 2다리 + plan B 1회 + 여유. 04-REVIEW WR-02.
    /// 감시가 전략보다 먼저 끝나면 다음 전환이 시작돼 두 전환이 겹치고, 늦게 착지한 남은 단계가
    /// 사용자가 마지막으로 고른 언어를 덮어쓴다. 항상 `capsHopWorstCaseMs`보다 200 ms 이상 길다.
    public static var switchWatchdogMs: Double { perSignalLimitMs * 3 + 300 }
}

/// S10 직접 전환의 도착 판정. 준비(prime) 직후에는 현재 소스가 잠깐 목표로 읽혔다가 원래 소스로
/// 돌아올 수 있어(2026-11-04 로그: 0 ms에 도착, 0.3초 뒤 아직 원래 소스), 목표로 `stableMs` 동안
/// 이어서 읽혀야 도착으로 본다. 목표로 읽히는 중에는 제한 시간이 지나도 판정을 끝까지 기다린다.
public struct LandingStability {
    public enum Result: Equatable { case waiting, landed, timedOut }

    public let timeoutMs: Double
    public let stableMs: Double
    private var targetSince: Double?

    public init(timeoutMs: Double, stableMs: Double) {
        self.timeoutMs = timeoutMs
        self.stableMs = stableMs
    }

    /// `elapsedMs`는 전환 요청부터 지난 시간이다.
    public mutating func observe(isTarget: Bool, elapsedMs: Double) -> Result {
        guard isTarget else {
            targetSince = nil
            return elapsedMs >= timeoutMs ? .timedOut : .waiting
        }
        let since = targetSince ?? elapsedMs
        targetSince = since
        return elapsedMs - since >= stableMs ? .landed : .waiting
    }
}
