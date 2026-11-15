import Foundation

/// 입력 소스 전환 뒤 대기 시간(ms) 규칙. D-26: fn 전환에만 쓰이며 어느 키에 쓸지는 호출자(AppModel)가 정한다.
/// 2026-11-11: 앱별 대기 시간을 없앴다. 대기 시간은 전체 값 하나이고, 앱별 설정은 「FnCaps 끄기」 목록이다.
public enum SettleTimePolicy {
    public static let defaultMs = 80
    public static let range = 0...150
    public static let stepMs = 5

    public static func clamp(_ ms: Int) -> Int { min(max(ms, range.lowerBound), range.upperBound) }

    /// 맨 앞 앱이 「FnCaps 끄기」 행이면 true(FINAL-REVIEW §3-1 B).
    public static func isOff(exceptions: [SettleException], frontBundleID: String?) -> Bool {
        guard let id = frontBundleID else { return false }
        return exceptions.first(where: { $0.bundleID == id })?.off ?? false
    }
}

public struct SettleException: Equatable, Codable, Sendable {
    public let bundleID: String
    public var ms: Int
    /// 「FnCaps 끄기」. 지금 목록의 행은 모두 true다. ms와 off는 옛 빌드와 저장값을 나누려고 남긴다.
    public var off: Bool

    public init(bundleID: String, ms: Int, off: Bool = false) {
        self.bundleID = bundleID
        self.ms = ms
        self.off = off
    }

    private enum CodingKeys: String, CodingKey { case bundleID, ms, off }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        bundleID = try c.decode(String.self, forKey: .bundleID)
        ms = try c.decode(Int.self, forKey: .ms)
        // 옛 저장값(off 없음)은 false로 읽는다. 저장 키 settleExceptions.v1은 그대로.
        off = try c.decodeIfPresent(Bool.self, forKey: .off) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(bundleID, forKey: .bundleID)
        try c.encode(ms, forKey: .ms)
        try c.encode(off, forKey: .off)
    }
}

public enum SettleExceptions {
    public static let defaultsKey = "settleExceptions.v1"
    public static let maxCount = 100

    public static func isValidBundleID(_ s: String) -> Bool {
        guard let first = s.unicodeScalars.first, s.unicodeScalars.count <= 255 else { return false }
        func alnum(_ c: Unicode.Scalar) -> Bool {
            (c >= "A" && c <= "Z") || (c >= "a" && c <= "z") || (c >= "0" && c <= "9")
        }
        guard alnum(first) else { return false }
        return s.unicodeScalars.allSatisfy { alnum($0) || $0 == "." || $0 == "-" }
    }

    /// 옛 「대기 시간만」 행(off == false)은 버린다. 그 앱에서 FnCaps를 끄라는 뜻이 아니었기 때문이다(2026-11-11).
    /// 다음 저장 때 목록에서 사라진다.
    public static func decoded(_ data: Data?) -> [SettleException] {
        guard let data, let raw = try? JSONDecoder().decode([SettleException].self, from: data) else { return [] }
        var seen = Set<String>()
        var out: [SettleException] = []
        for e in raw where e.off && isValidBundleID(e.bundleID) && !seen.contains(e.bundleID) {
            if out.count >= maxCount { break }
            seen.insert(e.bundleID)
            out.append(SettleException(bundleID: e.bundleID, ms: SettleTimePolicy.clamp(e.ms), off: e.off))
        }
        return out
    }

    public static func encoded(_ list: [SettleException]) -> Data? { try? JSONEncoder().encode(list) }

    /// 새 행은 「FnCaps 끄기」다. 이미 있으면 그 자리를 돌려준다.
    public static func adding(_ list: [SettleException], bundleID: String) -> (list: [SettleException], index: Int)? {
        guard isValidBundleID(bundleID) else { return nil }
        if let i = list.firstIndex(where: { $0.bundleID == bundleID }) { return (list, i) }
        guard list.count < maxCount else { return nil }
        return (list + [SettleException(bundleID: bundleID, ms: SettleTimePolicy.defaultMs, off: true)], list.count)
    }

    public static func removing(_ list: [SettleException], bundleID: String) -> [SettleException] {
        list.filter { $0.bundleID != bundleID }
    }
}
