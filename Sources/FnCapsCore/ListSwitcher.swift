import Foundation

/// D-06, D-07, D-08, D-09, D-10, D-25, D-46: 키별 목록에서 갈 소스를 고르는 순수 규칙.
/// key-list-sim.py press()·press_lists()의 소스 단위 이식이다. 메모리 계산만 하고 시스템을 부르지 않는다
/// (탭 콜백 안 preview에서 불린다). T-04-05: 빈 목록·갈 곳 없음은 fn `.passThrough`, Caps `.noop`.
/// 목록별 분기는 두지 않는다 — 목록은 TriggerKey를 SourceList로 바꿔 같은 경로를 탄다.
public enum ListSwitcher {
    public static func decide(
        _ key: TriggerKey, current: SourceID, layout: KeyLayout, tracker: ListTracker
    ) -> Decision {
        let noMove: Decision = key == .fn ? .passThrough : .noop
        let list = layout.sources(in: key.list)
        guard !list.isEmpty else { return noMove }                          // D-10

        let target: SourceID?
        if let i = list.firstIndex(of: current) {
            if list.count >= 2 {
                target = list[(i + 1) % list.count]                          // D-06
            } else if let p = tracker.previous, p != current, layout.isListed(p) {
                target = p                                                   // D-07
            } else {
                target = fallback(excluding: key.list, layout: layout, tracker: tracker)
            }
        } else {                                                // D-08, D-09, 04.3 진입 언어(D-01)
            let last = tracker.last(in: key.list).flatMap { list.contains($0) ? $0 : nil } ?? list[0]
            switch layout.entry(for: key) {
            case .source(let id) where list.contains(id):
                target = id
            case .last:
                target = last
            default:                                            // .next, 목록에 없는 .source(안전망)
                if list.count > 1, let li = list.firstIndex(of: last) {
                    target = list[(li + 1) % list.count]
                } else {
                    target = last
                }
            }
        }

        guard let target, target != current else { return noMove }
        return .switchTo(target)
    }

    /// D-07의 「직전이 없을 때」 대체 갈래. 자기 목록을 뺀 engineLists 순서(caps → fn → assigned)로
    /// 그 목록에서 마지막으로 쓴 소스, 없으면 그 목록의 첫 소스를 고른다.
    /// Caps [E]·fn []·지정 [R]처럼 fn이 비면 지정 목록이 후보다(조정자 결정 W1).
    private static func fallback(excluding list: SourceList, layout: KeyLayout,
                                 tracker: ListTracker) -> SourceID? {
        for other in SourceList.engineLists where other != list {
            let candidates = layout.sources(in: other)
            guard !candidates.isEmpty else { continue }
            if let last = tracker.last(in: other), candidates.contains(last) { return last }
            return candidates[0]
        }
        return nil
    }

    /// D-46 지정 단축키: 대상이 지정 목록의 켜진 소스이고 지금 소스가 아니면 그 소스로 간다.
    /// 그 밖에는 아무것도 하지 않는다(키만 삼킨다).
    public static func decideAssigned(
        _ target: SourceID, current: SourceID, layout: KeyLayout
    ) -> Decision {
        guard layout.sources(in: .assigned).contains(target), target != current else { return .noop }
        return .switchTo(target)
    }
}
