import Foundation

/// D-07, D-08, D-09, D-46: 현재·직전 소스와 목록별로 마지막으로 쓴 소스를 추적한다.
/// 목록별 마지막 값은 SourceList를 키로 한 표 하나다. 지정 목록도 Caps·fn과 같은 일급 목록이다.
/// 어느 목록에도 없는 소스는 거쳐도 상태가 바뀌지 않는다(Pitfall 5).
public struct ListTracker: Equatable, Sendable {
    public private(set) var current: SourceID?
    public private(set) var previous: SourceID?
    public private(set) var last: [SourceList: SourceID] = [:]

    public init() {}

    public var lastCaps: SourceID? { last[.caps] }
    public var lastFn: SourceID? { last[.fn] }

    public func last(for key: TriggerKey) -> SourceID? { last[key.list] }

    public func last(in list: SourceList) -> SourceID? { last[list] }

    /// `history`는 최신순(시스템 최근 기록). 오래된 것부터 반영하고 마지막에 현재를 반영한다.
    public mutating func seed(current: SourceID?, history: [SourceID], layout: KeyLayout) {
        self.current = nil
        previous = nil
        last = [:]
        for id in history.reversed() { observe(selected: id, layout: layout, inFlight: false) }
        if let current { observe(selected: current, layout: layout, inFlight: false) }
    }

    /// 상태가 바뀌면 true. 전환 중(`inFlight`)에는 우리 선택이 사용자 선택으로 기록되지 않게 무시한다.
    /// 지정 소스로 가도 그 소스가 지금 소스·직전 소스가 되고 지정 목록의 마지막이 된다(D-46).
    /// 복제된 소스는 그 소스가 든 모든 목록의 마지막이 된다(2026-11-11).
    @discardableResult
    public mutating func observe(selected: SourceID, layout: KeyLayout, inFlight: Bool) -> Bool {
        if inFlight { return false }
        let lists = layout.lists(of: selected)
        guard !lists.isEmpty else { return false }
        if selected == current { return false }
        previous = current
        current = selected
        for list in lists { last[list] = selected }
        return true
    }

    /// 목록에서 사라진 소스를 가리키는 값을 지운다.
    public mutating func reconcile(layout: KeyLayout) {
        for list in SourceList.engineLists {
            if let value = last[list], !layout.sources(in: list).contains(value) { last[list] = nil }
        }
        if let p = previous, !layout.isListed(p) { previous = nil }
    }

    // 시험 전용: 정확한 상태를 만든다.
    mutating func setForTesting(current: SourceID?, previous: SourceID?,
                                lastCaps: SourceID?, lastFn: SourceID?,
                                lastAssigned: SourceID? = nil) {
        self.current = current
        self.previous = previous
        var table: [SourceList: SourceID] = [:]
        if let lastCaps { table[.caps] = lastCaps }
        if let lastFn { table[.fn] = lastFn }
        if let lastAssigned { table[.assigned] = lastAssigned }
        last = table
    }
}
