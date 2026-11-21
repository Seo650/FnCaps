import Foundation
import Testing
import FnCapsCore
@testable import FnCapsSystem

/// 읽기 전용 시스템 시험. 표시등 값을 쓰지 않고, 이 Mac이 준 서비스 수·값도 단언하지 않는다.
@Suite(.serialized)
@MainActor
struct CapsLedSmokeTests {
    @Test func statusEnumeratesWithoutWriting() {
        guard let rows = CapsLed().status() else { return }
        // Transport가 없거나 Virtual인 서비스(리매퍼 가상 키보드)는 쓰기 대상이 아니다.
        for row in rows where row.transport == nil || row.transport == "Virtual" {
            #expect(row.eligible == false, "registryID=\(row.registryID)")
        }
    }
}
