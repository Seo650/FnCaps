import Foundation

/// 진단 정보에 넣을 입력 소스 한 줄.
public struct DiagnosticsSource: Equatable, Sendable {
    public let id: String
    public let name: String
    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

/// 진단 정보 재료. D-32(2026-11-12): 번들 ID 목록과 지정 조합을 넣는다(T-04-56·T-04-64 대체).
/// 사용자는 보내기 전 미리보기로 전부 본다. 입력 글자·일련번호·메모·메일은 받지 않는다.
public struct DiagnosticsInput: Equatable, Sendable {
    public var appVersion: String
    public var build: String
    public var osVersion: String
    public var strategy: String
    public var status: String
    public var sources: [DiagnosticsSource]
    public var caps: [String]
    public var fn: [String]
    public var notUsed: [String]
    /// 지정 소스 ID. 실제 조합 값은 assignedChords에 따로 적는다(T-04-64 대체).
    public var assigned: [String]
    public var settings: [String: String]
    public var logLines: [String]
    /// 지정 단축키 조합 한 줄에 하나: 「소스ID 표시글자 (keyCode N mods M)」.
    public var assignedChords: [String]
    /// 앱별 끄기 목록(번들 ID).
    public var appsOff: [String]
    /// 앱별 첫 글자 보호 목록: 「번들ID ms」.
    public var appsSettle: [String]
    public var loginItem: String
    public var appLanguage: String
    public var systemLanguage: String
    /// 「🌐 키를 누르면」 값.
    public var globeUsage: String
    /// #60 「이전 입력 소스 선택」 단축키 상태.
    public var hotkey60: String
    /// 현재 UserKeyMapping: 「src->dst」.
    public var userKeyMapping: [String]
    public var accessibility: String
    public var macModel: String
    /// 내장·외장 키보드: 「연결 방식 배열 이름」.
    public var keyboards: [String]

    public init(
        appVersion: String, build: String, osVersion: String, strategy: String, status: String,
        sources: [DiagnosticsSource], caps: [String], fn: [String], notUsed: [String],
        assigned: [String] = [], settings: [String: String], logLines: [String],
        assignedChords: [String] = [], appsOff: [String] = [], appsSettle: [String] = [],
        loginItem: String = "-", appLanguage: String = "-", systemLanguage: String = "-",
        globeUsage: String = "-", hotkey60: String = "-", userKeyMapping: [String] = [],
        accessibility: String = "-", macModel: String = "-", keyboards: [String] = []
    ) {
        self.appVersion = appVersion
        self.build = build
        self.osVersion = osVersion
        self.strategy = strategy
        self.status = status
        self.sources = sources
        self.caps = caps
        self.fn = fn
        self.notUsed = notUsed
        self.assigned = assigned
        self.settings = settings
        self.logLines = logLines
        self.assignedChords = assignedChords
        self.appsOff = appsOff
        self.appsSettle = appsSettle
        self.loginItem = loginItem
        self.appLanguage = appLanguage
        self.systemLanguage = systemLanguage
        self.globeUsage = globeUsage
        self.hotkey60 = hotkey60
        self.userKeyMapping = userKeyMapping
        self.accessibility = accessibility
        self.macModel = macModel
        self.keyboards = keyboards
    }
}

/// 진단 정보 본문(FINAL-REVIEW §3-1 F). 개발자용 영어 고정 형식이며 번역하지 않는다.
public enum DiagnosticsReport {
    /// 진단 본문 전체 상한(UTF-16 단위). Worker MAX_DIAGNOSTICS 55,000보다 여유를 둔다(T-04.2-11).
    public static let maxUnits = 50_000

    /// 전환·상태 기록 로그 머리말만 허용한다. 실제 AppLog.info 문자열에서 골랐다.
    public static let allowedPrefixes: [String] = [
        "fn decision", "fn step", "fn passThrough", "fn release", "fn enabled", "fn preview", "fnpass",
        "caps ", "lists set", "keyLists saved", "keyLists corrupt", "sources fresh",
        "source select failed", "source rejected", "status=", "tap ", "permission ",
        "settle app", "app off", "app language set", "settings reset", "hold released",
        "start ", "screen locked", "resume ", "recovery ", "rebuild ", "watchdog ",
        "globe usage", "S10-RealGlobe", "shortcut ",
    ]

    /// 허용 머리말 줄이어도 이 낱말이 있으면 버린다(키코드·문자·입력 내용·메모).
    static let blockedWords = ["keyCode", "char", "text=", "memo"]

    /// 허용 머리말 줄만 남기고 app=·front= 값(앱 번들 ID)을 가린다. limit개를 넘으면 마지막 limit개.
    /// 줄 앞의 `HH:mm:ss.SSS ` 시각(AppLog.recentLines 형식)은 머리말 검사에서 빼고 그대로 둔다.
    public static func safeLogLines(_ lines: [String], limit: Int = 120) -> [String] {
        let kept = lines.compactMap { line -> String? in
            let (stamp, body) = splitStamp(line)
            guard allowedPrefixes.contains(where: { body.hasPrefix($0) }),
                  !blockedWords.contains(where: { line.contains($0) }) else { return nil }
            return stamp + masked(body)
        }
        return Array(kept.suffix(max(limit, 0)))
    }

    /// "12:34:56.789 rest" → ("12:34:56.789 ", "rest"). 형식이 아니면 ("", line).
    static func splitStamp(_ line: String) -> (String, String) {
        let chars = Array(line.utf8)
        guard chars.count > 13 else { return ("", line) }
        let digitAt: Set<Int> = [0, 1, 3, 4, 6, 7, 9, 10, 11]
        for i in 0..<12 {
            let c = chars[i]
            if digitAt.contains(i) { guard c >= 48 && c <= 57 else { return ("", line) } }
            else if i == 8 { guard c == 46 else { return ("", line) } }
            else { guard c == 58 else { return ("", line) } }
        }
        guard chars[12] == 32 else { return ("", line) }
        return (String(line.prefix(13)), String(line.dropFirst(13)))
    }

    static func masked(_ line: String) -> String {
        line.split(separator: " ", omittingEmptySubsequences: false).map { word -> String in
            for key in ["app=", "front="] where word.hasPrefix(key) { return key + "<app>" }
            return String(word)
        }.joined(separator: " ")
    }

    public static func text(_ input: DiagnosticsInput) -> String {
        var logs = safeLogLines(input.logLines)
        var text = assemble(input, logs)
        // 본문 상한(T-04.2-11). 넘으면 오래된 로그 줄부터 뺀다. 로그 외 부분은 줄이지 않는다.
        while text.utf16.count > maxUnits, !logs.isEmpty {
            logs.removeFirst()
            text = assemble(input, logs)
        }
        return text
    }

    static func assemble(_ input: DiagnosticsInput, _ logs: [String]) -> String {
        var out: [String] = []
        out.append("FnCaps \(input.appVersion) (\(input.build))")
        out.append("macOS \(input.osVersion)")
        out.append("strategy \(input.strategy)")
        out.append("status \(input.status)")
        out.append("sources")
        out += input.sources.map { "  \($0.id) \($0.name)" }
        out.append("caps \(input.caps.joined(separator: " "))")
        out.append("fn \(input.fn.joined(separator: " "))")
        out.append("assigned \(input.assigned.joined(separator: " "))")
        out.append("notUsed \(input.notUsed.joined(separator: " "))")
        out.append("assignedChords")
        out += input.assignedChords.map { "  \($0)" }
        out.append("appsOff")
        out += input.appsOff.map { "  \($0)" }
        out.append("appsSettle")
        out += input.appsSettle.map { "  \($0)" }
        out.append("loginItem \(input.loginItem)")
        out.append("appLanguage \(input.appLanguage)")
        out.append("systemLanguage \(input.systemLanguage)")
        out.append("globeUsage \(input.globeUsage)")
        out.append("hotkey60 \(input.hotkey60)")
        out.append("userKeyMapping")
        out += input.userKeyMapping.map { "  \($0)" }
        out.append("accessibility \(input.accessibility)")
        out.append("macModel \(input.macModel)")
        out.append("keyboards")
        out += input.keyboards.map { "  \($0)" }
        out.append("settings")
        out += input.settings.keys.sorted().map { "  \($0)=\(input.settings[$0] ?? "")" }
        out.append("recent")
        out += logs.map { "  \($0)" }
        return out.joined(separator: "\n")
    }
}
