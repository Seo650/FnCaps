import Foundation
import Testing
@testable import FnCapsCore

// D-07·D-08: 처음 설정 아래 줄의 강조·Return·[이전]·[마침] 확인 규칙.
// UI-SPEC 「아래 줄에 어떤 버튼이 있는가」 표 9행을 그대로 고정한다.
// 한 화면에 강조 버튼은 하나이고(04.5 §3), 5단계 후보 목록에는 Return 버튼이 없고 [마침]은 강조가 아니다(D-08). 후보마다 [이 설정 사용하기]만 강조한다(G-08.1-13, 2026-11-23 사용자 결정).
// G-08.1-12(2026-11-23 사용자 결정): 권한을 주기 전 2단계 [다음]만 비활성이고 [나중에]·[이전]은 늘 눌린다

@Suite struct OnboardingButtonRuleTests {
    @Test func footerMatchesUISpecTable() {
        // 1 환영: 강조·Return [다음], [이전] 없음
        #expect(
            OnboardingButtonRule.footer(for: .welcome)
                == OnboardingFooter(
                    prominent: .next, defaultAction: .next, showsBack: false, finishConfirms: false))
        // 2 권한 없음: 강조·Return 은 화면 안 [손쉬운 사용 설정 열기], [다음]은 비활성(G-08.1-12)
        #expect(
            OnboardingButtonRule.footer(for: .permission(needsGrant: true))
                == OnboardingFooter(
                    prominent: .openAccessibility, defaultAction: .openAccessibility, showsBack: true,
                    finishConfirms: false, nextEnabled: false))
        // 2 권한 있음(또는 막힘): 강조·Return [다음]
        #expect(
            OnboardingButtonRule.footer(for: .permission(needsGrant: false))
                == OnboardingFooter(
                    prominent: .next, defaultAction: .next, showsBack: true, finishConfirms: false))
        // 3 🌐 값이 다름: 강조·Return 은 화면 안 [키보드 설정 열기]
        #expect(
            OnboardingButtonRule.footer(for: .globe(needsChange: true))
                == OnboardingFooter(
                    prominent: .openKeyboard, defaultAction: .openKeyboard, showsBack: true,
                    finishConfirms: false))
        // 3 🌐 값이 같음: 강조·Return [다음]
        #expect(
            OnboardingButtonRule.footer(for: .globe(needsChange: false))
                == OnboardingFooter(
                    prominent: .next, defaultAction: .next, showsBack: true, finishConfirms: false))
        // 4 전환 방식: 강조·Return [다음]
        #expect(
            OnboardingButtonRule.footer(for: .basics)
                == OnboardingFooter(
                    prominent: .next, defaultAction: .next, showsBack: true, finishConfirms: false))
        // 5 후보 목록: Return 없음, [마침]은 보통이고 확인을 거친다. 후보 [이 설정 사용하기]는 모두 강조(G-08.1-13)
        #expect(
            OnboardingButtonRule.footer(for: .layoutList)
                == OnboardingFooter(
                    prominent: nil, defaultAction: nil, showsBack: true, finishConfirms: true,
                    candidatesProminent: true))
        // 5 「직접 설정」 쪽: 강조·Return [마침], 확인 없음
        #expect(
            OnboardingButtonRule.footer(for: .layoutCustom)
                == OnboardingFooter(
                    prominent: .finish, defaultAction: .finish, showsBack: true, finishConfirms: false))
        // 5 언어 1개(빈 상태): 강조·Return [마침], 확인 없음(UI-SPEC O-5a)
        #expect(
            OnboardingButtonRule.footer(for: .layoutEmpty)
                == OnboardingFooter(
                    prominent: .finish, defaultAction: .finish, showsBack: true, finishConfirms: false))
    }

    @Test func prominentIsAlwaysTheDefaultAction() {
        let screens: [OnboardingScreen] = [
            .welcome,
            .permission(needsGrant: true),
            .permission(needsGrant: false),
            .globe(needsChange: true),
            .globe(needsChange: false),
            .basics,
            .layoutList,
            .layoutCustom,
            .layoutEmpty,
        ]
        for screen in screens {
            let footer = OnboardingButtonRule.footer(for: screen)
            #expect(footer.prominent == footer.defaultAction)
        }
    }

    @Test func nextIsDisabledOnlyBeforeGrant() {
        let screens: [OnboardingScreen] = [
            .welcome,
            .permission(needsGrant: true),
            .permission(needsGrant: false),
            .globe(needsChange: true),
            .globe(needsChange: false),
            .basics,
            .layoutList,
            .layoutCustom,
            .layoutEmpty,
        ]
        for screen in screens {
            #expect(
                OnboardingButtonRule.footer(for: screen).nextEnabled
                    == (screen != .permission(needsGrant: true)))
        }
    }

    @Test func candidatesProminentOnlyOnList() {
        let screens: [OnboardingScreen] = [
            .welcome,
            .permission(needsGrant: true),
            .permission(needsGrant: false),
            .globe(needsChange: true),
            .globe(needsChange: false),
            .basics,
            .layoutList,
            .layoutCustom,
            .layoutEmpty,
        ]
        for screen in screens {
            #expect(
                OnboardingButtonRule.footer(for: screen).candidatesProminent
                    == (screen == .layoutList))
        }
        #expect(OnboardingButtonRule.footer(for: .layoutList).defaultAction == nil)
    }

    @Test func screenFromStep() {
        #expect(
            OnboardingButtonRule.screen(
                step: 1, needsGrant: false, globeNeedsChange: false, branch: false, singleSource: false)
                == .welcome)
        #expect(
            OnboardingButtonRule.screen(
                step: 0, needsGrant: false, globeNeedsChange: false, branch: false, singleSource: false)
                == .welcome)
        #expect(
            OnboardingButtonRule.screen(
                step: 2, needsGrant: true, globeNeedsChange: false, branch: false, singleSource: false)
                == .permission(needsGrant: true))
        #expect(
            OnboardingButtonRule.screen(
                step: 3, needsGrant: false, globeNeedsChange: true, branch: false, singleSource: false)
                == .globe(needsChange: true))
        #expect(
            OnboardingButtonRule.screen(
                step: 4, needsGrant: false, globeNeedsChange: false, branch: false, singleSource: false)
                == .basics)
        #expect(
            OnboardingButtonRule.screen(
                step: 5, needsGrant: false, globeNeedsChange: false, branch: false, singleSource: false)
                == .layoutList)
        #expect(
            OnboardingButtonRule.screen(
                step: 5, needsGrant: false, globeNeedsChange: false, branch: true, singleSource: true)
                == .layoutCustom)
        #expect(
            OnboardingButtonRule.screen(
                step: 5, needsGrant: false, globeNeedsChange: false, branch: false, singleSource: true)
                == .layoutEmpty)
        #expect(
            OnboardingButtonRule.screen(
                step: 9, needsGrant: false, globeNeedsChange: false, branch: false, singleSource: false)
                == .layoutList)
    }
}
