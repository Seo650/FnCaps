import Foundation
import Testing
@testable import FnCapsCore

/// 옛 fn 순서는 KeyLists 이전 입력으로만 남았다. 저장 왕복과 깨진 Data만 확인한다.
@Suite struct CycleOrderTests {
    @Test func encodingRoundTripsAndBadDataFallsBack() throws {
        let order = CycleOrder(modeKeys: ["ja", "ko"])
        #expect(CycleOrder.decoded(try #require(order.encoded())) == order)
        #expect(CycleOrder.decoded(try #require(CycleOrder.system.encoded())) == .system)
        #expect(CycleOrder.decoded(nil) == .system)
        #expect(CycleOrder.decoded(Data("not json".utf8)) == .system)
        #expect(CycleOrder.defaultsKey == "fnCycleOrder")
    }
}
