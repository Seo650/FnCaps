import Foundation

/// 1초 조정의 키보드 집합 캐시를 언제 확정할지 정한다(WR-05). 시스템에 닿지 않는다.
/// 커널 목록에는 있으나 IOHID 클라이언트 목록에는 아직 없는 키보드가 있으면 확정하지 않고 다음 틱에 다시 열거한다.
/// 끝내 목록에 오르지 않는 장치 때문에 매초 열거하지 않도록 같은 집합에는 재시도 횟수를 제한한다.
public struct KeyboardSetCoverage {
    public static let maxRetries = 10
    private var pendingSet: Set<UInt64>?
    private var retries = 0

    public init() {}

    /// 확정할 집합을 돌려준다. nil이면 캐시하지 않아 다음 틱에 다시 열거한다.
    public mutating func confirmed(kernel: Set<UInt64>?, listed: Set<UInt64>) -> Set<UInt64>? {
        guard let kernel else { return nil }
        if kernel.isSubset(of: listed) {
            pendingSet = nil
            retries = 0
            return kernel
        }
        if pendingSet != kernel {
            pendingSet = kernel
            retries = 0
        }
        retries += 1
        return retries > Self.maxRetries ? kernel : nil
    }
}
