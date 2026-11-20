import AppKit
import FnCapsCore
import SwiftUI

/// 중요 업데이트 창의 내용(D-17). Sparkle `SUUpdateAlert` 순서를 따른다:
/// 아이콘, 제목, 버전 줄, 안내 글, 버튼. 건너뛰기 버튼은 없다.
///
/// 표시 상태는 `updates.phase`로만 정한다(UI-SPEC 「상태와 동작」). 뷰는 자기 상태를 두지 않는다.
/// 안내 글은 릴리스 노트 본문(외부 입력)이므로 `Text(verbatim:)`으로만 그린다.
/// 서식·링크·마크다운을 해석하지 않는다(T-06-09).
struct ImportantUpdateView: View {
    @ObservedObject var updates: UpdateController
    let offer: ImportantOffer
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DS.s(16)) {
            header
            noticeBox
            if let failureText {
                WarningNote(text: failureText)
            }
            buttonRow
        }
        // 창은 빈 도구 막대로 제목 막대를 높인다. 설정창처럼 내용을 제목 막대 밑까지 올리고, 위 여백은
        // 창 버튼 줄 아래로 직접 준다. 이래야 창 높이와 렌더 높이가 같다(06-02 V1).
        .padding(.top, DS.s(52))
        .padding(.bottom, DS.s(24))
        .padding(.horizontal, DS.pageInsetH)
        .frame(width: DS.s(420), alignment: .leading)
        .frame(maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea(.container, edges: .top)
    }

    // MARK: 머리

    private var header: some View {
        HStack(alignment: .top, spacing: DS.s(16)) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: DS.s(56), height: DS.s(56))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: DS.s(4)) {
                Text(verbatim: L("update.important.title"))
                    .font(DS.statusTitle)
                    .accessibilityAddTraits(.isHeader)
                Text(verbatim: LF("update.important.version", offer.version,
                                  UpdateController.currentVersion))
                    .font(DS.value)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: 안내 글

    /// 글 높이가 `DS.s(160)`을 넘으면 상자 안에서 스크롤하고 상자는 더 커지지 않는다(D-19-6).
    private var noticeBox: some View {
        SettingsBox {
            // ViewThatFits는 높이를 잴 때 작은 높이를 제안받으면 빈 ScrollView 쪽을 골라 상자가 비었다
            // (06-02 V1). 제안과 상관없이 「글 높이, 최대 DS.s(160)」을 직접 정한다.
            CappedHeight(max: DS.s(160)) {
                // 첫째는 높이만 재는 숨긴 사본이다. ScrollView는 높이 제안이 없어도 글 높이를 돌려주지 않는다.
                noticeText.hidden().accessibilityHidden(true)
                ScrollView(.vertical) { noticeText }
                    .scrollBounceBehavior(.basedOnSize)
            }
            .padding(DS.rowInset)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var noticeText: some View {
        Text(verbatim: offer.text)
            .font(DS.value)
            .lineSpacing(DS.s(4))
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
    }

    // MARK: 상태

    /// 실패·되돌림이면 상자 아래에 경고 줄을 붙인다. 재설치 불가도 같은 줄을 쓴다.
    private var failureText: String? {
        switch updates.phase {
        case .installFailed, .rolledBack:
            return updates.statusText()
        default:
            return nil
        }
    }

    private var isWorking: Bool {
        switch updates.phase {
        case .downloading, .verifying, .installing: return true
        default: return false
        }
    }

    /// 「지금 업데이트」를 누를 수 있는 상태. `UpdateController.install()`의 가드와 같다.
    private var updateEnabled: Bool {
        switch updates.phase {
        case .done(.available), .installFailed, .rolledBack: return true
        default: return false
        }
    }

    private var stageText: String {
        switch updates.phase {
        case .downloading: return L("about.update.downloading")
        case .verifying: return L("about.update.verifying")
        case .installing: return L("about.update.installing")
        default: return ""
        }
    }

    @ViewBuilder
    private var buttonRow: some View {
        if isWorking {
            // 설치기는 진행률을 주지 않으므로 스피너와 단계 글 한 줄만 둔다(UI-SPEC 「상태와 동작」).
            HStack(spacing: DS.s(8)) {
                ProgressView().controlSize(.small)
                Text(verbatim: stageText)
                    .font(DS.controlFont)
            }
            .frame(height: DS.controlHeight)
            .frame(maxWidth: .infinity, alignment: .leading)
        } else if isReinstallBlocked {
            // 평소 상태와 같이 오른쪽에 모으고 기본 버튼을 맨 오른쪽에 둔다(06-02 V4, 사용자 결정).
            HStack(spacing: DS.s(8)) {
                Spacer(minLength: 0)
                laterButton
                releasePageButton(prominent: true)
            }
        } else if case .installFailed = updates.phase {
            failureButtons
        } else if case .rolledBack = updates.phase {
            failureButtons
        } else {
            HStack(spacing: DS.s(8)) {
                Spacer(minLength: 0)
                laterButton
                updateNowButton
            }
        }
    }

    private var failureButtons: some View {
        HStack(spacing: DS.s(8)) {
            releasePageButton(prominent: false)
            Spacer(minLength: 0)
            laterButton
            updateNowButton
        }
    }

    private var isReinstallBlocked: Bool {
        switch updates.phase {
        case .installFailed(.notInstallable), .installFailed(.unsignedBuild):
            return true
        default:
            return false
        }
    }

    // MARK: 버튼

    @ViewBuilder
    private func releasePageButton(prominent: Bool) -> some View {
        // 릴리스 페이지는 고정 주소만 연다(T-06-10).
        if prominent {
            Button(L("about.update.releasePage")) {
                updates.openRelease(ExternalLinks.releasesLatest)
            }
            .buttonStyle(ProminentButtonStyle())
            .keyboardShortcut(.defaultAction)
        } else {
            Button(L("about.update.releasePage")) {
                updates.openRelease(ExternalLinks.releasesLatest)
            }
            .buttonStyle(PillButtonStyle())
        }
    }

    private var laterButton: some View {
        Button(L("update.important.later")) { close() }
            .buttonStyle(PillButtonStyle())
            .keyboardShortcut(.cancelAction)
    }

    private var updateNowButton: some View {
        Button(L("update.important.updateNow")) { updates.install() }
            .buttonStyle(ProminentButtonStyle())
            .keyboardShortcut(.defaultAction)
            .disabled(!updateEnabled)
    }
}

/// 첫째 자식(숨긴 글 사본)의 높이로 크기를 정하되 `max`를 넘지 않게 하고, 둘째 자식(ScrollView)을 그 크기에
/// 놓는다. 넘으면 ScrollView가 그 높이 안에서 스크롤한다. 바깥 높이 제안에 따라 크기가 바뀌지 않아 창 높이를
/// 잴 때와 그릴 때가 같다.
private struct CappedHeight: Layout {
    let max: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let measure = subviews.first else { return .zero }
        let width = proposal.width ?? measure.sizeThatFits(.unspecified).width
        let natural = measure.sizeThatFits(ProposedViewSize(width: width, height: nil)).height
        return CGSize(width: width, height: Swift.min(natural, max))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let size = ProposedViewSize(width: bounds.width, height: bounds.height)
        for child in subviews {
            child.place(at: bounds.origin, anchor: .topLeading, proposal: size)
        }
    }
}
