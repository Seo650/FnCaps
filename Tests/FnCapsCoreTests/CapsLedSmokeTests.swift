import Foundation
import Testing
import FnCapsCore
@testable import FnCapsSystem

/// 읽기 전용 시스템 시험. 표시등 값을 쓰지 않고, 이 Mac이 준 서비스 수·값도 단언하지 않는다.
@Suite(.serialized)
@MainActor
struct CapsLedSmokeTests {
    @Test func statusEnumeratesWithoutWriting() {
        guard let rows = CapsLed().status() else {
            // passive 클라이언트를 만들 수 없는 환경에서 조용히 통과하지 않는다(07-REVIEW IN-06).
            withKnownIssue("passive 클라이언트를 만들 수 없음", isIntermittent: true) {
                Issue.record("status() returned nil")
            }
            return
        }
        // Transport가 없거나 Virtual인 서비스(리매퍼 가상 키보드)는 쓰기 대상이 아니다.
        for row in rows where row.transport == nil || row.transport == CapsLedTarget.virtualTransport {
            #expect(row.eligible == false, "registryID=\(row.registryID)")
        }
    }
}
