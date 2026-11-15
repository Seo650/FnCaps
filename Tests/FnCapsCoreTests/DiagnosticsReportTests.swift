import Testing
@testable import FnCapsCore

/// 진단 정보(FINAL-REVIEW §3-1 F). 허용 머리말 로그 줄만, 로그의 app= 가림(T-04-56 → D-32가 대체).
@Suite struct DiagnosticsReportTests {
    private func input(logLines: [String] = []) -> DiagnosticsInput {
        DiagnosticsInput(
            appVersion: "1.0", build: "7", osVersion: "Version 27.2 (Build 27C1)", strategy: "shortcut",
            status: "active",
            sources: [DiagnosticsSource(id: "com.apple.keylayout.ABC", name: "ABC"),
                      DiagnosticsSource(id: "com.apple.inputmethod.Korean.2SetKorean", name: "2-Set Korean")],
            caps: ["com.apple.keylayout.ABC"], fn: ["com.apple.inputmethod.Korean.2SetKorean"], notUsed: ["x.y"],
            settings: ["b": "2", "a": "1"], logLines: logLines)
    }

    @Test func keepsAllowedPrefixOnly() {
        let out = DiagnosticsReport.safeLogLines(["fn decision=switchTo(abc)", "something else", "caps long fired from=x"])
        #expect(out == ["fn decision=switchTo(abc)", "caps long fired from=x"])
    }

    @Test func dropsSensitiveWordsEvenWithAllowedPrefix() {
        let out = DiagnosticsReport.safeLogLines([
            "fn decision keyCode=12", "caps char=a", "status= text=hello", "lists set memo=x", "tap installed",
        ])
        #expect(out == ["tap installed"])
    }

    @Test func masksBundleIDs() {
        #expect(DiagnosticsReport.safeLogLines(["settle app=com.apple.TextEdit ms=120"]) == ["settle app=<app> ms=120"])
        #expect(DiagnosticsReport.safeLogLines(["app off on=true front=com.foo.Bar"]) == ["app off on=true front=<app>"])
    }

    @Test func keepsLastLimitLines() {
        let lines = (0..<130).map { "tap installed \($0)" }
        let out = DiagnosticsReport.safeLogLines(lines)
        #expect(out.count == 120)
        #expect(out.first == "tap installed 10")
        #expect(DiagnosticsReport.safeLogLines(lines, limit: 3) == ["tap installed 127", "tap installed 128", "tap installed 129"])
    }

    @Test func keepsRealGlobeResultAndDropsWindowSync() {
        let result = "S10-RealGlobe -> com.apple.keylayout.ABC landed=true ms=161.0 path=fallback plan=hop trigger=release status=0/0 delay=30.0ms"
        #expect(DiagnosticsReport.safeLogLines([result, "window sync status=active"]) == [result])
        #expect(DiagnosticsReport.safeLogLines(["S10-RealGlobe -> x keyCode=1"]).isEmpty)
    }

    @Test func textNeverContainsLoggedBundleID() {
        let text = DiagnosticsReport.text(input(logLines: ["settle app=com.apple.TextEdit ms=120"]))
        #expect(!text.contains("com.apple.TextEdit"))
        #expect(text.contains("settle app=<app> ms=120"))
    }

    @Test func textLayout() {
        let lines = DiagnosticsReport.text(input(logLines: ["tap installed"])).components(separatedBy: "\n")
        #expect(lines.first == "FnCaps 1.0 (7)")
        #expect(lines.dropFirst().first == "macOS Version 27.2 (Build 27C1)")
        let joined = lines.joined(separator: "\n")
        for head in ["strategy shortcut", "status active", "sources", "caps", "fn", "notUsed x.y", "settings", "recent"] {
            #expect(lines.contains(where: { $0.hasPrefix(head) }), "\(head)")
        }
        #expect(joined.contains("com.apple.keylayout.ABC ABC"))
        #expect(joined.contains("a=1"))
        #expect(joined.range(of: "a=1")!.lowerBound < joined.range(of: "b=2")!.lowerBound)
        #expect(lines.last == "  tap installed")
    }

    @Test func timestampedLinesFromAppLog() {
        let out = DiagnosticsReport.safeLogLines([
            "12:34:56.789 settle app=com.apple.TextEdit ms=120", "12:34:56.790 typed text=hi", "12:34:56.791 other",
        ])
        #expect(out == ["12:34:56.789 settle app=<app> ms=120"])
    }

    @Test func textIsDeterministic() {
        #expect(DiagnosticsReport.text(input(logLines: ["tap installed"])) == DiagnosticsReport.text(input(logLines: ["tap installed"])))
    }

    @Test func recentNeverHasRejectedLines() {
        let text = DiagnosticsReport.text(input(logLines: ["typed text=hello", "fn decision text=hello", "tap installed"]))
        #expect(!text.contains("hello"))
        #expect(!text.contains("typed"))
    }
}

@Suite struct DiagnosticsAssignedTests {
    private func input(assigned: [String] = [], logLines: [String] = []) -> DiagnosticsInput {
        DiagnosticsInput(
            appVersion: "1.0", build: "7", osVersion: "27.2", strategy: "shortcut", status: "active",
            sources: [], caps: ["a"], fn: [], notUsed: [],
            assigned: assigned,
            settings: ["assignedShortcuts": "2"], logLines: logLines)
    }

    @Test func assignedLineBeforeNotUsed() {
        let lines = DiagnosticsReport.text(input(assigned: ["r.y", "v.z"])).components(separatedBy: "\n")
        #expect(lines.contains("assigned r.y v.z"))
        let joined = lines.joined(separator: "\n")
        #expect(joined.range(of: "assigned r.y v.z")!.lowerBound < joined.range(of: "notUsed")!.lowerBound)
    }

    @Test func settingsStillShowAssignedCount() {
        #expect(DiagnosticsReport.text(input()).contains("assignedShortcuts=2"))
    }

    @Test func shortcutLogLinesAllowedWithoutChordValues() {
        let out = DiagnosticsReport.safeLogLines(["shortcut target=r.y", "shortcut recording", "shortcut keyCode=38"])
        #expect(out == ["shortcut target=r.y", "shortcut recording"])
    }
}

/// D-32 추가분(2026-11-12). 번들 ID 목록·지정 조합을 넣는다(T-04-56·T-04-64 대체).
@Suite struct DiagnosticsD32Tests {
    private let chord = "ko.2set ⌥1 (keyCode 18 mods 524288)"

    private func full(logLines: [String] = []) -> DiagnosticsInput {
        DiagnosticsInput(
            appVersion: "1.0", build: "7", osVersion: "27.2", strategy: "shortcut", status: "active",
            sources: [], caps: ["a"], fn: [], notUsed: ["x.y"], assigned: ["r.y"],
            settings: ["assignedShortcuts": "1"], logLines: logLines,
            assignedChords: [chord],
            appsOff: ["com.apple.finder"],
            appsSettle: ["com.apple.TextEdit 120"],
            loginItem: "on",
            appLanguage: "ko",
            systemLanguage: "ko-KR",
            globeUsage: "showInputMenu",
            hotkey60: "enabled",
            userKeyMapping: ["0x700000039->0x70000006D"],
            accessibility: "trusted",
            macModel: "MacBookAir17,1",
            keyboards: ["built-in ANSI Korean"])
    }

    private let heads = ["assignedChords", "appsOff", "appsSettle", "loginItem", "appLanguage",
                         "systemLanguage", "globeUsage", "hotkey60", "userKeyMapping",
                         "accessibility", "macModel", "keyboards"]

    private func index(of head: String, in lines: [String]) -> Int? {
        lines.firstIndex { $0 == head || $0.hasPrefix(head + " ") }
    }

    @Test func d32SectionsAppearInOrderBetweenNotUsedAndSettings() {
        let lines = DiagnosticsReport.text(full()).components(separatedBy: "\n")
        var last = index(of: "notUsed", in: lines) ?? -1
        #expect(last >= 0)
        for head in heads {
            guard let i = index(of: head, in: lines) else {
                Issue.record("\(head) 줄이 없다")
                return
            }
            #expect(i > last, "\(head) 순서")
            last = i
        }
        let settings = index(of: "settings", in: lines) ?? -1
        #expect(settings > last)
    }

    @Test func d32ValuesAreWritten() {
        let lines = DiagnosticsReport.text(full()).components(separatedBy: "\n")
        let joined = lines.joined(separator: "\n")
        #expect(lines.contains("  \(chord)"))
        #expect(lines.contains("  com.apple.finder"))
        #expect(lines.contains("  com.apple.TextEdit 120"))
        #expect(lines.contains("  0x700000039->0x70000006D"))
        #expect(lines.contains("macModel MacBookAir17,1"))
        #expect(lines.contains("loginItem on"))
        #expect(lines.contains("appLanguage ko"))
        #expect(lines.contains("systemLanguage ko-KR"))
        #expect(lines.contains("globeUsage showInputMenu"))
        #expect(lines.contains("hotkey60 enabled"))
        #expect(lines.contains("accessibility trusted"))
        #expect(lines.contains("  built-in ANSI Korean"))
        #expect(joined.contains("com.apple.finder"))
    }

    @Test func chordItemSitsUnderAssignedChordsHeader() {
        let lines = DiagnosticsReport.text(full()).components(separatedBy: "\n")
        guard let i = lines.firstIndex(of: "assignedChords") else {
            Issue.record("assignedChords 줄이 없다")
            return
        }
        #expect(lines[i + 1] == "  \(chord)")
    }

    @Test func oldCallersSeeDashForMissingValues() {
        let lines = DiagnosticsReport.text(DiagnosticsInput(
            appVersion: "1.0", build: "7", osVersion: "27.2", strategy: "shortcut", status: "active",
            sources: [], caps: [], fn: [], notUsed: [], settings: [:], logLines: [])).components(separatedBy: "\n")
        for head in ["loginItem", "appLanguage", "systemLanguage", "globeUsage", "hotkey60",
                     "accessibility", "macModel"] {
            #expect(lines.contains("\(head) -"), "\(head)")
        }
        #expect(lines.contains("assignedChords"))
        #expect(lines.contains("keyboards"))
    }

    @Test func logMaskingStays() {
        let text = DiagnosticsReport.text(full(logLines: ["fn decision app=com.foo", "caps long memo=x", "tap installed"]))
        #expect(text.contains("fn decision app=<app>"))
        #expect(!text.contains("memo=x"))
        #expect(!text.contains("com.foo"))
    }

    @Test func messageTextIsNotAccepted() {
        // 입력 글자·메모·메일은 받는 칸 자체가 없다(D-32/D-40).
        let text = DiagnosticsReport.text(full(logLines: ["typed text=hello"]))
        #expect(!text.contains("hello"))
    }

    @Test func totalUnitsStayUnderLimitByDroppingOldestLogLines() {
        let filler = String(repeating: "x", count: 1000)
        let logs = (0..<120).map { "tap installed \($0) \(filler)" }
        let text = DiagnosticsReport.text(full(logLines: logs))
        #expect(DiagnosticsReport.maxUnits == 50_000)
        #expect(text.utf16.count <= DiagnosticsReport.maxUnits)
        #expect(!text.contains("tap installed 0 "))
        #expect(text.contains("tap installed 119 "))
    }

    @Test func noTrimmingWhenUnderLimit() {
        let text = DiagnosticsReport.text(full(logLines: ["tap installed 0", "tap installed 1"]))
        #expect(text.contains("tap installed 0"))
        #expect(text.contains("tap installed 1"))
    }
}
