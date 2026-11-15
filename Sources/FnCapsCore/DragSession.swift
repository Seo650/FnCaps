import Foundation

/// 끄는 동안 넣을 자리(재설계 §4). 번호는 화면에 보이는(켜진) 소스 기준이다.
public enum DragTarget: Equatable, Sendable {
    /// 상자 밖. 놓으면 원래 자리로 돌아간다.
    case none
    /// 이 목록의 이 칸에 넣는다.
    case slot(SourceList, Int)
    /// 꽉 찬 다른 키 상자. 자리가 열리지 않는다.
    case refused(SourceList)
}

/// 놓을 때 모델에 한 번 반영할 값. 번호는 보이는 자리다(04-10 `moveSource(id:to:at:)`).
/// `.move`는 origin 목록의 한 칸만 옮기고, `.copy`는 ⌥ 끌기로 대상 목록에 하나 더 넣는다(복제, 2026-11-11).
public enum DropOutcome: Equatable, Sendable {
    case none
    case move(SourceID, SourceList, Int)
    case copy(SourceID, SourceList, Int)
}

/// 끌기 상태 기계. 끄는 동안의 slots는 화면 상태만 만들고, 모델 반영은 outcome() 하나뿐이다.
public struct DragSession: Equatable, Sendable {
    public let id: SourceID
    public let origin: SourceList
    public let originIndex: Int
    /// origin 밖에서 이 소스가 이미 든 엔진 목록. 옮기면 합쳐지고, 복제는 거절한다.
    public let present: Set<SourceList>
    /// ⌥를 누르고 있는 동안 true(복제). 끄는 중에도 바뀐다.
    public var copy: Bool
    public private(set) var target: DragTarget

    public init(id: SourceID, origin: SourceList, originIndex: Int,
                present: Set<SourceList> = [], copy: Bool = false) {
        self.id = id
        self.origin = origin
        self.originIndex = originIndex
        self.present = present.subtracting([origin, .excluded])
        self.copy = copy
        self.target = copy ? .none : .slot(origin, originIndex)
    }

    /// 이 목록 칸에서 끄는 소스를 빼고 그릴지. 원래 목록(옮기기)과, 복제가 있는 대상 목록(합치기)이다.
    private func hidesSelf(in list: SourceList) -> Bool {
        if copy { return false }
        if list == origin { return true }
        if case let .slot(targetList, _) = target, targetList == list { return present.contains(list) }
        return false
    }

    /// 포인터가 놓인 상자(zone)와 그 상자 고리 위 각도로 target을 고친다.
    /// counts는 목록별 보이는 소스 수(끄는 소스 포함)다.
    public mutating func update(zone: SourceList?, angle: Double?, counts: [SourceList: Int],
                                maxPerKey: Int = 6,
                                hysteresis: Double = RingGeometry.defaultHysteresis) {
        guard let zone else { target = .none; return }
        let count = max(counts[zone] ?? 0, 0)
        if copy {
            // 복제: 다른 엔진 목록에만, 이미 있는 목록에는 넣지 않는다(같은 목록 안 중복 금지).
            guard zone != origin, zone != .excluded else { target = .none; return }
            if present.contains(zone) || count >= maxPerKey { target = .refused(zone); return }
        }
        // 이미 복제가 든 목록으로 옮기면 합쳐지므로 그 칸은 세지 않는다.
        let merge = !copy && present.contains(zone)
        let own = zone == origin || merge
        switch zone {
        case .excluded:
            // 「사용 안 함」 상자는 끝에만 넣는다. 각도는 쓰지 않는다.
            // 같은 상자 안에서는 순서를 바꾸지 않으므로 빈 칸을 원래 자리에 둔다(04-REVIEW WR-04).
            target = .slot(.excluded, own ? originIndex : count)
        case .assigned:
            // 「지정 단축키」 상자도 줄 상자라 끝에만 넣는다(04-22가 그린다). 상한만 따로 본다(D-46).
            // 같은 상자 안에서는 순서를 바꾸지 않는다(WR-04).
            if !own && count >= maxPerKey { target = .refused(.assigned); return }
            target = .slot(.assigned, zone == origin ? originIndex : (merge ? max(count - 1, 0) : count))
        case .caps, .fn:
            if !own && count >= maxPerKey { target = .refused(zone); return }
            // 고리 칸 수 = 끄는 소스를 뺀 개수 + 1(§4 자리 비우기).
            let slotCount = max(count - (own ? 1 : 0), 0) + 1
            var previous: Int? = nil
            if case let .slot(list, p) = target, list == zone { previous = p }
            let index = RingGeometry.insertionIndex(pointerAngle: angle ?? .pi, slotCount: slotCount,
                                                    previous: previous, hysteresis: hysteresis)
            target = .slot(zone, index)
        }
    }

    /// 화면에 그릴 목록 칸. nil은 빈 칸(점선)이다. ids는 그 목록의 보이는 소스 순서다.
    public func slots(for list: SourceList, ids: [SourceID]) -> [SourceID?] {
        let base: [SourceID] = hidesSelf(in: list) ? ids.filter { $0 != id } : ids
        if case let .slot(targetList, index) = target, targetList == list {
            var result: [SourceID?] = base.map { $0 }
            result.insert(nil, at: min(max(index, 0), result.count))
            return result
        }
        guard list == origin, !copy else { return ids.map { $0 } }
        if case .slot = target { return base.map { $0 } } // 다른 상자로 갔으면 원래 고리는 빈 칸을 닫는다.
        return ids.map { $0 == id ? nil : $0 }            // 상자 밖·거절이면 원래 자리 빈 칸 유지.
    }

    /// 놓을 때 반영할 값. 제자리·거절·상자 밖은 반영 없음.
    public func outcome() -> DropOutcome {
        guard case let .slot(list, index) = target else { return .none }
        if copy { return list == origin ? .none : .copy(id, list, index) }
        if list == origin && index == originIndex { return .none }
        return .move(id, list, index)
    }

    /// Esc 또는 끌기 취소.
    public mutating func cancel() { target = .none }
}
