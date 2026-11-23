import FnCapsCore
import SwiftUI

/// 처음 설정 화면 상태와 진행 저장(04.4 D-18). AppDelegate가 하나를 만들어 처음 설정 창(화면)과
/// 설정 창 사이드바·메뉴 줄(읽기)이 함께 본다(08.1 D-03).
/// `revision`은 `FirstRunSetup`에 쓸 때마다 올라 관찰자가 같은 차례에 다시 그린다. 후보·[마침] 요청은
/// 처음 설정 창 컨트롤러만 구독한다(설정 창 쪽 요청은 `SettingsUIState`에 따로 있다).
final class OnboardingUIState: ObservableObject, CandidateRequesting {
    /// 처음 설정 진행 저장(04.4 D-18). 기본은 메모리 저장이라 렌더 하니스가 사용자 defaults에 쓰지 않는다(T-04.4-04).
    /// 실제 창은 AppDelegate가 `.standard` 기반 값을 넘긴다.
    let firstRun: FirstRunSetup
    /// 후보 그림 축소판의 화면 상태(보기 전용). 설정 창의 `helpMiniKeys`와 섞지 않는다(08.1-02).
    let miniKeys = KeysPageState()
    @Published var setupStep = 1
    /// 5단계 「직접 설정」 분기 쪽을 보이는지. 저장하지 않는다(UI-SPEC S-17): 단계 이동·나가기·마치기·
    /// 이어서 들어오기에서 false로 돌아가 5단계 목록으로 온다.
    /// (@State를 쓸 수 없어 화면 상태를 여기에 둔다: SDK 27 빌드 제약)
    @Published var setupBranch = false
    /// 5단계 「직접 설정」 행 호버(DS.dropHighlight 바탕, UI-SPEC §6-5).
    /// (@State를 쓸 수 없어 화면 상태를 여기에 둔다: SDK 27 빌드 제약)
    @Published var setupCustomHover = false
    /// 확인 창이 떠 있는 동안 값이 있다. 처음 설정 창 컨트롤러가 소비하고 지운다.
    /// 값이 있는 동안 모든 후보 버튼이 비활성이라 연타로 창이 여러 개 뜨지 않는다(T-04.4-10).
    /// (@State를 쓸 수 없어 화면 상태를 여기에 둔다: SDK 27 빌드 제약)
    @Published var pendingCandidate: GuidancePlan?
    /// 5단계 목록에서 [마침]을 눌렀을 때의 확인 창 요청. 처음 설정 창 컨트롤러가 띄우고 false로 되돌린다(04.5 UAT F-5).
    /// (@State를 쓸 수 없어 화면 상태를 여기에 둔다: SDK 27 빌드 제약)
    @Published var finishPromptRequested = false
    /// `FirstRunSetup`에 쓸 때마다 오른다. 사이드바 「처음 설정 n/5」 행과 메뉴 줄이 같은 차례에 다시 그리도록 알린다(D-03).
    @Published private(set) var revision = 0

    init(firstRun: FirstRunSetup = FirstRunSetup(defaults: nil)) {
        self.firstRun = firstRun
    }

    /// 아직 처음 설정을 마치지 않았는지. 사이드바 행·메뉴 줄이 보이는 조건과 같다(D-16).
    var isActive: Bool { firstRun.isActive }

    /// D-16 이어감, D-18: 저장된 단계에서 처음 설정을 연다. 권한이 없으면 2단계로 연다(G-08.1-4).
    /// 자른 단계를 저장한다(D-18).
    func enterSetup(globeOK: Bool, needsGrant: Bool) {
        firstRun.resume()
        setupStep = FirstRunSetup.resumeStep(stored: firstRun.step, globeOK: globeOK, needsGrant: needsGrant)
        firstRun.setStep(setupStep)
        setupBranch = false
        revision += 1
    }

    /// D-18: 단계를 옮기고 저장한다. 「직접 설정」 분기는 저장하지 않는다(UI-SPEC S-17).
    func setupGo(to step: Int) {
        setupStep = step
        setupBranch = false
        firstRun.setStep(step)
        revision += 1
    }

    /// D-16: [나중에]·창 닫기. left를 저장한다. 창을 닫는 일은 컨트롤러가 한다.
    func leaveSetup() {
        firstRun.markLeft()
        setupBranch = false
        setupCustomHover = false
        revision += 1
    }

    /// D-15: 마치고 저장한다. 「키와 언어」 이동은 컨트롤러가 설정 창에 시킨다(08.1 D-07).
    func finishSetup() {
        firstRun.finish()
        setupBranch = false
        setupCustomHover = false
        revision += 1
    }

    /// D-09: 후보 [이 설정 사용하기] 요청. 확인 창은 처음 설정 창 컨트롤러가 띄운다.
    /// 이미 요청이 남아 있으면 받지 않는다(연타 방지, T-04.4-10).
    func requestCandidate(_ plan: GuidancePlan) {
        guard pendingCandidate == nil else { return }
        pendingCandidate = plan
    }

    /// 사이드바 「처음 설정 n/5」의 n = 누르면 돌아갈 단계(멈춘 단계, 🌐가 맞으면 3 → 4, 권한이 없으면 2).
    /// 마친 단계 수가 아니다(04.5 UAT 사용자 결정, 2026-11-15). 처음 설정 대상이 아니면 nil이라 행이 없다(D-16).
    func sidebarStep(globeOK: Bool, needsGrant: Bool) -> Int? {
        guard firstRun.isActive else { return nil }
        return FirstRunSetup.resumeStep(stored: firstRun.step, globeOK: globeOK, needsGrant: needsGrant)
    }
}
