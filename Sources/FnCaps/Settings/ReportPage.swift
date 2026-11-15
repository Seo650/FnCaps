import AppKit
import FnCapsCore
import SwiftUI

/// 「문제 알리기」 쪽(D-09, D-10, D-30, D-39~D-43).
/// 글·메일은 `ui` 메모리에만 있고(D-40), [보내기]를 누를 때만 `reports`로 넘겨 Worker에 보낸다.
/// 성공 뒤 비우기·확인 시트는 쪽이 아니라 창 컨트롤러가 맡는다(쪽을 옮겨도 결과를 놓치지 않게).
struct ReportPage: View {
    @ObservedObject var model: AppModel
    @ObservedObject var ui: SettingsUIState
    @ObservedObject var reports: ReportController

    // MARK: 값

    private var units: Int { ReportInput.messageUnits(ui.reportMessage) }

    /// 4,500자부터 글자 수를 보인다(Worker 5,000자 한도).
    private var showCount: Bool { units >= 4500 }

    /// 값이 있을 때만 형식 검사를 한다. 비어 있으면 보낼 수 있다(D-39).
    private var emailInvalid: Bool {
        let trimmed = ui.reportEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && !ReportInput.emailIsValid(ui.reportEmail)
    }

    private var sending: Bool { reports.phase == .sending }

    private var canSend: Bool {
        ReportInput.canSend(message: ui.reportMessage, email: ui.reportEmail,
                            previewReady: reports.preview != nil, sending: sending)
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }

    // MARK: 본문

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.groupSpacing) {
                VStack(alignment: .leading, spacing: DS.s(8)) {
                    Text(verbatim: L("report.title"))
                        .font(DS.pageTitle)
                    Text(verbatim: L("report.intro"))
                        .font(DS.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                messageGroup
                emailGroup
                previewGroup
                sendRow
            }
            .padding(.horizontal, DS.pageInsetH)
            .padding(.top, DS.pageInsetTop)
            .padding(.bottom, DS.s(20))
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear(perform: prepareIfNeeded)
        .onChange(of: ui.reportMessage) { _, _ in reports.clearError() }
        .onChange(of: ui.reportEmail) { _, _ in reports.clearError() }
        // reset으로 미리보기가 비면(예: 성공 처리) 쪽이 보이는 동안 다시 만든다.
        .onChange(of: reports.preview) { _, newValue in
            if newValue == nil { prepareIfNeeded() }
        }
    }

    // MARK: 내용

    private var messageGroup: some View {
        SettingsGroup(title: L("report.message.title")) {
            VStack(alignment: .leading, spacing: 0) {
                TextEditor(text: $ui.reportMessage)
                    .font(DS.controlFont)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: DS.s(120))
                    .padding(DS.rowInset)
                    .accessibilityLabel(L("report.message.title"))
                    .disabled(sending)
                    .overlay(alignment: .topLeading) {
                        if ui.reportMessage.isEmpty {
                            Text(verbatim: L("report.message.placeholder"))
                                .font(DS.controlFont)
                                .foregroundStyle(.tertiary)
                                .padding(.leading, DS.rowInset + 5)
                                .padding(.top, DS.rowInset + 1)
                                .allowsHitTesting(false)
                                .accessibilityHidden(true)
                        }
                    }
                if showCount {
                    HStack(spacing: DS.s(4)) {
                        if units > ReportInput.maxMessageUnits {
                            StatusDot(color: DS.warn)
                        }
                        Text(verbatim: LF("report.message.count", units))
                            .font(DS.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.horizontal, DS.rowInset)
                    .padding(.bottom, DS.s(8))
                }
            }
        }
    }

    // MARK: 메일 (선택)

    private var emailGroup: some View {
        SettingsGroup(title: L("report.email.title"), description: L("report.email.caption")) {
            VStack(alignment: .leading, spacing: DS.s(4)) {
                // placeholder는 번역하지 않는다(형식 예시).
                TextField("", text: $ui.reportEmail, prompt: Text(verbatim: "name@example.com"))
                    .textFieldStyle(.plain)
                    .font(DS.controlFont)
                    .frame(height: DS.controlHeight)
                    .padding(.horizontal, DS.s(8))
                    .background(
                        RoundedRectangle(cornerRadius: DS.controlCornerRadius, style: .continuous)
                            .fill(Color(nsColor: .textBackgroundColor)))
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.controlCornerRadius, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.15)))
                    .padding(.horizontal, DS.rowInset)
                    .padding(.top, DS.s(8))
                    .padding(.bottom, emailInvalid ? DS.s(4) : DS.s(8))
                    .accessibilityLabel(L("report.email.title"))
                    .disabled(sending)
                if emailInvalid {
                    HStack(spacing: DS.s(4)) {
                        StatusDot(color: DS.warn)
                        Text(verbatim: L("report.email.invalid"))
                            .font(DS.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, DS.rowInset)
                    .padding(.bottom, DS.s(8))
                }
            }
        }
    }

    // MARK: 보낼 정보 (D-10, D-41)

    private var previewGroup: some View {
        SettingsGroup(title: L("report.preview.title"), description: L("report.preview.caption")) {
            DisclosureGroup(isExpanded: $ui.reportPreviewOpen) {
                previewBody
                    .padding(.top, DS.s(8))
            } label: {
                // 작은 ▸만 눌리지 않게 글자와 남은 줄 폭 전체를 누를 수 있게 한다.
                Text(verbatim: L("report.preview.toggle"))
                    .font(DS.rowTitle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture { withAnimation { ui.reportPreviewOpen.toggle() } }
                    .accessibilityLabel(L("report.preview.title"))
            }
            .padding(.horizontal, DS.rowInset)
            .padding(.vertical, DS.s(10))
        }
    }

    @ViewBuilder
    private var previewBody: some View {
        if let preview = reports.preview {
            SettingsBox {
                ScrollView {
                    Text(verbatim: previewText(preview))
                        .font(DS.caption.monospaced())
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(DS.rowInset)
                }
                .frame(maxHeight: DS.s(200))
            }
        } else {
            HStack(spacing: DS.s(6)) {
                ProgressView().controlSize(.small)
                Text(verbatim: L("report.preview.loading"))
                    .font(DS.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, DS.s(4))
        }
    }

    /// 미리보기 = 전송 문자열(D-10). 메일을 적었으면 맨 위에 한 줄을 더한다(D-41).
    private func previewText(_ preview: String) -> String {
        let trimmedEmail = ui.reportEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedEmail.isEmpty else { return preview }
        return LF("report.preview.email", trimmedEmail) + "\n" + preview
    }

    // MARK: 보내기 줄

    private var sendRow: some View {
        HStack(spacing: DS.s(8)) {
            statusView
            Spacer(minLength: DS.s(8))
            Button(L("report.send")) {
                reports.send(message: ui.reportMessage, email: ui.reportEmail, appVersion: appVersion)
            }
            .buttonStyle(ProminentButtonStyle())
            // 글 상자에서 Return이 줄바꿈이므로 기본 버튼(.defaultAction)을 쓰지 않는다.
            .disabled(!canSend)
        }
    }

    @ViewBuilder
    private var statusView: some View {
        if sending {
            HStack(spacing: DS.s(6)) {
                ProgressView().controlSize(.small)
                Text(verbatim: L("report.sending"))
                    .font(DS.caption)
                    .foregroundStyle(.secondary)
            }
        } else if case .done(let outcome) = reports.phase, !isSent(outcome) {
            HStack(alignment: .firstTextBaseline, spacing: DS.s(6)) {
                StatusDot(color: DS.warn)
                Text(verbatim: errorText(outcome))
                    .font(DS.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// 서버 응답 본문은 쓰지 않고 정해진 문구만 고른다(T-04.2-26).
    private func errorText(_ outcome: ReportOutcome) -> String {
        switch outcome {
        case .badRequest: return L("report.error.badRequest")
        case .tooLarge: return L("report.error.tooLarge")
        case .rateLimited: return L("report.error.rateLimited")
        case .upstream: return L("report.error.upstream")
        case .notConfigured: return L("report.error.notConfigured")
        case .network: return L("report.error.network")
        case .sent, .other: return L("report.error.other")
        }
    }

    private func isSent(_ outcome: ReportOutcome) -> Bool {
        if case .sent = outcome { return true }
        return false
    }

    // MARK: 준비

    /// 쪽이 나타날 때 한 번 진단 문자열을 만든다(D-10). 아직 없거나 대기 상태면 다시 만든다.
    private func prepareIfNeeded() {
        guard reports.preview == nil || reports.phase == .idle else { return }
        reports.prepare { [model] in model.diagnosticsText() }
    }
}
