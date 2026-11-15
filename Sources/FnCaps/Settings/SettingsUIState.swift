import FnCapsCore
import SwiftUI

enum SettingsPage: String, CaseIterable, Identifiable {
    case general, keys, advanced, help, about
    case report

    /// 사이드바 항목. 「정보」를 일반 위에 둔다(D-45, 앱 머리는 보이기만 한다).
    /// 「문제 알리기」는 맨 끝이다(D-30, 「도움말」과의 사이는 사이드바가 구분선을 그린다).
    static let sidebarItems: [SettingsPage] = [.about, .general, .keys, .advanced, .help, .report]

    var id: String { rawValue }

    /// 사이드바 항목 이름. 「FnCaps 정보」 쪽은 사이드바에서 짧게 「정보」로 쓴다.
    var sidebarKey: String { self == .about ? "sidebar.aboutItem" : titleKey }

    var titleKey: String {
        switch self {
        case .general: return "sidebar.general"
        case .keys: return "sidebar.keys"
        case .advanced: return "sidebar.advanced"
        case .help: return "sidebar.help"
        case .about: return "sidebar.about"
        case .report: return "sidebar.report"
        }
    }

    var symbol: String {
        switch self {
        case .general: return "gearshape"
        case .keys: return "keyboard"
        case .advanced: return "slider.horizontal.3"
        case .help: return "questionmark.circle"
        case .about: return "info.circle"
        case .report: return "exclamationmark.bubble"
        }
    }
}

/// 도움말 「설정하기」의 두 그림(D-47): macOS 기본 전환과 FnCaps 권장 배치.
enum HelpSetupSegment: String, CaseIterable, Identifiable {
    case macOS, recommended

    var id: String { rawValue }
}

/// 설정창 화면 상태. 설정값은 AppModel이 갖고 여기에는 화면 동작만 둔다.
/// (SDK 27 빌드 제약으로 화면 상태는 ObservableObject로 둔다)
final class SettingsUIState: ObservableObject {
    /// 처음 설정 진행 저장(04.4 D-18). 기본은 메모리 저장이라 렌더 하니스가 사용자 defaults에 쓰지 않는다(T-04.4-04).
    /// 실제 창은 SettingsWindowController가 `.standard` 기반 값을 넘긴다.
    let firstRun: FirstRunSetup
    /// 처음 설정 화면 여부. 쪽(page)을 늘리지 않고 이 값 하나로 전환한다.
    /// (@State를 쓸 수 없어 화면 상태를 여기에 둔다: SDK 27 빌드 제약)
    @Published var setupMode = false
    @Published var setupStep = 1
    /// 5단계 「직접 설정」 분기 쪽을 보이는지. 저장하지 않는다(UI-SPEC S-17): 단계 이동·나가기·마치기·
    /// 이어서 들어오기에서 false로 돌아가 5단계 목록으로 온다.
    /// (@State를 쓸 수 없어 화면 상태를 여기에 둔다: SDK 27 빌드 제약)
    @Published var setupBranch = false
    /// 5단계 「직접 설정」 행 호버(DS.dropHighlight 바탕, UI-SPEC §6-5).
    /// (@State를 쓸 수 없어 화면 상태를 여기에 둔다: SDK 27 빌드 제약)
    @Published var setupCustomHover = false

    init(firstRun: FirstRunSetup = FirstRunSetup(defaults: nil)) {
        self.firstRun = firstRun
    }

    @Published var selectedPage: SettingsPage = .general
    @Published var openInfoID: String?
    @Published var selectedExceptionID: String?
    @Published var newTagIDs: Set<String> = []
    @Published var exceptionError: Bool = false
    @Published var supportOpenFailed = false
    /// 정보 쪽 GitHub [Star] 열기 실패 캡션(UI-SPEC §9). supportOpenFailed와 같은 모양으로 쓴다.
    /// (@State를 쓸 수 없어 화면 상태를 여기에 둔다: SDK 27 빌드 제약)
    @Published var githubOpenFailed = false
    /// 설정창이 화면에 보이는 동안만 true. 창 컨트롤러(04-08)만 쓴다.
    @Published var windowVisible = false
    /// 메모 줄 글자. 메모리에만 두고 저장·기록하지 않는다(M7, T-04-40). 창을 닫으면 비운다.
    @Published var memoText = ""
    /// 키와 언어 쪽 화면 상태(04-16, 04-17).
    let keys = KeysPageState()
    /// 도움말 「설정하기」 그림 전환(D-47). 기본은 할 일이 보이는 「FnCaps 권장」이다.
    /// (@State를 쓸 수 없어 화면 상태를 여기에 둔다: SDK 27 빌드 제약)
    @Published var helpSetupSegment: HelpSetupSegment = .recommended
    /// 도움말 「설정하기」 축소판이 `KeyRingBox`에 넘길 빈 화면 상태. 보기 전용이라 끌기·녹화를
    /// 하지 않는다. 「키와 언어」 쪽의 `keys`와 섞지 않는다.
    let helpMiniKeys = KeysPageState()
    /// 다른 쪽에서 도움말 묶음으로 올 때 갈 묶음 id. HelpPage가 한 번 쓰고 nil로 지운다.
    @Published var helpAnchor: String?
    /// 확인 창이 떠 있는 동안 값이 있다. 창 컨트롤러(04.4-06)가 소비하고 지운다.
    /// 값이 있는 동안 모든 후보 버튼이 비활성이라 연타로 창이 여러 개 뜨지 않는다(T-04.4-10).
    /// (@State를 쓸 수 없어 화면 상태를 여기에 둔다: SDK 27 빌드 제약)
    @Published var pendingCandidate: GuidancePlan?
    /// 5단계 목록에서 [마침]을 눌렀을 때의 확인 창 요청. 창 컨트롤러가 띄우고 false로 되돌린다(04.5 UAT F-5).
    @Published var finishPromptRequested = false
    /// 다른 쪽에서 「키와 언어」 묶음으로 올 때 갈 id. KeysPage가 한 번 쓰고 지운다. 지금은 "keys.assigned"만.
    @Published var keysAnchor: String?
    /// D-10: 적용 뒤 직접 정해야 하는 빈 녹화 칸 강조. 0.6초 뒤 KeysPage가 지운다.
    @Published var keysChordHighlight: Set<SourceID> = []
    /// 스크롤 도착한 묶음 제목 강조. 0.6초 뒤 HelpPage가 지운다.
    /// (@State를 쓸 수 없어 화면 상태를 여기에 둔다: SDK 27 빌드 제약)
    @Published var helpHighlighted: String?
    /// 「문제 알리기」 글. 메모리에만 두고 저장·기록하지 않는다(D-40). 창을 닫으면 비운다.
    @Published var reportMessage = ""
    /// 「문제 알리기」 메일. 메모리에만 두고 저장·기록하지 않는다(D-40). 창을 닫으면 비운다.
    @Published var reportEmail = ""
    /// 「문제 알리기」 「보낼 정보」 펼침. (@State를 쓸 수 없어 여기에 둔다: SDK 27 빌드 제약)
    @Published var reportPreviewOpen = false

    /// D-19·D-46 공용 입구: 도움말 「설정하기」로 옮긴다. 「일반」의 [권장 배치 보기] 등이 이 함수를 써서
    /// 항상 「FnCaps 권장」 그림에 도착한다. (D-50은 04.4 D-20으로 없어짐)
    func showHelpSetup() {
        helpSetupSegment = .recommended
        helpAnchor = "help.setup"
        selectedPage = .help
    }

    /// D-16 이어감, D-18: 저장된 단계에서 처음 설정을 연다.
    func enterSetup(globeOK: Bool) {
        firstRun.resume()
        setupStep = FirstRunSetup.resumeStep(stored: firstRun.step, globeOK: globeOK)
        firstRun.setStep(setupStep)
        setupBranch = false
        setupMode = true
    }

    /// D-18: 단계를 옮기고 저장한다. 「직접 설정」 분기는 저장하지 않는다(UI-SPEC S-17).
    func setupGo(to step: Int) {
        setupStep = step
        setupBranch = false
        firstRun.setStep(step)
    }

    /// D-16: [나중에]·창 닫기. left를 저장하고 평소 창으로 바꾼다.
    func leaveSetup() {
        firstRun.markLeft()
        setupBranch = false
        setupCustomHover = false
        setupMode = false
    }

    /// D-15 마치면 「키와 언어」로, D-16 사이드바 항목이 사라진다.
    func finishSetup() {
        firstRun.finish()
        setupBranch = false
        setupCustomHover = false
        setupMode = false
        selectedPage = .keys
    }

    /// 5단계 [마침]. 후보 목록 쪽에서는 권장 배치를 도움말에서 다시 볼 수 있다는 확인 창을 먼저 띄운다
    /// (그냥 누르고 지나가는 사람이 많다, 04.5 UAT 사용자 결정). 「직접 설정」 분기 쪽은 바로 마친다.
    func requestFinish() {
        if setupBranch { finishSetup() } else { finishPromptRequested = true }
    }

    /// D-09: 후보 [이 설정 사용하기] 요청. 확인 창은 창 컨트롤러(04.4-06)가 띄운다.
    /// 이미 요청이 남아 있으면 받지 않는다(연타 방지, T-04.4-10).
    func requestCandidate(_ plan: GuidancePlan) {
        guard pendingCandidate == nil else { return }
        pendingCandidate = plan
    }

    func infoBinding(_ id: String) -> Binding<Bool> {
        Binding(
            get: { self.openInfoID == id },
            set: { self.openInfoID = $0 ? id : nil })
    }
}
