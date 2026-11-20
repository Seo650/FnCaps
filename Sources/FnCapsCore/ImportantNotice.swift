import Foundation

/// 릴리스 노트 본문(`releases/latest`의 `body`)의 「중요 업데이트」 표시를 읽는다(D-15, D-16).
///
/// 형식은 `release.sh`의 검사(`check_important_notes`)와 `packaging/release-notes/examples/important.md`
/// 견본이 정한다:
/// - 영어 절 제목은 줄 전체가 `## Important`인 줄이다.
/// - 여는 주석 줄은 `<!-- fncaps:important below=X.Y.Z`로 시작하고, `below=` 뒤 첫 낱말이 버전이다.
/// - 영어 글은 제목 다음 줄부터 첫 `#` 줄이나 여는 주석 줄 앞까지의 비지 않은 줄을 공백 하나로 이은 것이다.
/// - 언어 줄은 여는 주석 줄 다음부터 첫 닫는 줄(`-->`) 앞까지이고 `코드: 글` 꼴이다.
///   코드는 `languages`의 9개뿐이며, 같은 코드가 두 번 나오면 앞 줄을 쓴다.
///
/// 앱은 GitHub 웹에서 고친 본문의 `\r\n`·`\r`도 `\n`으로 본다. `release.sh` 쪽 검사가 더 엄격하다
/// (빠진 언어·중복·잘못된 below면 게시를 멈춘다).
public struct ImportantNotice: Equatable, Sendable {
    /// `below=` 값 그대로. 이 버전보다 낮은 앱에서만 창을 띄운다(D-16, Sparkle criticalUpdate).
    public let below: String
    /// `## Important` 영어 절의 글. 사용자 언어 줄이 없을 때 보인다.
    public let english: String
    /// 언어 코드별 글. `clean` 뒤 비지 않은 줄만 담는다.
    public let localized: [String: String]

    /// 앱이 받는 언어 줄의 코드. `release.sh` 검사와 같은 목록이다.
    public static let languages = [
        "ko", "ja", "zh-Hans", "zh-Hant", "de", "es", "fr", "ru", "uk",
    ]

    /// 안내 글의 앱 쪽 안전 상한(D-19-6). 게시 때 길이는 막지 않고 화면은 상자 스크롤로 푼다.
    public static let maxLength = 4000

    /// 앱 시작 뒤 이 시간 안에 뜬 창만 앞으로 가져온다(D-19-2, Sparkle dockless 예외).
    public static let launchActivationWindow: TimeInterval = 60

    // MARK: 파싱

    /// 본문에서 중요 표시를 읽는다. 표시가 없거나, 영어 글이 비었거나, below가 버전으로 읽히지 않으면 nil.
    public static func parse(_ body: String) -> ImportantNotice? {
        // GitHub 웹에서 고친 본문은 \r\n이다. 앱은 두 줄 끝을 \n으로 본다.
        let normalized = body
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let lines = normalized.components(separatedBy: "\n")

        guard let headerIndex = lines.firstIndex(where: {
            $0.trimmingCharacters(in: .whitespaces) == "## Important"
        }) else { return nil }

        var englishParts: [String] = []
        var openIndex: Int?
        var below: String?
        var i = headerIndex + 1
        while i < lines.count {
            let trimmed = lines[i].trimmingCharacters(in: .whitespaces)
            // 다음 제목이 먼저 오면 여는 주석 줄이 없는 것이다.
            if trimmed.hasPrefix("#") { break }
            if let value = openingBelow(trimmed) {
                openIndex = i
                below = value
                break
            }
            if !trimmed.isEmpty { englishParts.append(trimmed) }
            i += 1
        }
        // 여는 줄이 없거나, below가 없거나, 버전으로 읽히지 않으면 표시가 없는 것으로 본다.
        guard let openIndex, let below, AppVersion(below) != nil else { return nil }

        var localized: [String: String] = [:]
        var closed = false
        var j = openIndex + 1
        while j < lines.count {
            let trimmed = lines[j].trimmingCharacters(in: .whitespaces)
            if trimmed == "-->" { closed = true; break }
            if let (code, value) = languageLine(trimmed), localized[code] == nil {
                let cleaned = clean(value)
                if !cleaned.isEmpty { localized[code] = cleaned }
            }
            j += 1
        }
        // 닫는 줄이 없으면 표시가 없는 것으로 본다.
        guard closed else { return nil }

        let english = clean(englishParts.joined(separator: " "))
        guard !english.isEmpty else { return nil }

        return ImportantNotice(below: below, english: english, localized: localized)
    }

    /// 여는 주석 줄이면 `below=` 값을 돌려준다. `below=` 뒤 첫 낱말이 버전이다.
    private static func openingBelow(_ trimmed: String) -> String? {
        let prefix = "<!-- fncaps:important"
        guard trimmed.hasPrefix(prefix), let range = trimmed.range(of: "below=") else { return nil }
        let token = trimmed[range.upperBound...].prefix { !$0.isWhitespace }
        return token.isEmpty ? nil : String(token)
    }

    /// `코드: 글` 줄이면 (코드, 글)을 돌려준다. 모르는 코드와 콜론 뒤 공백이 없는 줄은 nil.
    private static func languageLine(_ trimmed: String) -> (String, String)? {
        guard let colon = trimmed.firstIndex(of: ":") else { return nil }
        let code = String(trimmed[trimmed.startIndex..<colon])
        guard languages.contains(code) else { return nil }
        let after = trimmed[trimmed.index(after: colon)...]
        guard after.first == " " else { return nil }
        return (code, String(after.drop { $0 == " " }))
    }

    // MARK: 정리

    /// 안내 글을 화면에 그리기 전에 정리한다(T-06-09).
    /// 제어 글자(탭·줄바꿈 포함, Unicode Cc)와 방향 제어 글자(U+202A–202E, U+2066–2069)를 지우고,
    /// 앞뒤 공백을 자르고, `maxLength` 글자에서 자른다. 글자 수는 Character 기준이다.
    public static func clean(_ text: String) -> String {
        var kept = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            if (0x202A...0x202E).contains(scalar.value) { continue }
            if (0x2066...0x2069).contains(scalar.value) { continue }
            if scalar.properties.generalCategory == .control { continue }
            kept.append(scalar)
        }
        let trimmed = String(kept).trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count > maxLength ? String(trimmed.prefix(maxLength)) : trimmed
    }

    // MARK: 판정

    /// 사용자 언어 줄을 고르고, 없으면 영어 절을 쓴다(D-16).
    public func text(language: String) -> String {
        if let line = localized[language], !line.isEmpty { return line }
        return english
    }

    /// 지금 버전이 `below`보다 낮을 때만 참이다(D-16). 지금 버전이 읽히지 않으면 거짓.
    public func applies(currentVersion: String) -> Bool {
        guard let current = AppVersion(currentVersion), let marker = AppVersion(below) else { return false }
        return current < marker
    }

    /// 자동 확인 결과로 창을 낼지 정한다(D-15, D-16).
    /// body가 없거나, 표시를 읽지 못하거나, 지금 버전이 below 이상이면 nil이다.
    /// 「한 번만」 저장 값은 받지 않는다(D-19-1: 다시 알림은 정기 확인 주기가 정한다).
    public static func offer(body: String?, latest: String, currentVersion: String,
                             language: String) -> ImportantOffer? {
        guard let body, let notice = parse(body), notice.applies(currentVersion: currentVersion) else {
            return nil
        }
        return ImportantOffer(version: latest, text: notice.text(language: language))
    }

    /// 앱 시작 뒤 60초 안에 뜬 창만 협조적 활성화로 앞에 놓는다(D-19-2).
    /// 시계가 되돌아가 `now`가 `launchedAt`보다 앞이면 거짓이다.
    public static func activatesOnShow(launchedAt: Date, now: Date) -> Bool {
        let elapsed = now.timeIntervalSince(launchedAt)
        return elapsed >= 0 && elapsed < launchActivationWindow
    }
}

/// 중요 업데이트 창에 보일 값(D-17). 버전은 릴리스 태그에서 앞의 v를 뗀 것이고,
/// 글은 릴리스 노트의 사용자 언어 줄(없으면 영어 절)이다.
public struct ImportantOffer: Equatable, Sendable {
    public let version: String
    public let text: String

    public init(version: String, text: String) {
        self.version = version
        self.text = text
    }
}
