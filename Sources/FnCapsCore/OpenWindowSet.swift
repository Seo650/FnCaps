import Foundation

/// 설정 창과 처음 설정 창은 함께 열릴 수 있다(D-03). 둘 중 하나라도 보이면 Dock 아이콘(.regular)을 두고,
/// 마지막 창이 닫힐 때만 .accessory로 돌아간다(UI-SPEC 활성화 정책). 앱 쪽 적용은 WindowPresence(08.1-03)가
/// 한다. 순수 판단만 둔다(SwiftUI·AppKit을 import하지 않는다).
public struct OpenWindowSet: Equatable, Sendable {
    /// 지금 열려 있는 창 이름들.
    public private(set) var ids: Set<String>

    public init() { ids = [] }

    /// 열린 창이 하나도 없는지.
    public var isEmpty: Bool { ids.isEmpty }

    /// 창을 연 것으로 기록한다. 같은 이름을 두 번 열어도 하나다.
    public mutating func open(_ id: String) { ids.insert(id) }

    /// 창을 닫은 것으로 기록한다. 그 이름이 들어 있었고 지운 뒤 집합이 비었을 때만 true다.
    /// 같은 이름을 두 번 닫거나 없는 이름을 닫으면 false다(T-08.1-03).
    @discardableResult
    public mutating func close(_ id: String) -> Bool {
        guard ids.remove(id) != nil else { return false }
        return ids.isEmpty
    }
}
