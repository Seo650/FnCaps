import Combine
import Foundation
import FnCapsCore

/// 「문제 알리기」 전송 상태(D-10·D-11·D-31·D-34). 메인 스레드 전용.
/// 글·메일은 프로퍼티로 갖지 않는다(D-40). 화면(SettingsUIState)이 입력 중에만 들고 있다가 넘긴다.
/// 보내는 중에 창을 닫아도 요청은 끝까지 두고, 결과는 phase에 남긴다(창 처리는 화면 몫).
final class ReportController: ObservableObject {
    enum Phase: Equatable {
        case idle
        case sending
        case done(ReportOutcome)
    }

    typealias Fetch = (URLRequest) async throws -> (Data, URLResponse)

    @Published private(set) var phase: Phase = .idle
    /// 전송할 진단 본문. nil이면 아직 만드는 중이다(D-10: 미리보기 = 전송 문자열).
    @Published private(set) var preview: String?

    private enum Key {
        static let installId = "reportInstallId"
    }

    /// nil이면 메모리에만 둔다(렌더 도구용).
    private let defaults: UserDefaults?
    private let fetch: Fetch
    /// defaults가 nil일 때 같은 실행 안에서 번호를 유지한다.
    private var memoryInstallId: String?

    init(defaults: UserDefaults?, fetch: Fetch? = nil) {
        self.defaults = defaults
        if let fetch {
            self.fetch = fetch
        } else {
            // 쿠키·캐시 없음. 총 시간 상한 15초(RESEARCH Pitfall 5, T-04.2-21).
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 15
            config.timeoutIntervalForResource = 15
            config.httpCookieStorage = nil
            config.urlCache = nil
            config.requestCachePolicy = .reloadIgnoringLocalCacheData
            let session = URLSession(configuration: config)
            self.fetch = { request in try await session.data(for: request) }
        }
    }

    // MARK: 설치 번호 (D-31)

    /// 무작위 UUID 하나. 첫 사용 때 만들어 저장하고 이후 같은 값을 쓴다. 기기 고유값은 쓰지 않는다.
    var installId: String {
        let resolved = InstallID.resolve(stored: defaults?.string(forKey: Key.installId) ?? memoryInstallId)
        if resolved.isNew {
            if defaults != nil {
                defaults?.set(resolved.id, forKey: Key.installId)
            } else {
                memoryInstallId = resolved.id
            }
        }
        return resolved.id
    }

    // MARK: 미리보기

    /// 화면이 쪽이 나타날 때 부른다. 진단 읽기(IOHID·hidutil)가 있어 다음 메인 차례로 미룬다.
    /// 한 번 만든 문자열을 미리보기와 전송에 함께 쓴다(D-10).
    func prepare(_ make: @escaping () -> String) {
        preview = nil
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.preview = make()
        }
    }

    // MARK: 전송

    /// 보내는 중이거나 미리보기가 없으면 무시한다(T-04.2-21).
    func send(message: String, email: String, appVersion: String) {
        let sending = phase == .sending
        guard !sending, preview != nil else { return }
        guard ReportInput.canSend(
            message: message, email: email, previewReady: true, sending: sending)
        else { return }
        phase = .sending
        // 미리보기와 같은 문자열을 보낸다(D-10). 사이에 다른 스레드가 값을 바꾸지 않는다.
        let payload = ReportPayload(
            installId: installId, appVersion: appVersion, message: message,
            diagnostics: preview!, email: email)
        let fetch = self.fetch
        Task {
            let outcome = await ReportClient.send(
                endpoint: ExternalLinks.reportEndpoint, payload: payload,
                appVersion: appVersion, fetch: fetch)
            await MainActor.run {
                self.phase = .done(outcome)
                // 결과 코드만 남긴다. 글·메일·응답 본문은 남기지 않는다(T-04.2-18).
                AppLog.info("report result=\(Self.tag(outcome))")
            }
        }
    }

    /// 성공 창을 닫은 뒤 화면이 부른다. 다음에 열 때 prepare가 다시 진단을 만든다.
    func reset() {
        phase = .idle
        preview = nil
    }

    /// 다음 입력 때 오류 문구를 지운다(UI-SPEC). 성공 결과는 그대로 둔다.
    func clearError() {
        if case .done(let outcome) = phase, !Self.isSent(outcome) {
            phase = .idle
        }
    }

    /// 로그에 쓰는 영어 고정 이름. 서버 문구는 쓰지 않는다(T-04.2-08).
    private static func tag(_ outcome: ReportOutcome) -> String {
        switch outcome {
        case .sent: return "sent"
        case .badRequest: return "badRequest"
        case .tooLarge: return "tooLarge"
        case .rateLimited: return "rateLimited"
        case .upstream: return "upstream"
        case .notConfigured: return "notConfigured"
        case .network: return "network"
        case .other: return "other"
        }
    }

    private static func isSent(_ outcome: ReportOutcome) -> Bool {
        if case .sent = outcome { return true }
        return false
    }

    #if DEBUG
    /// 렌더 도구 전용.
    func debugSet(phase: Phase, preview: String?) {
        self.phase = phase
        self.preview = preview
    }
    #endif
}
