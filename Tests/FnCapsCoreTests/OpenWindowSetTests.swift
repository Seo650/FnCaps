import Foundation
import Testing
@testable import FnCapsCore

// D-03: 설정 창과 처음 설정 창은 함께 열릴 수 있다. 마지막 창이 닫힐 때만 .accessory로 돌아가야 하므로
// 열린 창 이름 집합과 「마지막 닫힘」 판정을 둔다(T-08.1-03).

@Suite struct OpenWindowSetTests {
    @Test func startsEmptyAndTracksOpenIDs() {
        var set = OpenWindowSet()
        #expect(set.isEmpty)
        #expect(set.ids.isEmpty)

        set.open("settings")
        #expect(!set.isEmpty)
        #expect(set.ids == ["settings"])
    }

    @Test func closesOnlyOnLastWindow() {
        var set = OpenWindowSet()
        set.open("settings")
        set.open("setup")
        #expect(set.ids == ["settings", "setup"])
        #expect(set.close("settings") == false)
        #expect(!set.isEmpty)
        #expect(set.close("setup") == true)
        #expect(set.isEmpty)
    }

    @Test func duplicateOpenCountsOnce() {
        var set = OpenWindowSet()
        set.open("settings")
        set.open("settings")
        #expect(set.ids.count == 1)
        #expect(set.close("settings") == true)
        #expect(set.isEmpty)
    }

    @Test func closingAbsentOrTwiceIsFalse() {
        var set = OpenWindowSet()
        #expect(set.close("setup") == false)

        set.open("setup")
        #expect(set.close("setup") == true)
        #expect(set.close("setup") == false)
    }
}
