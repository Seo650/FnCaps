import Foundation

/// 「문제 알리기」 전송 결과(D-34). 보낸 응답 7종과 전송 성공 하나.
public enum ReportOutcome: Equatable, Sendable {
    /// 201. 이슈 번호를 읽었으면 담고, 못 읽어도 성공이다.
    case sent(issue: Int?)
    /// 400. 입력(설치 번호·글·메일) 형식이 Worker 규칙에 맞지 않는다.
    case badRequest
    /// 413. 글·진단 본문이 Worker 한도를 넘었다.
    case tooLarge
    /// 429. 설치 번호별 하루 제한 또는 IP별 분당 제한.
    case rateLimited
    /// 502. Worker가 GitHub에 이슈를 만들지 못했다.
    case upstream
    /// 503. Worker에 토큰이 없어 꺼져 있다.
    case notConfigured
    /// 응답이 없거나 HTTP가 아니다(네트워크 실패·시간 초과·던진 fetch).
    case network
    /// 위 어느 것도 아닌 응답.
    case other
}

/// Worker 응답 → ReportOutcome. 상태 코드와 issue 번호만 읽는다(T-04.2-08: 서버 문구는 쓰지 않는다).
public enum ReportResponse {
    public static func outcome(status: Int?, data: Data?) -> ReportOutcome {
        guard let status else { return .network }
        switch status {
        case 201: return .sent(issue: issueNumber(data))
        case 400: return .badRequest
        case 413: return .tooLarge
        case 429: return .rateLimited
        case 502: return .upstream
        case 503: return .notConfigured
        default: return .other
        }
    }

    /// 응답에서 읽는 유일한 값. 다른 필드는 버린다.
    private struct Reply: Decodable {
        let issue: Int?
    }

    static func issueNumber(_ data: Data?) -> Int? {
        guard let data, let reply = try? JSONDecoder().decode(Reply.self, from: data) else { return nil }
        return reply.issue
    }
}

/// 보내기 전 입력 검사(APP-21, D-39). 화면과 시험이 같은 규칙을 쓴다.
public enum ReportInput {
    /// 글 5,000자 한도. Worker JS `.length`와 같은 UTF-16 단위로 잰다.
    public static let maxMessageUnits = 5000
    /// 메일 254자 한도(Worker MAX_EMAIL).
    public static let maxEmailLength = 254
    /// 메일 형식의 단일 정의. `worker/src/index.js`의 EMAIL_RE 슬래시 사이 문자열과 글자 하나까지 같다.
    /// 바꾸면 두 곳을 함께 바꾼다(시험 `emailPatternMatchesWorker`가 대조한다).
    public static let emailPattern = "^[^\\s@`]+@[^\\s@`]+\\.[^\\s@`]+$"

    public static func messageUnits(_ message: String) -> Int { message.utf16.count }

    public static func isMessageTooLong(_ message: String) -> Bool {
        messageUnits(message) > maxMessageUnits
    }

    /// 빈 메일은 보낼 수 있다(D-39). 값이 있으면 trim 뒤 254자 이하이고 패턴 전체 일치여야 한다.
    public static func emailIsValid(_ email: String) -> Bool {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return true }
        if trimmed.utf16.count > maxEmailLength { return false }
        guard let re = try? NSRegularExpression(pattern: emailPattern) else { return false }
        let whole = NSRange(location: 0, length: (trimmed as NSString).length)
        return re.firstMatch(in: trimmed, options: [], range: whole)?.range == whole
    }

    /// [보내기]를 누를 수 있는지. 미리보기를 본 뒤에만 보낸다(D-10).
    public static func canSend(message: String, email: String, previewReady: Bool, sending: Bool) -> Bool {
        guard !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !isMessageTooLong(message),
              emailIsValid(email),
              previewReady, !sending else { return false }
        return true
    }
}

/// Worker로 보내는 JSON 본문. 메일이 비면 `email` 키 자체를 쓰지 않는다(D-42).
public struct ReportPayload: Encodable, Equatable, Sendable {
    public let installId: String
    public let appVersion: String
    public let message: String
    public let diagnostics: String
    public let email: String?

    public init(installId: String, appVersion: String, message: String, diagnostics: String, email: String?) {
        self.installId = installId
        self.appVersion = String(appVersion.prefix(40))
        self.message = message
        self.diagnostics = diagnostics
        let trimmed = (email ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        self.email = trimmed.isEmpty ? nil : trimmed
    }

    enum CodingKeys: String, CodingKey {
        case installId, appVersion, message, diagnostics, email
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(installId, forKey: .installId)
        try c.encode(appVersion, forKey: .appVersion)
        try c.encode(message, forKey: .message)
        try c.encode(diagnostics, forKey: .diagnostics)
        try c.encodeIfPresent(email, forKey: .email)
    }
}

/// 요청 만들기. URL은 넘겨받은 고정 상수만 쓴다(T-04.2-09: 사용자 입력으로 URL을 만들지 않는다).
public enum ReportRequest {
    public static func make(endpoint: URL, payload: ReportPayload, appVersion: String) -> URLRequest {
        var r = URLRequest(url: endpoint, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        r.httpMethod = "POST"
        r.httpShouldHandleCookies = false
        r.setValue("application/json", forHTTPHeaderField: "content-type")
        r.setValue("FnCaps/\(sanitized(appVersion))", forHTTPHeaderField: "User-Agent")
        r.httpBody = (try? JSONEncoder().encode(payload)) ?? Data()
        return r
    }

    /// User-Agent에 넣을 버전. 영숫자와 점만 남긴다(헤더 주입 방지).
    static func sanitized(_ version: String) -> String {
        String(version.filter { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == ".") })
    }
}

/// 전송. 네트워크 호출은 주입한 fetch로만 한다(UpdateCheck와 같은 모양).
public enum ReportClient {
    public static func send(endpoint: URL, payload: ReportPayload, appVersion: String,
                            fetch: (URLRequest) async throws -> (Data, URLResponse)) async -> ReportOutcome {
        let request = ReportRequest.make(endpoint: endpoint, payload: payload, appVersion: appVersion)
        guard let (data, response) = try? await fetch(request) else {
            return ReportResponse.outcome(status: nil, data: nil)
        }
        return ReportResponse.outcome(status: (response as? HTTPURLResponse)?.statusCode, data: data)
    }
}

/// 설치 번호(D-31). 무작위 UUID 하나만 쓴다. 기기 고유값은 쓰지 않는다.
public enum InstallID {
    /// 저장값이 UUID 형식이면 소문자로 정규화해 그대로 쓰고, 없거나 형식이 틀리면 새로 만든다.
    public static func resolve(stored: String?) -> (id: String, isNew: Bool) {
        if let stored, let uuid = UUID(uuidString: stored) {
            return (uuid.uuidString.lowercased(), false)
        }
        return (UUID().uuidString.lowercased(), true)
    }
}
