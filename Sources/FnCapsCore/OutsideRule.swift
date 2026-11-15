import Foundation

/// D-08: 현재 소스가 누른 키의 목록 밖일 때 어디로 갈지(M-7 전역 규칙 하나).
public enum OutsideRule: String, Codable, Sendable, CaseIterable {
    /// 그 목록에서 마지막으로 쓴 소스의 다음 (기본)
    case nextAfterLast = "next"
    /// 그 목록에서 마지막으로 쓴 소스
    case last = "last"

    public static let defaultsKey = "outsideRule"

    /// 모르는 값이나 nil은 기본값으로 읽는다.
    public static func decoded(_ raw: String?) -> OutsideRule {
        raw.flatMap(OutsideRule.init(rawValue:)) ?? .nextAfterLast
    }
}
