import Foundation

/// GAP-04 진단용: AX 판정과 탭 프로브를 따로 보이게 하고, 값이 바뀔 때만 로그 줄을 낸다.
public struct PermissionTrace: Equatable, Sendable {
    private struct Key: Equatable, Sendable {
        var ax: Bool
        var probe: Bool?
        var tapInstalled: Bool
        var tapEnabled: Bool?
    }
    private var last: Key?

    public init() {}

    public mutating func record(ax: Bool, probe: Bool?, tapInstalled: Bool, tapEnabled: Bool?) -> String? {
        let key = Key(ax: ax, probe: probe, tapInstalled: tapInstalled, tapEnabled: tapEnabled)
        if key == last { return nil }
        last = key
        func s(_ b: Bool?) -> String { b.map { $0 ? "true" : "false" } ?? "-" }
        return "permission ax=\(s(ax)) probe=\(s(probe)) tap=\(s(tapInstalled)) tapEnabled=\(s(tapEnabled))"
    }
}
