import Foundation
import Testing
@testable import FnCapsCore

/// 「문제 알리기」 전송(D-10, D-34, D-39, D-42, D-31). 네트워크는 부르지 않는다.
@Suite struct ReportOutcomeTests {
    private let endpoint = URL(string: "https://fncaps-reports.example.workers.dev/report")!

    private func payload(email: String? = nil, appVersion: String = "1.0") -> ReportPayload {
        ReportPayload(
            installId: "0f0e0d0c-0b0a-4908-8706-050403020100",
            appVersion: appVersion,
            message: "글",
            diagnostics: "diagnostics",
            email: email)
    }

    private func json(_ obj: [String: Any]) -> Data {
        (try? JSONSerialization.data(withJSONObject: obj)) ?? Data()
    }

    // MARK: 응답 매핑 (D-34)

    @Test func mapsStatusToOutcome() {
        #expect(ReportResponse.outcome(status: 201, data: json(["ok": true, "issue": 12])) == .sent(issue: 12))
        #expect(ReportResponse.outcome(status: 201, data: json(["ok": true])) == .sent(issue: nil))
        #expect(ReportResponse.outcome(status: 201, data: Data("nope".utf8)) == .sent(issue: nil))
        #expect(ReportResponse.outcome(status: 400, data: Data()) == .badRequest)
        #expect(ReportResponse.outcome(status: 413, data: Data()) == .tooLarge)
        #expect(ReportResponse.outcome(status: 429, data: Data()) == .rateLimited)
        #expect(ReportResponse.outcome(status: 502, data: Data()) == .upstream)
        #expect(ReportResponse.outcome(status: 503, data: Data()) == .notConfigured)
        #expect(ReportResponse.outcome(status: nil, data: nil) == .network)
        #expect(ReportResponse.outcome(status: 500, data: Data()) == .other)
        #expect(ReportResponse.outcome(status: 404, data: Data()) == .other)
    }

    @Test func serverWordsAreNotKept() {
        // 서버 문구는 화면·로그에 내지 않는다(T-04.2-08). 400 본문을 읽어도 .badRequest 하나뿐이다.
        let body = json(["ok": false, "error": "bad_request: 답장 메일 형식"])
        #expect(ReportResponse.outcome(status: 400, data: body) == .badRequest)
    }

    // MARK: 글 길이 (APP-21)

    @Test func messageUnitsAreUTF16() {
        #expect(ReportInput.maxMessageUnits == 5000)
        #expect(ReportInput.messageUnits("가😀") == 3)
        #expect(ReportInput.messageUnits("abc") == 3)
        #expect(!ReportInput.isMessageTooLong(String(repeating: "a", count: 5000)))
        #expect(ReportInput.isMessageTooLong(String(repeating: "a", count: 5001)))
    }

    // MARK: 보내기 가능 여부

    @Test func canSendRequiresMessageEmailAndPreview() {
        #expect(ReportInput.canSend(message: "   ", email: "", previewReady: true, sending: false) == false)
        #expect(ReportInput.canSend(message: "글", email: "a@b", previewReady: true, sending: false) == false)
        #expect(ReportInput.canSend(message: "글", email: "", previewReady: true, sending: false))
        #expect(ReportInput.canSend(message: "글", email: "a@b.co", previewReady: true, sending: false))
        #expect(ReportInput.canSend(message: "글", email: "", previewReady: false, sending: false) == false)
        #expect(ReportInput.canSend(message: "글", email: "", previewReady: true, sending: true) == false)
        #expect(ReportInput.canSend(message: String(repeating: "a", count: 5001), email: "", previewReady: true, sending: false) == false)
    }

    // MARK: 메일 (D-39)

    @Test func emailIsValidTable() {
        #expect(ReportInput.maxEmailLength == 254)
        // 통과
        for good in ["", "  ", "a@b.co", "x.y@sub.example.org", "a@.b.c"] {
            #expect(ReportInput.emailIsValid(good), "\(good)")
        }
        // 거절
        for bad in ["a@b", "ab.co", "a@bco", "a@.c", "a@b.", "a b@c.d", "a`@b.c", "a@b@c.d"] {
            #expect(!ReportInput.emailIsValid(bad), "\(bad)")
        }
        let local = String(repeating: "a", count: 250)
        #expect(!ReportInput.emailIsValid(local + "@b.co")) // 255자
        #expect(ReportInput.emailIsValid(String(repeating: "a", count: 249) + "@b.co")) // 254자
    }

    /// 메일 형식의 단일 정의: 앱 패턴이 Worker `EMAIL_RE`의 슬래시 사이 문자열과 같아야 한다.
    @Test func emailPatternMatchesWorker() throws {
        let file = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("worker/src/index.js")
        let text = try String(contentsOf: file, encoding: .utf8)
        guard let line = text.split(separator: "\n").first(where: { $0.hasPrefix("const EMAIL_RE = /") }) else {
            Issue.record("worker/src/index.js에 EMAIL_RE 정의가 없다")
            return
        }
        let parts = line.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count >= 2 else {
            Issue.record("EMAIL_RE 줄 형식이 예상과 다르다: \(line)")
            return
        }
        #expect(String(parts[1]) == ReportInput.emailPattern)
    }

    // MARK: 요청 본문 (D-42)

    @Test func payloadOmitsEmailKeyWhenEmpty() throws {
        for empty in ["", "   ", nil] as [String?] {
            let data = try JSONEncoder().encode(payload(email: empty))
            let obj = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
            #expect(obj["email"] == nil, "email=\(String(describing: empty))")
            #expect(obj["message"] as? String == "글")
            #expect(obj["installId"] as? String == "0f0e0d0c-0b0a-4908-8706-050403020100")
        }
    }

    @Test func payloadTrimsAndKeepsEmail() throws {
        let data = try JSONEncoder().encode(payload(email: "  a@b.co  "))
        let obj = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(obj["email"] as? String == "a@b.co")
    }

    @Test func payloadClipsAppVersion() throws {
        let data = try JSONEncoder().encode(payload(appVersion: String(repeating: "1", count: 41)))
        let obj = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect((obj["appVersion"] as? String)?.count == 40)
    }

    // MARK: 요청

    @Test func requestIsPOSTJSONWithFixedEndpoint() throws {
        let r = ReportRequest.make(endpoint: endpoint, payload: payload(), appVersion: "1.0")
        #expect(r.url == endpoint)
        #expect(r.httpMethod == "POST")
        #expect(r.value(forHTTPHeaderField: "content-type") == "application/json")
        #expect(r.value(forHTTPHeaderField: "User-Agent") == "FnCaps/1.0")
        #expect(r.timeoutInterval == 15)
        #expect(r.httpShouldHandleCookies == false)
        let body = try #require(r.httpBody)
        let obj = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(obj["message"] as? String == "글")
    }

    @Test func userAgentDropsUnsafeCharacters() throws {
        let r = ReportRequest.make(endpoint: endpoint, payload: payload(), appVersion: "1.0\r\nX-Evil: 1")
        let ua = try #require(r.value(forHTTPHeaderField: "User-Agent"))
        #expect(!ua.contains("\r") && !ua.contains("\n") && !ua.contains(" "))
        #expect(ua.hasPrefix("FnCaps/1.0"))
    }

    // MARK: 설치 번호 (D-31)

    @Test func installIDResolves() {
        let fresh = InstallID.resolve(stored: nil)
        #expect(fresh.isNew)
        #expect(UUID(uuidString: fresh.id) != nil)
        #expect(fresh.id == fresh.id.lowercased())

        let bad = InstallID.resolve(stored: "bad")
        #expect(bad.isNew)
        #expect(UUID(uuidString: bad.id) != nil)

        let stored = "0F0E0D0C-0B0A-4908-8706-050403020100"
        let kept = InstallID.resolve(stored: stored)
        #expect(!kept.isNew)
        #expect(kept.id == stored.lowercased())
    }

    // MARK: 전송

    @Test func sendThrowingFetchIsNetwork() async {
        struct Boom: Error {}
        let outcome = await ReportClient.send(endpoint: endpoint, payload: payload(), appVersion: "1.0") { _ in
            throw Boom()
        }
        #expect(outcome == .network)
    }

    @Test func sendUsesInjectedFetch() async throws {
        let body = json(["ok": true, "issue": 7])
        let outcome = await ReportClient.send(endpoint: endpoint, payload: payload(), appVersion: "1.0") { req in
            let resp = try #require(HTTPURLResponse(url: req.url!, statusCode: 201, httpVersion: nil, headerFields: nil))
            return (body, resp)
        }
        #expect(outcome == .sent(issue: 7))
    }

    @Test func sendNonHTTPResponseIsNetwork() async {
        let outcome = await ReportClient.send(endpoint: endpoint, payload: payload(), appVersion: "1.0") { req in
            (Data(), URLResponse(url: req.url!, mimeType: nil, expectedContentLength: 0, textEncodingName: nil))
        }
        #expect(outcome == .network)
    }
}
