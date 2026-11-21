// 구조 참고: gksdud main.swift PressGate (MIT)
import Foundation

/// F18 누름·뗌 게이트. 자동 반복과 뗌은 삼키고, 자동 반복이 아닌 누름은 늘 새 누름이다.
public struct CapsPressGate: Equatable, Sendable {
    public private(set) var held = false

    public init() {}

    /// consume: 이벤트를 삼키는가. press: 새 누름인가.
    public mutating func handle(down: Bool, autorepeat: Bool) -> (consume: Bool, press: Bool) {
        if !down {
            defer { held = false }
            return (held, false)
        }
        if autorepeat { return (true, false) }
        held = true  // 뗌을 놓쳐도 새 누름은 새로 시작한다
        return (true, true)
    }

    public mutating func reset() { held = false }
}

/// 전환이 일어난 이유. 로그의 `trigger=` 값이다.
public enum CapsTrigger: String, Equatable, Sendable {
    case release
    case key
}

/// 한 번의 Caps 누름에 대한 판정. 전환과 길게 누르기 중 하나만 나온다.
public enum CapsVerdict: Equatable, Sendable {
    case none
    case switchNow(CapsTrigger)
    case long
}

/// Caps(F 키) 누름 하나의 판정기. 판정 소유자는 이 값 하나이며 `FnTap`이 가진다.
/// 탭 콜백과 타이머는 모두 메인 스레드(메인 런루프)에서 돌아 서로 겹치지 않는다. 그래도 판정 뒤에는 모든 입력이
/// `.none`이므로 한 번의 누름은 결과를 한 번만 낸다.
/// 구조 참고: gksdud main.swift LongPressState (MIT). 기준 시간은 설정값이다.
public struct CapsPressJudge: Equatable, Sendable {
    public static let defaultMs = 500
    public static let minMs = 300
    public static let maxMs = 1000
    public static let stepMs = 50

    /// 설정값을 300~1000 ms로 자른다.
    public static func clampMs(_ ms: Int) -> Int { min(max(ms, minMs), maxMs) }

    private enum Phase: Equatable, Sendable { case idle, pending, decided }
    private var phase: Phase = .idle
    private var started: TimeInterval = 0
    private var delay: TimeInterval = Double(CapsPressJudge.defaultMs) / 1000
    private var cancelled = false

    public init() {}

    /// 판정 전인가(뗌, 다른 키, 타이머를 기다리는 중).
    public var isPending: Bool { phase == .pending }

    /// 이전 상태를 모두 지우고 새 누름을 시작한다.
    /// longEnabled false: 길게 누르기 끄기(D-17). 뗌과 다른 키는 늘 전환이다.
    public mutating func begin(now: TimeInterval, delay: TimeInterval, longEnabled: Bool = true) {
        phase = .pending
        started = now
        self.delay = delay
        cancelled = !longEnabled
    }

    /// 누름 상태를 지운다(탭 재설정). 뒤이은 뗌은 아무것도 일으키지 않는다.
    public mutating func reset() {
        phase = .idle
        cancelled = false
    }

    /// 길게 누르기만 취소한다. 판정 전이면 뒤이은 뗌이나 다른 키는 그래도 전환한다.
    public mutating func cancel() { cancelled = true }

    private func elapsedEnough(_ now: TimeInterval) -> Bool { now - started >= delay }

    /// 뗌. 기준 시간 전이면 전환, 이후면(타이머가 늦은 경우) 길게 누르기. 취소됐으면 늘 전환.
    public mutating func release(now: TimeInterval) -> CapsVerdict {
        guard phase == .pending else { return .none }
        phase = .decided
        if !cancelled, elapsedEnough(now) { return .long }
        return .switchNow(.release)
    }

    /// 다른 키 keyDown(수식 키 단독·마우스·자동 반복은 부르지 않는다). 판정 전이면 전환.
    public mutating func otherKey() -> CapsVerdict {
        guard phase == .pending else { return .none }
        phase = .decided
        return .switchNow(.key)
    }

    /// 기준 시간 타이머. 판정 전, 취소되지 않았고 기준 시간 이상일 때만 길게 누르기.
    public mutating func timer(now: TimeInterval) -> CapsVerdict {
        guard phase == .pending, !cancelled, elapsedEnough(now) else { return .none }
        phase = .decided
        return .long
    }
}

/// 길게 누르기 규칙. 슬라이더와 분리한 상수와 동작 표.
public enum CapsLongRule {
    /// 기준 언어로 전환한 뒤 잠금을 바꿀 수 있는 시간 제한(초). 길게 누르기 슬라이더와 무관하다.
    public static let baseReturnLimit: TimeInterval = 0.5

    public enum Action: Equatable, Sendable {
        /// 언어는 그대로 두고 잠금만 바꾼다.
        case flipLock
        /// 기준 언어로 전환한 뒤 잠금을 바꾼다. 전환할 곳이 없으면 전환만 생략한다.
        case switchToBaseThenFlip
        /// 아무 일도 하지 않는다.
        case ignore
    }

    /// `fromBase`: 누른 순간의 소스가 기준 언어. `isLayout`: 그 소스가 일반 자판(`TISTypeKeyboardLayout`).
    public static func action(fromBase: Bool, isLayout: Bool, layoutsOnly: Bool) -> Action {
        if layoutsOnly {
            if !isLayout { return .ignore }
            return .flipLock
        }
        return fromBase ? .flipLock : .switchToBaseThenFlip
    }

    /// 길게 누르기로 바꿀 영어(기준 언어) 소스를 고른다. Caps 목록 → fn 목록 → 「사용 안 함」 순서로,
    /// 같은 목록 안에서는 놓인 순서로 첫 기준 언어 소스. 켜진 소스(`sources`)에 있는 것만 본다.
    /// 어느 목록에 영어가 있든 길게 누르기가 동작한다(사용자 결정 2026-11-21, quick 261121-cle).
    /// 영어가 하나도 없으면 nil이고, 부르는 쪽은 전환 없이 잠금만 바꾼다.
    public static func englishTarget(
        caps: [SourceID], fn: [SourceID], excluded: [SourceID], sources: [SourceInfo]
    ) -> SourceID? {
        let base = Set(sources.filter { SourceClassifier.role(of: $0) == .base }.map(\.id))
        return (caps + fn + excluded).first { base.contains($0) }
    }
}
