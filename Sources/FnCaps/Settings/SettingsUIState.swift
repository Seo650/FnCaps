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
/// 처음 설정 화면 상태는 별도 창의 `OnboardingUIState`가 갖는다(08.1 D-01, D-03).
/// (SDK 27 빌드 제약으로 화면 상태는 ObservableObject로 둔다)
final class SettingsUIState: ObservableObject {
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
