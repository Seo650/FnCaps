// D-07·D-08: 처음 설정 아래 줄의 강조·Return·[이전]·[마침] 확인 규칙(UI-SPEC 「아래 줄에 어떤 버튼이 있는가」).
// D-07: 후보를 고르면 적용과 함께 끝나므로 목록의 [마침]은 늘 「배치 없이 끝내기」다.
// D-08: 목록의 [마침]은 회색이고 Return에 묶지 않는다. 「직접 설정」 쪽 [마침]은 확인 없이 끝낸다.
// 한 화면에 강조 버튼은 하나다(04.5 §3). 예외: 5단계 후보 목록은 후보마다 [이 설정 사용하기]를 강조하고 Return에는 묶지 않는다(G-08.1-13).
// G-08.1-12: 권한을 주기 전 2단계 [다음]은 비활성이다. 조건은 needsGrant(호출처의 permissionPanel == .grant)와 같고 막힘(.stuck)은 막지 않는다(A-02 그대로).
// 순수 판단만 둔다(SwiftUI·AppKit을 import하지 않는다).
import Foundation

/// 처음 설정 화면 종류. UI-SPEC 「아래 줄에 어떤 버튼이 있는가」 표의 행에 대응한다.
public enum OnboardingScreen: Equatable, Sendable {
    /// 1단계 환영.
    case welcome
    /// 2단계 손쉬운 사용 권한. needsGrant는 허용 버튼이 보이는 상태(`permissionPanel == .grant`)다.
    case permission(needsGrant: Bool)
    /// 3단계 🌐 키. needsChange면 값이 권장과 달라 [키보드 설정 열기]를 강조한다.
    case globe(needsChange: Bool)
    /// 4단계 전환 방식.
    case basics
    /// 5단계 권장 배치 후보 목록.
    case layoutList
    /// 5단계 「직접 설정」 쪽.
    case layoutCustom
    /// 5단계 입력 소스 1개(빈 상태).
    case layoutEmpty
}

/// 아래 줄 또는 화면 안의 버튼.
public enum OnboardingButton: Equatable, Sendable {
    /// 아래 줄 오른쪽 끝의 [다음].
    case next
    /// 아래 줄 오른쪽 끝의 [마침].
    case finish
    /// 화면 안 [손쉬운 사용 설정 열기].
    case openAccessibility
    /// 화면 안 [키보드 설정 열기].
    case openKeyboard
}

/// 한 화면의 아래 줄 버튼 규칙.
public struct OnboardingFooter: Equatable, Sendable {
    /// 강조(ProminentButtonStyle) 버튼. 없으면 nil.
    public let prominent: OnboardingButton?
    /// Return(`.defaultAction`)에 묶는 버튼. 없으면 nil.
    public let defaultAction: OnboardingButton?
    /// [이전] 버튼을 보이는지.
    public let showsBack: Bool
    /// [마침]을 눌렀을 때 확인 시트를 거치는지.
    public let finishConfirms: Bool
    /// [다음]을 누를 수 있는지. 권한을 주기 전 2단계만 false다(G-08.1-12, 2026-11-23 사용자 결정).
    /// [나중에]·[이전]은 늘 눌린다(04.4 D-16).
    public let nextEnabled: Bool
    /// 5단계 후보마다 있는 [이 설정 사용하기]를 강조(ProminentButtonStyle)할지. Return에는 묶지 않으므로
    /// prominent·defaultAction과 따로 둔다. 후보 목록 화면만 true다(G-08.1-13, 2026-11-23 사용자 결정.
    /// 「한 화면에 강조 하나」는 04.4 UI-SPEC에서 Claude가 정한 규칙이라 이 화면에서 예외로 푼다).
    public let candidatesProminent: Bool

    public init(
        prominent: OnboardingButton?, defaultAction: OnboardingButton?, showsBack: Bool,
        finishConfirms: Bool, nextEnabled: Bool = true, candidatesProminent: Bool = false
    ) {
        self.prominent = prominent
        self.defaultAction = defaultAction
        self.showsBack = showsBack
        self.finishConfirms = finishConfirms
        self.nextEnabled = nextEnabled
        self.candidatesProminent = candidatesProminent
    }
}

/// 단계 번호와 상태를 화면 종류로 바꾸고, 화면 종류를 아래 줄 규칙으로 바꾼다.
public enum OnboardingButtonRule {
    /// 단계 번호와 상태를 화면 종류로 바꾼다. 범위 밖 단계는 1과 5로 자른다.
    /// needsGrant는 호출처가 `permissionPanel == .grant`로 넘긴다(막힘은 false, A-02).
    /// 5단계는 분기(「직접 설정」 쪽)가 빈 상태보다 앞선다.
    public static func screen(
        step: Int, needsGrant: Bool, globeNeedsChange: Bool, branch: Bool, singleSource: Bool
    ) -> OnboardingScreen {
        let clamped = min(max(step, 1), FirstRunSetup.stepCount)
        switch clamped {
        case 1: return .welcome
        case 2: return .permission(needsGrant: needsGrant)
        case 3: return .globe(needsChange: globeNeedsChange)
        case 4: return .basics
        default:
            if branch { return .layoutCustom }
            if singleSource { return .layoutEmpty }
            return .layoutList
        }
    }

    /// 화면 종류를 아래 줄 규칙으로 바꾼다. UI-SPEC 「아래 줄에 어떤 버튼이 있는가」 표 그대로다.
    public static func footer(for screen: OnboardingScreen) -> OnboardingFooter {
        switch screen {
        case .welcome:
            return OnboardingFooter(
                prominent: .next, defaultAction: .next, showsBack: false, finishConfirms: false)
        case .permission(needsGrant: true):
            return OnboardingFooter(
                prominent: .openAccessibility, defaultAction: .openAccessibility, showsBack: true,
                finishConfirms: false, nextEnabled: false)
        case .permission(needsGrant: false):
            return OnboardingFooter(
                prominent: .next, defaultAction: .next, showsBack: true, finishConfirms: false)
        case .globe(needsChange: true):
            return OnboardingFooter(
                prominent: .openKeyboard, defaultAction: .openKeyboard, showsBack: true,
                finishConfirms: false)
        case .globe(needsChange: false):
            return OnboardingFooter(
                prominent: .next, defaultAction: .next, showsBack: true, finishConfirms: false)
        case .basics:
            return OnboardingFooter(
                prominent: .next, defaultAction: .next, showsBack: true, finishConfirms: false)
        case .layoutList:
            return OnboardingFooter(
                prominent: nil, defaultAction: nil, showsBack: true, finishConfirms: true,
                candidatesProminent: true)
        case .layoutCustom:
            return OnboardingFooter(
                prominent: .finish, defaultAction: .finish, showsBack: true, finishConfirms: false)
        case .layoutEmpty:
            // UI-SPEC O-5a: 돌아가도 고를 것이 없어 확인 없이 끝낸다(사용자가 뒤집으면 이 행만 바꾼다).
            return OnboardingFooter(
                prominent: .finish, defaultAction: .finish, showsBack: true, finishConfirms: false)
        }
    }
}
