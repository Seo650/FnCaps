import AppKit
import CoreGraphics
import FnCapsCore
import SwiftUI

/// 타일 하나의 정체. 복제(2026-11-11)로 같은 소스가 여러 상자에 있으므로 상자와 소스를 함께 쓴다.
struct TileKey: Hashable {
    let list: SourceList
    let id: SourceID
}

/// 키와 언어 쪽의 화면 상태 계약. 설정값은 넣지 않는다.
/// 04-16이 쓰고 04-17이 끌기 상태를 더한다. 이 파일은 모델을 부르지 않는다(모델 반영은 KeysPage의 놓기 한 곳).
final class KeysPageState: ObservableObject {
    /// 포인터가 올라간 소스 행과 그 상자(복제된 소스는 상자마다 따로 올라간다).
    @Published var hoveredID: SourceID?
    @Published var hoveredList: SourceList?
    /// 타일에 포인터가 들어온 시각. 「새로 추가됨」 점은 잠깐 머문 뒤 나갈 때만 지운다(04.1 리뷰 WR-02).
    var hoverStarts: [SourceID: Date] = [:]
    static let newTagDwell: TimeInterval = 0.3

    func isHovered(_ id: SourceID?, in list: SourceList) -> Bool {
        id != nil && hoveredID == id && hoveredList == list
    }
    /// 목록(Caps, fn, 사용 안 함)별 화면 영역. 끌어 놓기 판정에 쓴다.
    @Published var zoneFrames: [SourceList: CGRect] = [:]
    /// 진입 언어 ⓘ 팝오버. 한 번에 하나(04.4 D-21).
    @Published var entryInfoOpen: SourceList?
    /// Caps·fn 고리 중심(좌표계 "keys"). 포인터 각도를 잴 때 쓴다.
    @Published var ringCenters: [SourceList: CGPoint] = [:]

    // MARK: 녹화(D-46, 04-22)
    // 값 선언만 Task 1이 더한다. 값을 바꾸는 메서드는 Task 2가 더한다.

    /// 녹화 중인 지정 소스. 없으면 nil.
    @Published private(set) var recordingID: SourceID?
    /// 녹화 중 누르고 있는 수정 키 비트(⌃⌥⇧⌘).
    @Published private(set) var recordingModifiers: UInt64 = 0
    /// 녹화 거절 문구. 다음 키를 받기 전까지 보인다.
    @Published private(set) var recordingMessage: String?
    /// 빼앗기 알림(「%@에서 옮김」). 다음 녹화 시작·쪽 이동 때 지운다.
    @Published private(set) var lastNotice: String?

    /// 녹화 처리 묶음. KeysPage가 만들어 넘긴다. 이 파일은 모델을 직접 부르지 않는다.
    struct RecordHandlers {
        let validate: (UInt16, UInt64) -> ChordValidation.Result
        let commit: (KeyChord?) -> Void
        let began: () -> Void
        let ended: () -> Void
        let announce: (String) -> Void
        let message: (ChordValidation.Refusal) -> String
        let format: (KeyChord) -> String
        let takenNotice: (SourceID) -> String
        /// 접근성 알림에 넣을 소스 이름.
        let sourceName: (SourceID) -> String
    }

    /// 녹화 키 감시. macOS 26/27에서 약하게 잡으면 감시가 조용히 멈추므로 강하게 보관한다(연구 §2-1).
    private var recordMonitor: Any?
    private var handlers: RecordHandlers?

    // MARK: 끌기(재설계 §4)

    /// 끄는 중이면 값이 있다. 판정은 FnCapsCore.DragSession이 한다.
    @Published private(set) var drag: FnCapsCore.DragSession?
    /// 포인터 위치(좌표계 "keys").
    @Published private(set) var pointer: CGPoint = .zero
    /// 잡은 점 − 타일 중심. 떠오른 타일이 포인터 아래에서 튀지 않게 한다.
    @Published private(set) var grabOffset: CGSize = .zero
    /// 끄는 동안 고정한 Caps·fn 상자 높이.
    @Published private(set) var frozenHeights: [SourceList: CGFloat] = [:]
    /// 타일 프레임(좌표계 "keys"). 잡은 타일과 오프셋을 찾을 때 쓴다.
    @Published var tileFrames: [TileKey: CGRect] = [:]

    /// 끌기를 놓거나 취소할 때 쓸 애니메이션. KeysPage가 동작 줄이기 설정에 맞춰 넣는다.
    var settleAnimation: Animation? = .spring(response: 0.3, dampingFraction: 0.8)
    /// 넣을 자리가 바뀔 때(자리 열기·닫기, 바탕, 6/6) 쓸 애니메이션. 동작 줄이기면 nil(즉시 배치).
    var slotAnimation: Animation? = .spring(response: 0.35, dampingFraction: 0.85)

    private var escMonitor: Any?
    /// ⌥를 누르고 떼는 것을 끄는 동안 따라간다(복제 ↔ 옮기기).
    private var flagsMonitor: Any?
    private var cursorPushed = false
    /// 이 제스처에서 이미 끌기를 시작했는지. Esc 취소 뒤 같은 제스처가 다시 시작하지 않게 한다.
    private var gestureStarted = false
    /// 마지막 move가 받은 목록별 수. 가장자리 자동 스크롤 타이머가 다시 판정할 때 쓴다.
    private var lastCounts: [SourceList: Int] = [:]
    /// 쪽 ScrollView가 보이는 영역(좌표계 "keys"). ScrollEdgeHelper가 채운다.
    var viewportInKeys: CGRect?
    /// 그 영역만큼 스크롤한다. 실제로 움직인 양을 돌려준다(ScrollEdgeHelper가 채운다).
    var scrollBy: ((CGFloat) -> CGFloat)?
    private var scrollTimer: Timer?

    /// 키 칸 폭(DS.keyZoneWidth와 같은 값). 고리 칸 영역을 상자 전체로 넓힐 때 쓴다.
    private static let keyZoneWidth = DS.keyZoneWidth

    /// 이번 제스처가 새 끌기를 시작해도 되는지. 시작하면 onGestureEnded 전까지 false.
    var canBeginInThisGesture: Bool { drag == nil && !gestureStarted }

    /// 제스처가 끝났다(놓기 처리 뒤). 다음 제스처가 다시 시작할 수 있게 한다.
    func onGestureEnded() { gestureStarted = false }

    // MARK: 녹화(D-46)

    /// 지정 소스 녹화를 시작한다. 이미 녹화 중이면 먼저 끝내고, 끄는 중이면 시작하지 않는다.
    /// interactive가 false면(렌더) 키 감시를 붙이지 않는다.
    func startRecording(_ id: SourceID, handlers: RecordHandlers, interactive: Bool = true) {
        if recordingID != nil { endRecording() }
        guard drag == nil else { return }
        recordingID = id
        recordingModifiers = 0
        recordingMessage = nil
        lastNotice = nil
        self.handlers = handlers
        handlers.began()
        guard interactive else { return }
        handlers.announce(L("keys.assigned.recording"))
        recordMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.keyDown, .flagsChanged, .leftMouseDown, .rightMouseDown]
        ) { [weak self] event in
            self?.handleRecordEvent(event) ?? event
        }
    }

    /// 빼앗기 알림을 지운다. 쪽 이동·창 닫기에서 부른다.
    func clearNotice() { lastNotice = nil }

    #if DEBUG
    /// 렌더 전용: 녹화 값만 넣는다. 감시·처리 묶음·탭 멈춤은 건드리지 않는다(T-04-75).
    func debugRecording(id: SourceID?, modifiers: UInt64, message: String?) {
        recordingID = id
        recordingModifiers = modifiers
        recordingMessage = message
    }

    /// 렌더 전용: 빼앗기 알림만 넣는다.
    func debugNotice(_ text: String?) { lastNotice = text }
    #endif

    /// 녹화를 끝낸다. 감시 제거와 탭 멈춤 해제는 이 한 곳에서만 한다(T-04-72). 멱등.
    func endRecording() {
        guard recordingID != nil || recordMonitor != nil || handlers != nil else { return }
        if let monitor = recordMonitor {
            NSEvent.removeMonitor(monitor)
            recordMonitor = nil
        }
        let current = handlers
        handlers = nil
        recordingID = nil
        recordingModifiers = 0
        recordingMessage = nil
        current?.ended()
    }

    /// 녹화 중 키 하나를 처리한다. 처리한 이벤트는 nil을 돌려 앱 안 전달을 멈춘다(연구 §7-1).
    private func handleRecordEvent(_ event: NSEvent) -> NSEvent? {
        guard let id = recordingID, let handlers else { return event }
        switch event.type {
        case .flagsChanged:
            // 누르고 있는 수정 키를 바로 보여 준다.
            recordingModifiers = UInt64(event.modifierFlags.rawValue) & HotkeyChord.modifierBits
            return event
        case .leftMouseDown, .rightMouseDown:
            // 다른 곳 클릭 = 끝. 단축키 칸을 누르면 버튼 동작이 다시 시작한다.
            endRecording()
            return event
        case .keyDown:
            break
        default:
            return event
        }
        let keyCode = event.keyCode
        let modifiers = UInt64(event.modifierFlags.rawValue) & HotkeyChord.modifierBits
        if modifiers == 0 {
            switch keyCode {
            case 53:  // Esc: 취소. 이전 조합을 그대로 둔다.
                endRecording()
                return nil
            case 51, 117:  // Delete, Forward Delete: 지운다.
                handlers.commit(nil)
                endRecording()
                return nil
            case 48:  // Tab: 녹화를 끝내고 다음 칸으로 넘긴다.
                endRecording()
                return event
            default:
                break
            }
        }
        // ⌘W·⌘Q는 창 닫기·종료로 넘긴다(MASShortcut Spec 규칙).
        if modifiers == 0x100000, keyCode == 13 || keyCode == 12 {
            endRecording()
            return event
        }
        switch handlers.validate(keyCode, modifiers) {
        case let .accepted(chord, takenFrom):
            handlers.commit(chord)
            handlers.announce(LF("keys.assigned.saved", handlers.format(chord), handlers.sourceName(id)))
            if let takenFrom {
                let notice = handlers.takenNotice(takenFrom)
                lastNotice = notice
                handlers.announce(notice)
            }
            endRecording()
            return nil
        case let .refused(refusal):
            NSSound.beep()
            let text = handlers.message(refusal)
            recordingMessage = text
            handlers.announce(text)
            return nil
        }
    }

    // MARK: 가장자리 자동 스크롤(W7)

    /// 60 Hz 타이머. 끄는 동안, interactive 끌기에서만 만든다. NSScrollView를 못 찾으면 만들지 않는다.
    private func startAutoScroll() {
        guard scrollTimer == nil, viewportInKeys != nil, scrollBy != nil else { return }
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.autoScrollTick()
        }
        RunLoop.main.add(timer, forMode: .common)
        scrollTimer = timer
    }

    private func stopAutoScroll() {
        scrollTimer?.invalidate()
        scrollTimer = nil
    }

    private func autoScrollTick() {
        guard drag != nil, let viewport = viewportInKeys, let scrollBy else { return }
        let step = DragAutoScroll.step(pointerY: Double(pointer.y),
                                       viewportMinY: Double(viewport.minY),
                                       viewportMaxY: Double(viewport.maxY))
        guard step != 0 else { return }
        let actual = scrollBy(CGFloat(step))
        guard actual != 0 else { return }
        // 화면은 그대로인데 내용이 움직였으므로 포인터의 내용 좌표도 같이 옮긴다.
        viewportInKeys = viewport.offsetBy(dx: 0, dy: actual)
        move(to: CGPoint(x: pointer.x, y: pointer.y + actual), counts: lastCounts)
    }

    /// 끌기 시작. interactive가 false면(렌더) 커서와 Esc 감시를 붙이지 않는다.
    /// present는 origin 밖에서 이 소스가 이미 든 엔진 목록이다. copy는 ⌥로 시작했는지(복제).
    func begin(id: SourceID, origin: SourceList, index: Int, at point: CGPoint,
               counts: [SourceList: Int], present: Set<SourceList> = [], copy: Bool = false,
               interactive: Bool = true) {
        if recordingID != nil { endRecording() }
        guard drag == nil else { return }
        gestureStarted = true
        lastCounts = counts
        hoveredID = nil
        hoveredList = nil
        // 「사용 안 함」에서 끄는 것은 복제가 아니다(그 상자에서는 빠지는 것이 맞다).
        drag = FnCapsCore.DragSession(id: id, origin: origin, originIndex: index, present: present,
                                      copy: copy && origin != .excluded)
        if let frame = tileFrames[TileKey(list: origin, id: id)] {
            grabOffset = CGSize(width: point.x - frame.midX, height: point.y - frame.midY)
        } else {
            grabOffset = .zero
        }
        pointer = point
        // 잡는 순간에는 상자 크기를 그대로 둔다. 다른 키 상자는 포인터가 그 위에 올라갈 때만 한 칸 커진다
        // (2026-11-08 사용자 요청: 「이 박스위에 마우스가 올라가면 그때 켜지게」).
        frozenHeights = Self.boxHeights(counts: counts, origin: origin, hovering: nil)
        guard interactive else { return }
        (drag?.copy == true ? NSCursor.dragCopy : NSCursor.closedHand).push()
        cursorPushed = true
        escMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.keyCode == 53 else { return event }
            self.cancel()
            return nil
        }
        flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.setCopy(event.modifierFlags.contains(.option))
            return event
        }
        startAutoScroll()
    }

    /// 끄는 중 ⌥ 상태가 바뀌면 복제·옮기기를 바꾸고 커서(「+」)를 맞춘 뒤 자리를 다시 판정한다.
    private func setCopy(_ on: Bool) {
        guard var session = drag, session.origin != .excluded, session.copy != on else { return }
        session.copy = on
        drag = session
        if cursorPushed {
            NSCursor.pop()
            (on ? NSCursor.dragCopy : NSCursor.closedHand).push()
        }
        move(to: pointer, counts: lastCounts)
    }

    /// 포인터 이동. 영역과 고리 각도로 넣을 자리를 정한다. 끄는 중이 아니면 무시한다.
    func move(to point: CGPoint, counts: [SourceList: Int]) {
        guard var session = drag else { return }
        lastCounts = counts
        pointer = point
        let zone = zone(at: point)
        var angle: Double?
        // 고리는 Caps·fn뿐이다. 지정 상자는 줄 상자라 각도를 쓰지 않는다(연구 §6-3).
        if let zone, zone == .caps || zone == .fn, let center = ringCenters[zone] {
            let visible = counts[zone] ?? 0
            let own = zone == session.origin && !session.copy || !session.copy && session.present.contains(zone)
            let slots = max(visible - (own ? 1 : 0), 0) + 1
            let radii: RingGeometry.Radii
            if let frozen = frozenHeights[zone] {
                radii = RingGeometry.radii(count: slots, maxBoxHeight: Double(frozen))
            } else {
                radii = RingGeometry.radii(count: slots)
            }
            angle = RingGeometry.pointerAngle(dx: Double(point.x - center.x),
                                              dy: Double(point.y - center.y), radii: radii)
        }
        session.update(zone: zone, angle: angle, counts: counts)
        // 이미 복제가 든 상자는 칸이 늘지 않으므로(합치기·복제 거절) 키우지 않는다.
        let growing = zone.flatMap { session.present.contains($0) ? nil : $0 }
        let heights = Self.boxHeights(counts: counts, origin: session.origin, hovering: growing)
        // 포인터는 애니메이션 없이 따라가고, 자리 변화와 상자 크기 변화만 spring으로 움직인다.
        if session != drag || heights != frozenHeights {
            withAnimation(slotAnimation) {
                drag = session
                frozenHeights = heights
            }
        }
    }

    /// 끄는 동안의 키 상자 높이. 원래 상자는 그대로, 포인터가 올라간 다른 키 상자만 한 칸(6개 상한 안에서) 커진다.
    static func boxHeights(counts: [SourceList: Int], origin: SourceList,
                           hovering: SourceList?) -> [SourceList: CGFloat] {
        var heights: [SourceList: CGFloat] = [:]
        for list in [SourceList.caps, .fn] {
            let grow = (hovering == list && list != origin) ? 1 : 0
            let n = min((counts[list] ?? 0) + grow, KeyLists.maxPerKey)
            heights[list] = CGFloat(RingGeometry.boxHeight(count: n))
        }
        return heights
    }

    /// 포인터가 놓인 상자. Caps·fn은 키 칸까지 넣은 상자 전체, 지정·사용 안 함은 상자 전체.
    private func zone(at point: CGPoint) -> SourceList? {
        for list in [SourceList.caps, .fn] {
            guard let ring = zoneFrames[list] else { continue }
            let box = CGRect(x: ring.minX - Self.keyZoneWidth, y: ring.minY,
                             width: ring.width + Self.keyZoneWidth, height: ring.height)
            if box.contains(point) { return list }
        }
        if let assigned = zoneFrames[.assigned], assigned.contains(point) { return .assigned }
        if let unused = zoneFrames[.excluded], unused.contains(point) { return .excluded }
        return nil
    }

    /// 놓을 때 반영할 값. 정리는 호출자가 애니메이션 안에서 end()로 한다.
    func finish() -> DropOutcome {
        drag?.outcome() ?? .none
    }

    /// 끌기 상태를 모두 지운다. 커서 pop·Esc 감시 제거·자동 스크롤 타이머 정지는 여기 한 곳에서만 한다.
    func end() {
        drag = nil
        frozenHeights = [:]
        grabOffset = .zero
        stopAutoScroll()
        if cursorPushed {
            NSCursor.pop()
            cursorPushed = false
        }
        if let monitor = escMonitor {
            NSEvent.removeMonitor(monitor)
            escMonitor = nil
        }
        if let monitor = flagsMonitor {
            NSEvent.removeMonitor(monitor)
            flagsMonitor = nil
        }
    }

    /// Esc 또는 끌기 취소. 원래 자리로 돌아가는 애니메이션과 함께 끝낸다. 모델은 바뀌지 않는다.
    func cancel() {
        guard drag != nil else { return }
        drag?.cancel()
        withAnimation(settleAnimation) { end() }
    }

    // MARK: 그리기 도우미

    /// 화면에 그릴 칸. 끄는 중이 아니면 ids 그대로다. nil은 빈 칸.
    func slotIDs(for list: SourceList, ids: [SourceID]) -> [SourceID?] {
        guard let drag else { return ids.map { $0 } }
        return drag.slots(for: list, ids: ids)
    }

    /// 다른 상자의 자리 위에 있는지(바탕을 진하게).
    /// 원래 상자에 점선 빈 칸을 둘지. 복제 중에는 원래 타일이 그대로 있으므로 두지 않는다.
    func placeholder(in list: SourceList) -> SourceID? {
        guard let drag, drag.origin == list, !drag.copy else { return nil }
        return drag.id
    }

    func isHighlighted(_ list: SourceList) -> Bool {
        guard let drag, case let .slot(target, _) = drag.target else { return false }
        return target == list && list != drag.origin
    }

    /// 꽉 찬 상자 위에 있는지(「6/6」을 붉게).
    func isRefused(_ list: SourceList) -> Bool {
        guard let drag, case let .refused(target) = drag.target else { return false }
        return target == list
    }
}
