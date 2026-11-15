// D-13(합의어): 화면 이름은 「처음 설정」이고 코드 이름은 FirstRunSetup이다.
// D-16~D-20: 어느 단계에서든 나갈 수 있고, 나가면 사이드바 「처음 설정 n/5」 항목이 남으며,
// 이미 충족한 단계는 마친 것으로 센다. 단계는 저장해 권한 뒤 자동 재시작(`--show-settings`)을
// 건너 이어지고, 새로 설치한 사람만 본다.
// 단계는 5개다(UI-SPEC §6, 2026-11-14 사용자 결정): 1 환영 → 2 손쉬운 사용 권한 → 3 🌐 키 →
// 4 전환 방식 → 5 권장 배치 고르기.
// 옛 이동 장치(04.2 D-50, 권한 뒤 도움말 「설정하기」 이동)를 대신한다.
// 순수 판단만 둔다(SwiftUI·AppKit을 import하지 않는다). 창 모양과 이동은 설정 화면이 한다.
import Foundation

public final class FirstRunSetup {
    /// 다음에 보일 단계(1...5). 저장값이 없으면 처음 설정이 아니다(D-19).
    public static let stepKey = "firstRunSetup.step"
    /// 5단계를 마쳤는지(D-16: 마치면 사이드바 항목이 사라진다).
    public static let finishedKey = "firstRunSetup.finished"
    /// [나중에]나 창 닫기로 나갔는지. 나간 뒤에는 평소 설정 창으로 연다(orchestrator decision 4).
    public static let leftKey = "firstRunSetup.left"
    /// 단계 점 개수(UI-SPEC §4: 건너뛴 단계도 점은 5개 그대로).
    public static let stepCount = 5

    private let defaults: UserDefaults?
    /// defaults가 없을 때만 쓰는 메모리 저장. 렌더 하니스가 사용자 defaults를 건드리지 않는다(T-04.4-04).
    private var memory: [String: Any] = [:]

    /// `defaults: nil`이면 메모리에만 쓴다(렌더 하니스용).
    public init(defaults: UserDefaults?) { self.defaults = defaults }

    // MARK: - 저장 헬퍼

    private func object(forKey key: String) -> Any? {
        if let defaults { return defaults.object(forKey: key) }
        return memory[key]
    }

    private func write(_ value: Any?, forKey key: String) {
        guard let value else {
            if let defaults { defaults.removeObject(forKey: key) } else { memory[key] = nil }
            return
        }
        if let defaults { defaults.set(value, forKey: key) } else { memory[key] = value }
    }

    // MARK: - 시드

    /// 첫 실행이고 단계 키가 없을 때만 단계 1을 심는다. 업데이트 사용자(firstLaunch == false)는
    /// 아무것도 쓰지 않아 isTracked == false다(D-19).
    public static func seedIfFirstLaunch(_ firstLaunch: Bool, defaults: UserDefaults) {
        guard firstLaunch, defaults.object(forKey: stepKey) == nil else { return }
        defaults.set(1, forKey: stepKey)
        defaults.set(false, forKey: finishedKey)
        defaults.set(false, forKey: leftKey)
    }

    /// 메모리 저장 인스턴스용 시드. 같은 인스턴스 안에서만 쓰인다.
    public func seedIfFirstLaunch(_ firstLaunch: Bool) {
        guard firstLaunch, object(forKey: Self.stepKey) == nil else { return }
        write(1, forKey: Self.stepKey)
        write(false, forKey: Self.finishedKey)
        write(false, forKey: Self.leftKey)
    }

    // MARK: - 상태

    /// 단계 키가 있는지. 처음 설정 대상인지 판단한다.
    public var isTracked: Bool { object(forKey: Self.stepKey) != nil }

    public var isFinished: Bool { object(forKey: Self.finishedKey) as? Bool ?? false }

    public var hasLeft: Bool { object(forKey: Self.leftKey) as? Bool ?? false }

    /// 사이드바 「처음 설정 n/5」 항목을 보일지(D-16).
    public var isActive: Bool { isTracked && !isFinished }

    /// 창을 열 때 단계 화면으로 열지. 한 번 나갔으면 평소 창으로 연다(orchestrator decision 4).
    public var opensInSetupMode: Bool { isActive && !hasLeft }

    // MARK: - 단계

    /// 저장값이 Int이고 1...5이면 그 값, 아니면 1이다(T-04.4-03, ASVS V5 clamp).
    public var step: Int {
        guard let raw = object(forKey: Self.stepKey) as? Int,
            (1...Self.stepCount).contains(raw)
        else { return 1 }
        return raw
    }

    public func setStep(_ n: Int) {
        write(min(max(n, 1), Self.stepCount), forKey: Self.stepKey)
    }

    // MARK: - 단계 이동

    /// [다음]. 2단계 뒤 🌐 값이 이미 권장과 같으면 3단계를 건너뛴다(D-17).
    /// 단계 점은 5개 그대로 둔다(UI-SPEC §4). globeOK는 호출처가 `!snapshot.globeNotice`로 넘긴다.
    public static func nextStep(after step: Int, globeOK: Bool) -> Int {
        switch step {
        case ..<1: return 1
        case 1: return 2
        case 2: return globeOK ? 4 : 3
        case 3: return 4
        case 4: return 5
        default: return stepCount
        }
    }

    /// [이전]. 3단계를 건너뛴 경우 4단계에서 2단계로 돌아간다(UI-SPEC §4).
    /// 5단계에서는 4단계로 돌아간다(5단계 「직접 설정」 분기 쪽의 [이전]은 5단계 목록으로 간다).
    public static func previousStep(before step: Int, globeOK: Bool) -> Int {
        switch step {
        case ..<3: return 1
        case 3: return 2
        case 4: return globeOK ? 2 : 3
        case 5: return 4
        default: return stepCount
        }
    }

    /// 재시작·이어서 하기로 단계 화면을 열 때 보일 단계. 저장된 3단계가 이미 충족이면 4단계다.
    public static func resumeStep(stored: Int, globeOK: Bool) -> Int {
        let clamped = min(max(stored, 1), stepCount)
        return clamped == 3 && globeOK ? 4 : clamped
    }

    // MARK: - 나가기·마치기

    /// [나중에]·창 닫기. 사이드바 항목은 남고(isActive), 다음 창 열기는 평소 창으로 연다.
    public func markLeft() { write(true, forKey: Self.leftKey) }

    /// 사이드바 「처음 설정 n/5」를 눌러 멈춘 단계로 돌아간다.
    public func resume() { write(false, forKey: Self.leftKey) }

    public func finish() {
        write(true, forKey: Self.finishedKey)
        write(false, forKey: Self.leftKey)
    }
}
