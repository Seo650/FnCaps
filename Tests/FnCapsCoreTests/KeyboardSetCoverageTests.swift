import Testing
@testable import FnCapsCore

@Suite struct KeyboardSetCoverageTests {
    @Test func coveredSetIsConfirmed() {
        var c = KeyboardSetCoverage()
        #expect(c.confirmed(kernel: [1, 2], listed: [1, 2]) == [1, 2])
        #expect(c.confirmed(kernel: [1], listed: [1, 2]) == [1])
    }

    /// WR-05: 새 키보드(2)가 커널에는 있으나 목록에는 아직 없으면 확정하지 않는다.
    @Test func uncoveredSetIsNotConfirmedSoNextTickEnumeratesAgain() {
        var c = KeyboardSetCoverage()
        #expect(c.confirmed(kernel: [1, 2], listed: [1]) == nil)
        #expect(c.confirmed(kernel: [1, 2], listed: [1, 2]) == [1, 2])
    }

    @Test func neverListedDeviceStopsRetryingAfterLimit() {
        var c = KeyboardSetCoverage()
        for _ in 0..<KeyboardSetCoverage.maxRetries {
            #expect(c.confirmed(kernel: [1, 9], listed: [1]) == nil)
        }
        #expect(c.confirmed(kernel: [1, 9], listed: [1]) == [1, 9])
    }

    @Test func differentUncoveredSetStartsOverAndNilKernelIsNeverConfirmed() {
        var c = KeyboardSetCoverage()
        for _ in 0..<(KeyboardSetCoverage.maxRetries + 1) { _ = c.confirmed(kernel: [1, 9], listed: [1]) }
        #expect(c.confirmed(kernel: [1, 8], listed: [1]) == nil)
        #expect(c.confirmed(kernel: nil, listed: [1]) == nil)
    }
}
