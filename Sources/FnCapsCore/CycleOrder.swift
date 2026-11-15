import Foundation

/// 옛 fn 순서. 04-04부터 KeyLists 이전 입력으로만 읽는다.
public struct CycleOrder: Equatable, Sendable, Codable {
    public let modeKeys: [String]?

    public init(modeKeys: [String]?) { self.modeKeys = modeKeys }

    public static let system = CycleOrder(modeKeys: nil)
}

extension CycleOrder {
    public static let defaultsKey = "fnCycleOrder"

    public func encoded() -> Data? { try? JSONEncoder().encode(self) }

    /// 없거나 깨지면 `.system`.
    public static func decoded(_ data: Data?) -> CycleOrder {
        guard let data, let order = try? JSONDecoder().decode(CycleOrder.self, from: data) else { return .system }
        return order
    }
}
