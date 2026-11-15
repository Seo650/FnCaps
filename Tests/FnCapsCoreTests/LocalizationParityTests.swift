import Foundation
import Testing

/// 모든 언어의 문구 파일이 키와 형식 지정자까지 맞는지 고정한다.
/// L()은 키가 없으면 키 문자열을 그대로 보이므로 빠진 번역을 눈에만 맡기지 않는다.
/// 언어 목록은 저장소 `Resources`의 `*.lproj` 폴더에서 직접 찾는다. 새 언어 폴더를 만들면
/// 키 일치·형식 지정자·삭제 키 검사가 그 언어에 자동으로 걸린다.
@Suite struct LocalizationParityTests {
    /// 번역이 들어오기 전에 문체 검사를 따로 거는 새 언어. 폴더가 없는 언어는 건너뛴다.
    /// 10개 언어가 모두 갖춰졌는지는 AppLanguageTests가 본다.
    static let newLangs = ["zh-Hans", "zh-Hant", "uk", "ru", "fr", "es", "de"]

    /// 저장소 뿌리. `Tests/FnCapsCoreTests/<이 파일>`에서 세 단계 위다.
    static var root: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    /// `Resources` 안에서 `Localizable.strings`를 가진 `*.lproj` 폴더 이름을 정렬해 돌려준다.
    static var langs: [String] {
        let dir = root.appendingPathComponent("Resources")
        let entries = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        return entries
            .filter { $0.pathExtension == "lproj" }
            .filter { FileManager.default.fileExists(atPath: $0.appendingPathComponent("Localizable.strings").path) }
            .map { $0.deletingPathExtension().lastPathComponent }
            .sorted()
    }

    static func load(_ lang: String) throws -> [String: String] {
        let url = root.appendingPathComponent("Resources/\(lang).lproj/Localizable.strings")
        guard let dict = NSDictionary(contentsOf: url) as? [String: String] else {
            throw LoadError.unreadable(url.path)
        }
        return dict
    }

    enum LoadError: Error { case unreadable(String) }

    static func all() throws -> [String: [String: String]] {
        var r: [String: [String: String]] = [:]
        for l in langs { r[l] = try load(l) }
        return r
    }

    static let deletedKeys = [
        // 2026-11-13: 「다른 언어 수」 접힘과 「모든 언어 최대 N번」 줄을 없앴다.
        "help.setup.others", "help.setup.count", "help.setup.recommended", "help.setup.max",
        "keys.caps.shortcutNote",
        "window.capsSource", "window.capsSource.label", "window.capsSource.default",
        "window.capsSource.help", "window.capsSource.shortcutNote", "window.capsSource.blocked",
        "window.capsSource.missing", "window.capsSource.missingNoBase",
        "window.capsLong", "window.capsLongHelp", "window.capsLongLayoutsOnly",
        "window.capsLongLayoutsOnlyHelp", "window.cycleOrder", "window.cycleOrderHelp",
        "window.holdSettle", "window.holdSettleHelp",
        // 2026-11-11: 앱별 대기 시간 삭제(앱별 설정은 「FnCaps 끄기」 목록). menu.hideIcon은 메뉴에 다시 넣었다.
        "apps.mode.off", "apps.time.a11y",
        // 04-18: 재설계로 쓰지 않게 된 키
        "sidebar.longPress", "window.longPressHelp", "settings.group.run", "settings.enable.info",
        "settings.group.permission", "settings.permission.info", "settings.group.recover",
        "settings.restore.info", "settings.group.capsLong", "settings.group.fnLong",
        "keys.intro", "keys.caps.info", "keys.fn.info", "keys.caps.defaultNote", "keys.disabledTag",
        "keys.move.a11y", "keys.moveUp.a11y", "keys.moveDown.a11y", "keys.unassigned.title",
        "keys.unassigned.note", "keys.outside.title", "keys.outside.picker", "keys.outside.info",
        "keys.outside.example", "keys.full", "longpress.enable.info", "longpress.off.note",
        "longpress.time.caption", "longpress.time.info", "longpress.time.reset",
        "longpress.layouts.title", "longpress.layouts.caption", "longpress.layouts.info",
        "advanced.settle.group", "advanced.settle.reset", "about.version", "about.license",
        "about.support.group", "about.support.body", "about.support.button",
        "about.recover.step1", "about.recover.step2", "about.recover.step3", "about.recover.command",
        "menu.capsBlocked", "permission.body",
        // 04.2-06: 「설정 팁」 → 「도움말」. tips.*를 help.*로 바꾸고 옛 키를 모두 지웠다.
        "sidebar.tips",
        "tips.group", "tips.intro", "tips.example.setup", "tips.example.from",
        "tips.lang.en", "tips.lang.ko", "tips.lang.ja", "tips.lang.zh",
        "tips.col.langs", "tips.col.split", "tips.col.presses",
        "tips.row3.count", "tips.row3.sample", "tips.row3.split", "tips.row3.presses",
        "tips.row4.count", "tips.row4.sample", "tips.row4.split", "tips.row4.presses",
        "tips.row5.count", "tips.row5.split", "tips.row5.presses",
        "tips.note.shortcut", "tips.note.rule",
        "tips.dup.group", "tips.dup.intro", "tips.dup.hub.title", "tips.dup.hub.caption",
        "tips.dup.home.title", "tips.dup.home.caption", "tips.dup.note",
        // 04.2-09 D-05·D-07·D-10: 「키가 이상할 때」 묶음을 정보 쪽에서 지우고 메뉴로 옮겼다. 복구 절차는 README로.
        "about.recover.group", "about.recover.copy", "about.recover.copied",
        "about.trouble.step1", "about.trouble.openGeneral",
        "about.trouble.step2", "about.trouble.step2.detail",
        "about.trouble.step3", "about.trouble.step3.path",
        "about.trouble.step4", "about.trouble.step4.detail",
        "about.diagnostics.copy",
        // 04.2-07 D-36·D-37: 한 행에는 줄 설명과 ⓘ 중 하나만. outside는 줄 설명, settle은 ⓘ만 남겼다.
        "advanced.outside.info", "advanced.settle.caption",
        // 04.2-13 도움말 개편(D-46, D-52): 「지금 내 배치」 비교와 겹침 예시 두 갈래를 지웠다.
        "help.setup.current",
        // 04.4 UAT U-4: 「같은 언어를 여러 키에 두기」 묶음 삭제, 개요 줄을 모양별 키로 교체.
        "help.dup.title", "help.dup.intro", "help.dup.caps.title", "help.dup.caps.caption",
        "help.cand.why.zero", "help.cand.why.some",
        "setup.welcome.segment.fncaps",  // 04.4 UAT U-11: 1단계는 환영 인사만
        "help.dup.hub.title", "help.dup.hub.caption",
        "help.dup.home.title", "help.dup.home.caption",
        // 2026-11-13: 「언어를 나누는 방법」 묶음을 지웠다.
        "help.split.title", "help.split.intro",
        // 2026-11-13 (04.3 D-02): 전역 「fn과 Caps를 오갈 때」를 키별 진입 언어로 옮겼다.
        "advanced.outside.title", "advanced.outside.caption",
        // 2026-11-13 04.4 D-21: 진입 언어 설명 줄을 ⓘ로 바꿈.
        "keys.entry.caption",
        // 2026-11-13 04.4 D-08·D-12: 권장 그림 말과 같음/다름 줄을 후보 목록으로 바꿈.
        "help.setup.same", "help.setup.different",
        "help.setup.step.caps", "help.setup.step.fn.one",
        "help.setup.step.fn.many", "help.setup.step.assigned",
        // 2026-11-14 (04.5-06 사용자 결정): 4단계는 도움말 macOS 기본 조각만 둔다. 「FnCaps」 묶음과 「macOS 기본」 행을 지웠다.
        "setup.why.globe", "setup.why.caps", "setup.fn.row", "setup.caps.row",
        // 같은 날: 4단계 머리 보조 줄이 FnCaps 설명이라 지웠다(제목이 macOS 기본 전환임을 밝힌다).
        "setup.why.app",
    ]

    /// Sources 아래 모든 .swift 파일을 하나로 합친 글.
    static func allSourceText() throws -> String {
        let src = root.appendingPathComponent("Sources")
        guard let files = FileManager.default.enumerator(at: src, includingPropertiesForKeys: nil) else {
            throw LoadError.unreadable(src.path)
        }
        var text = ""
        for case let url as URL in files where url.pathExtension == "swift" {
            text += try String(contentsOf: url, encoding: .utf8)
            text += "\n"
        }
        return text
    }

    @Test func keysMatch() throws {
        let all = try Self.all()
        #expect(Self.langs.contains("en"), "Resources에 en.lproj가 없습니다")
        let en = try #require(all["en"])
        let base = Set(en.keys)
        for l in Self.langs {
            let keys = Set(all[l]!.keys)
            #expect(keys.subtracting(base).isEmpty, "[\(l)]에만 있는 키: \(keys.subtracting(base).sorted())")
            #expect(base.subtracting(keys).isEmpty, "[\(l)]에 빠진 키: \(base.subtracting(keys).sorted())")
        }
    }

    @Test func specifiersMatch() throws {
        let all = try Self.all()
        let en = try #require(all["en"])
        let regex = try NSRegularExpression(pattern: "%(\\d+\\$)?(@|ld|lu|d|f)")
        func specs(_ s: String) -> [String] {
            let ns = s as NSString
            return regex.matches(in: s, range: NSRange(location: 0, length: ns.length))
                .map { ns.substring(with: $0.range) }.sorted()
        }
        for (key, enValue) in en {
            let expected = specs(enValue)
            for l in Self.langs where l != "en" {
                guard let v = all[l]?[key] else { continue }
                #expect(specs(v) == expected, "\(key) [\(l)] 지정자 \(specs(v)) != \(expected)")
            }
        }
    }

    @Test func deletedKeysAbsent() throws {
        let all = try Self.all()
        for l in Self.langs {
            for k in Self.deletedKeys {
                #expect(all[l]![k] == nil, "[\(l)]에 삭제 키가 남음: \(k)")
            }
        }
    }

    @Test func forbiddenWordsAbsent() throws {
        let all = try Self.all()
        let ko = ["표시등", "불빛", "두 번", "더블"]
        let ja = ["ランプ", "インジケータ", "ダブル", "2回"]
        // D-12 4번: 「표시등」은 사용자가 요청한 문구다. 표시등을 고치면 키와 면제를 함께 지운다.
        let capsLight = "help.notes.capsLight"
        // 04.4 UAT U-1(2026-11-14 사용자): 후보 상자별 말은 「탭 / 더블탭」으로 쓴다.
        // 「더블탭 정도는 누구나 아는 표현이라고 치자」. 「더블」·「ダブル」·「double」만 이 두 키에서 푼다.
        let doubleTapKeys: Set<String> = [
            "help.cand.press.two", "help.cand.caps.back", "help.cand.why.cycles"]
        for (k, v) in all["ko"]! where k != capsLight {
            for w in ko where !(w == "더블" && doubleTapKeys.contains(k)) {
                #expect(!v.contains(w), "ko \(k): \(w)")
            }
        }
        for (k, v) in all["ja"]! where k != capsLight {
            for w in ja where !(w == "ダブル" && doubleTapKeys.contains(k)) {
                #expect(!v.contains(w), "ja \(k): \(w)")
            }
        }
        for (k, v) in all["en"]! where k != capsLight {
            #expect(v.range(of: "\\bLED\\b", options: .regularExpression) == nil, "en \(k): LED")
            #expect(v.range(of: "indicator light", options: .caseInsensitive) == nil, "en \(k): indicator light")
            if !doubleTapKeys.contains(k) {
                #expect(v.range(of: "double", options: .caseInsensitive) == nil, "en \(k): double")
            }
        }
    }

    @Test func koParticles() throws {
        let ko = try Self.load("ko")
        for (k, v) in ko {
            for w in ["FnCaps을", "FnCaps이", "FnCaps은", "FnCaps과"] {
                #expect(!v.contains(w), "ko \(k): \(w)")
            }
        }
    }

    /// 코드가 L()/LF()로 직접 쓰는 키가 모두 en 문구 파일에 있어야 한다.
    /// 변수로 넘기는 키는 정규식에 잡히지 않으므로 목록으로 따로 확인한다.
    @Test func codeKeysExistInEnglish() throws {
        let en = try Self.load("en")
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let src = root.appendingPathComponent("Sources/FnCaps")
        let regex = try NSRegularExpression(pattern: "\\bLF?\\(\\s*\"([a-zA-Z0-9_.]+)\"")
        let literal = try NSRegularExpression(pattern: "\\?\\s*\"([a-zA-Z0-9_.]+)\"\\s*:\\s*\"([a-zA-Z0-9_.]+)\"")
        var used: [String: String] = [:]
        let files = try #require(FileManager.default.enumerator(at: src, includingPropertiesForKeys: nil))
        for case let url as URL in files where url.pathExtension == "swift" {
            let text = try String(contentsOf: url, encoding: .utf8)
            let ns = text as NSString
            let full = NSRange(location: 0, length: ns.length)
            for m in regex.matches(in: text, range: full) {
                used[ns.substring(with: m.range(at: 1))] = url.lastPathComponent
            }
            // L(cond ? "a" : "b") 형태의 삼항 키
            for m in literal.matches(in: text, range: full) {
                for i in 1...2 {
                    let k = ns.substring(with: m.range(at: i))
                    if k.contains(".") { used[k] = url.lastPathComponent }
                }
            }
        }
        let dynamic = [
            "sidebar.general", "sidebar.keys", "sidebar.advanced", "sidebar.about", "sidebar.help",
            "sidebar.report",
            "status.running", "status.permission", "status.waiting", "status.off",
            "permission.path.legacy", "permission.path.27", "menu.turnOn", "menu.turnOff",
        ]
        for k in dynamic { used[k] = used[k] ?? "동적 목록" }
        #expect(used.count > 20)
        for (k, file) in used.sorted(by: { $0.key < $1.key }) {
            #expect(en[k] != nil, "en에 없는 키: \(k) (\(file))")
        }
    }

    @Test func requiredKeysPresent() throws {
        let en = try Self.load("en")
        for k in ["sidebar.general", "keys.caps.empty", "keys.fn.empty", "menu.newSources.one",
                  "advanced.long.enable.caption", "advanced.settle.title", "about.bmc.button",
                  "status.waiting", "memo.placeholder", "keys.addSource", "keys.unused.title",
                  "about.update.title", "report.send", "general.conflict.warning",
                  "general.language.title", "advanced.reset.all.button", "advanced.reset.all.confirm",
                  "apps.caption", "menu.hideIcon", "login.notFound"] {
            #expect(en[k] != nil, "en에 없음: \(k)")
        }
    }

    /// 문구 파일의 모든 키가 코드 어딘가에 따옴표째 나온다. 안 쓰는 키가 쌓이지 않게 한다.
    /// 코드가 문자열을 조합해 만드는 키만 예외에 넣고, 키마다 이유를 적는다.
    static let unreferencedAllowed: [String] = []

    @Test func everyKeyIsReferenced() throws {
        let en = try Self.load("en")
        let text = try Self.allSourceText()
        for k in en.keys.sorted() where !Self.unreferencedAllowed.contains(k) {
            let found = text.contains("\"\(k)\"")
            #expect(found, "코드에서 쓰지 않는 키: \(k)")
        }
    }

    /// 권유 말투를 막는다(FINAL-REVIEW §3-2). 화면 문구는 사실을 적는다.
    /// en 예외: login.failed의 "try again"은 오류 뒤 다시 하라는 안내라 권유가 아니다(ko 값과 함께 사용자 검토 목록에 올림).
    static let coachingAllowedEn = ["login.failed"]

    @Test func noCoachingTone() throws {
        let all = try Self.all()
        for (k, v) in all["ko"]! {
            for w in ["해 보세요", "해보세요", "써 보기", "하세요", "두세요"] {
                #expect(!v.contains(w), "ko \(k): \(w)")
            }
        }
        for (k, v) in all["en"]! where !Self.coachingAllowedEn.contains(k) {
            #expect(!v.hasPrefix("Try "), "en \(k): Try")
            #expect(!v.contains(" try "), "en \(k): try")
        }
    }

    /// 화면 문구에는 macOS와 같은 「입력 소스」만 쓰고 내부 말은 쓰지 않는다.
    /// 예외: about.recover.command는 터미널 명령 원문이다(04-18에 키를 지우고 ExternalLinks.recoverCommand로 옮겼지만 다시 생겨도 예외).
    @Test func screenTermsUnified() throws {
        let ko = try Self.load("ko")
        for (k, v) in ko where k != "about.recover.command" {
            for w in ["입력기", "매핑", "펄스"] {
                #expect(!v.contains(w), "ko \(k): \(w)")
            }
        }
    }

    // MARK: - 새 7개 언어

    /// 언어별 문구 파일의 허용 목록 한 줄.
    struct AllowEntry {
        let key: String
        let reason: String
        let line: Int
    }

    /// `Tests/LocalizationAllowlists/same-as-english-<lang>.txt`를 읽는다.
    /// 형식: 한 줄에 `<key> = <이유>`, `#`로 시작하는 줄은 주석. 파일이 없으면 빈 목록.
    static func allowlist(_ lang: String) throws -> [AllowEntry] {
        let url = root.appendingPathComponent("Tests/LocalizationAllowlists/same-as-english-\(lang).txt")
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let text = try String(contentsOf: url, encoding: .utf8)
        var out: [AllowEntry] = []
        for (i, raw) in text.components(separatedBy: "\n").enumerated() {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            let parts = line.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            let key = parts[0].trimmingCharacters(in: .whitespaces)
            let reason = parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespaces) : ""
            out.append(AllowEntry(key: key, reason: reason, line: i + 1))
        }
        return out
    }

    /// 허용 이유는 세 가지뿐이다: `brand`, `symbol`, `cognate: <그 언어에서 맞는 표기인 근거>`.
    static func isValidAllowReason(_ r: String) -> Bool {
        if r == "brand" || r == "symbol" { return true }
        let prefix = "cognate:"
        guard r.hasPrefix(prefix) else { return false }
        return !r.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// ko와 ja 값이 둘 다 영어 값과 같은 키. 브랜드·기호·`%d ms`처럼 언어 중립인 값이다.
    static func neutralKeys(en: [String: String], all: [String: [String: String]]) -> Set<String> {
        guard let ko = all["ko"], let ja = all["ja"] else { return [] }
        return Set(en.keys.filter { ko[$0] == en[$0] && ja[$0] == en[$0] })
    }

    /// 번역 누락 검사. 새 언어 값이 영어 값과 똑같이 남아 있으면 실패한다.
    /// 허용: ko·ja도 영어와 같은 언어 중립 값, 그리고 언어별 허용 목록에 적힌 키.
    @Test func untranslatedValuesAbsent() throws {
        let all = try Self.all()
        let en = try #require(all["en"])
        let neutral = Self.neutralKeys(en: en, all: all)
        for l in Self.newLangs {
            guard let values = all[l] else { continue }
            var allowed: Set<String> = []
            for e in try Self.allowlist(l) {
                #expect(!e.reason.isEmpty, "[\(l)] same-as-english-\(l).txt \(e.line)행: 이유가 비어 있음")
                #expect(Self.isValidAllowReason(e.reason),
                        "[\(l)] \(e.key): 이유는 brand / symbol / cognate: <근거> 중 하나여야 함 — \(e.reason)")
                #expect(en[e.key] != nil, "[\(l)] 허용 목록 \(e.line)행에 en에 없는 키: \(e.key)")
                #expect(values[e.key] == en[e.key],
                        "[\(l)] 낡은 허용 항목 \(e.line)행: \(e.key) 값이 영어와 다름")
                allowed.insert(e.key)
            }
            let missing = values.keys.sorted().filter { k in
                values[k] == en[k] && !neutral.contains(k) && !allowed.contains(k)
            }
            #expect(missing.isEmpty, "[\(l)] 번역 누락(영어 그대로): \(missing)")
        }
    }

    /// 폴더 자동 발견은 빠진 폴더를 조용히 건너뛴다. 기대하는 언어가 모두 있는지 따로 본다
    /// (폴더 누락·이름 오타 `zh_Hans.lproj` 등을 잡는다).
    @Test func expectedLangsPresent() {
        let expected = Set(Self.newLangs + ["en", "ko", "ja"])
        let found = Set(Self.langs)
        #expect(found.isSuperset(of: expected), "빠진 lproj: \(expected.subtracting(found).sorted())")
    }

    /// 새 언어의 권유 말투 금지(RESEARCH §문구 길이·문체 규칙). 사실 서술과 짧은 명사구를 쓴다.
    static let coachingWords: [String: [String]] = [
        "ru": ["Попробуйте"],
        "uk": ["Спробуйте"],
        "fr": ["Essayez"],
        "es": ["Pruebe", "Intente"],
        "de": ["Versuchen Sie", "Probieren Sie"],
        "zh-Hans": ["请尝试", "试试"],
        "zh-Hant": ["請嘗試", "試試"],
    ]

    @Test func noCoachingToneNewLangs() throws {
        let all = try Self.all()
        for l in Self.newLangs {
            guard let values = all[l] else { continue }
            let words = Self.coachingWords[l] ?? []
            for (k, v) in values where !Self.coachingAllowedEn.contains(k) {
                for w in words {
                    #expect(v.range(of: w, options: .caseInsensitive) == nil, "[\(l)] \(k): 권유 말투 \(w)")
                }
            }
        }
    }

    /// 간체·번체를 변환기로 만들지 않는다(D-09). 서로의 용어가 섞이면 실패한다.
    @Test func chineseScriptsNotMixed() throws {
        let all = try Self.all()
        let simplifiedOnly = ["输入法", "设置", "键盘", "菜单"]
        let traditionalOnly = ["輸入方式", "設定", "鍵盤", "選單"]
        for (k, v) in all["zh-Hant"] ?? [:] {
            for w in simplifiedOnly {
                #expect(!v.contains(w), "[zh-Hant] \(k): 간체 용어 \(w)")
            }
        }
        for (k, v) in all["zh-Hans"] ?? [:] {
            for w in traditionalOnly {
                #expect(!v.contains(w), "[zh-Hans] \(k): 번체 용어 \(w)")
            }
        }
    }

    /// ru·uk는 숫자 뒤 명사의 복수형이 세 가지라 `.strings`만으로 맞출 수 없다(Pitfall 4).
    /// 숫자와 명사가 붙는 문구는 「명사: %d」 꼴로 두어 `%d`로 끝나게 한다.
    static let numberLastKeys = [
        "menu.newSources.many", "menu.newSources.outside", "longpress.time.a11y",
    ]

    @Test func cyrillicNumberLast() throws {
        let all = try Self.all()
        let en = try #require(all["en"])
        for k in Self.numberLastKeys {
            #expect(en[k]?.hasSuffix("%d") == true, "en \(k): %d로 끝나야 함")
        }
        for l in ["ru", "uk"] {
            guard let values = all[l] else { continue }
            for k in Self.numberLastKeys {
                #expect(values[k]?.hasSuffix("%d") == true, "[\(l)] \(k): %d로 끝나야 함")
            }
        }
    }
}
