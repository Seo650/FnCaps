import Testing
@testable import FnCapsCore

private func src(
    _ id: String, name: String? = nil, type: String = "TISTypeKeyboardInputMode",
    bundleID: String? = nil, mode: String? = nil
) -> SourceInfo {
    SourceInfo(
        id: id, localizedName: name ?? id, languages: [], type: type, bundleID: bundleID,
        inputModeID: mode, isSelectCapable: true, isEnabled: true)
}

@Suite struct InputSourceHistoryMatcherTests {
    let ko = src("com.apple.inputmethod.Korean.2SetKorean", mode: "com.apple.inputmethod.Korean.2SetKorean")
    let gureum = src("org.youknowone.inputmethod.Gureum.han2", bundleID: "org.youknowone.inputmethod.Gureum")
    let abc = src("com.apple.keylayout.ABC", name: "ABC", type: "TISTypeKeyboardLayout")
    let us = src("com.apple.keylayout.US", name: "U.S.", type: "TISTypeKeyboardLayout")

    @Test func matchesInputMode() {
        let r = InputSourceHistoryMatcher.match(
            [HistoryEntry(inputMode: ko.inputModeID, bundleID: nil, layoutName: nil)], among: [abc, ko])
        #expect(r == [ko.id])
    }

    @Test func matchesBundleWhenNoMode() {
        let r = InputSourceHistoryMatcher.match(
            [HistoryEntry(inputMode: nil, bundleID: "org.youknowone.inputmethod.Gureum", layoutName: nil)],
            among: [ko, gureum])
        #expect(r == [gureum.id])
    }

    @Test func matchesLayoutByID() {
        let r = InputSourceHistoryMatcher.match(
            [HistoryEntry(inputMode: nil, bundleID: nil, layoutName: "ABC")], among: [abc, us])
        #expect(r == [abc.id])
    }

    @Test func matchesLayoutStrippedNonAlphanumerics() {
        let r = InputSourceHistoryMatcher.match(
            [HistoryEntry(inputMode: nil, bundleID: nil, layoutName: "U.S.")], among: [abc, us])
        #expect(r == [us.id])
    }

    @Test func fallsBackToUniqueLocalizedName() {
        let dvorak = src("com.apple.keylayout.Dvorak-Custom", name: "Dvorak X", type: "TISTypeKeyboardLayout")
        let r = InputSourceHistoryMatcher.match(
            [HistoryEntry(inputMode: nil, bundleID: nil, layoutName: "Dvorak X")], among: [abc, dvorak])
        #expect(r == [dvorak.id])
    }

    @Test func ambiguousLocalizedNameIsDropped() {
        let a = src("com.example.keylayout.A", name: "Same", type: "TISTypeKeyboardLayout")
        let b = src("com.example.keylayout.B", name: "Same", type: "TISTypeKeyboardLayout")
        let r = InputSourceHistoryMatcher.match(
            [HistoryEntry(inputMode: nil, bundleID: nil, layoutName: "Same")], among: [a, b])
        #expect(r.isEmpty)
    }

    @Test func nonLayoutSourceIsNotNameMatched() {
        let r = InputSourceHistoryMatcher.match(
            [HistoryEntry(inputMode: nil, bundleID: nil, layoutName: "Korean")],
            among: [src("x.mode", name: "Korean")])
        #expect(r.isEmpty)
    }

    @Test func skipsUnmatchedDedupesKeepsOrder() {
        let entries = [
            HistoryEntry(inputMode: "nope", bundleID: nil, layoutName: nil),
            HistoryEntry(inputMode: ko.inputModeID, bundleID: nil, layoutName: nil),
            HistoryEntry(inputMode: nil, bundleID: nil, layoutName: "ABC"),
            HistoryEntry(inputMode: ko.inputModeID, bundleID: nil, layoutName: nil),
        ]
        #expect(InputSourceHistoryMatcher.match(entries, among: [abc, ko]) == [ko.id, abc.id])
    }

    @Test func emptyEntries() {
        #expect(InputSourceHistoryMatcher.match([], among: [abc]).isEmpty)
    }
}
