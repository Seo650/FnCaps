import AppKit
import FnCapsCore
import FnCapsSystem
import SwiftUI

/// P2 「키와 언어」: 머리글 + Caps 상자 + fn 상자 + 「사용 안 함」 상자(D-29, D-31, D-37, D-39).
/// 목록 밖 규칙은 「고급 > 전환」에 있다(04-14). 옮기기는 끌어 놓기(04-17, 재설계 §4)와
/// 타일 우클릭 메뉴·접근성 동작으로 한다. 시스템 드래그 API는 쓰지 않는다.
struct KeysPage: View {
    @ObservedObject var model: AppModel
    @ObservedObject var ui: SettingsUIState
    @ObservedObject private var keys: KeysPageState
    @Namespace private var dragNS
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(model: AppModel, ui: SettingsUIState) {
        self.model = model
        self.ui = ui
        self.keys = ui.keys
    }

    private var snapshot: AppSnapshot { model.snapshot }

    /// 설정창이 보이고 이 쪽이 선택됐을 때만 새 소스 알림을 지운다(D-23, D-26).
    private func absorbNew() {
        guard ui.windowVisible && ui.selectedPage == .keys else { return }
        let pending = model.snapshot.pendingNewSourceIDs
        guard !pending.isEmpty else { return }
        ui.newTagIDs.formUnion(pending)
        model.markNewSourcesSeen()
    }

    private var newIDs: Set<SourceID> { ui.newTagIDs.union(snapshot.pendingNewSourceIDs) }

    var body: some View {
        ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: DS.groupSpacing) {
                VStack(alignment: .leading, spacing: DS.s(8)) {
                    Text(verbatim: L(SettingsPage.keys.titleKey))
                        .font(DS.pageTitle)
                    Text(verbatim: L("keys.header"))
                        .font(DS.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: DS.s(12)) {
                    ringBox(.caps)
                    if snapshot.capsBlocked { capsNotes }
                    ringBox(.fn)
                    // D-46: fn 상자와 「사용 안 함」 상자 사이.
                    AssignedShortcutsBox(rows: snapshot.assignedRows,
                                         slotIDs: keys.slotIDs(for: .assigned,
                                                               ids: snapshot.assignedRows.map(\.id)),
                                         highlighted: keys.isHighlighted(.assigned),
                                         countWarning: keys.isRefused(.assigned),
                                         currentID: snapshot.currentSourceID, newIDs: newIDs, keys: keys, ui: ui,
                                         placeholderID: keys.placeholder(in: .assigned),
                                         chordText: snapshot.assignedChordText,
                                         conflictIDs: snapshot.assignedConflictIDs,
                                         typingIDs: snapshot.assignedTypingIDs,
                                         onChordTap: { startRecording($0) }) {
                        tile($0, in: .assigned)
                    }
                    .id("keys.assigned")
                    UnusedSourcesBox(rows: snapshot.unassignedRows,
                                     slotIDs: keys.slotIDs(for: .excluded, ids: snapshot.unassignedRows.map(\.id)),
                                     highlighted: keys.isHighlighted(.excluded),
                                     currentID: snapshot.currentSourceID, newIDs: newIDs, keys: keys, ui: ui,
                                     placeholderID: keys.placeholder(in: .excluded)) {
                        tile($0, in: .excluded)
                    }
                }
            }
            .overlay(alignment: .topLeading) { liftedTile }
            .simultaneousGesture(dragGesture)
            .coordinateSpace(name: "keys")
            // 같은 층의 background라 좌표계가 어긋나지 않는다(W7).
            .background(ScrollEdgeHelper(keys: keys))
            .onPreferenceChange(KeyZoneFrameKey.self) { keys.zoneFrames = $0 }
            .onPreferenceChange(RingCenterKey.self) { keys.ringCenters = $0 }
            .onPreferenceChange(TileFrameKey.self) { keys.tileFrames = $0 }
            .padding(.horizontal, DS.pageInsetH)
            .padding(.top, DS.pageInsetTop)
            .padding(.bottom, DS.s(20))
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear { absorbNew(); consumeKeysAnchor(proxy) }
        .onChange(of: ui.keysAnchor) { _, _ in consumeKeysAnchor(proxy) }
        .onReceive(model.$snapshot) { snapshot in
            absorbNew()
            // 녹화 중인 소스가 지정 목록에서 사라졌으면(다른 곳으로 옮겨짐) 녹화를 끝낸다.
            if let id = keys.recordingID, !snapshot.assignedRows.contains(where: { $0.id == id }) {
                keys.endRecording()
            }
        }
        .onReceive(ui.$windowVisible) { _ in absorbNew() }
        .onReceive(ui.$selectedPage) { _ in absorbNew() }
        // 쪽을 옮기면 녹화를 끝낸다. onChange는 처음 나타날 때는 부르지 않는다(렌더 장면 보존).
        .onChange(of: ui.selectedPage) { _, _ in
            keys.endRecording()
            keys.clearNotice()
        }
        // 설정창이 키 창 지위를 잃으면 녹화를 끝낸다(W8). 다른 창은 이 비교에 걸리지 않는다.
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { note in
            guard let window = note.object as? NSWindow,
                  window.contentViewController is NSHostingController<SettingsRootView> else { return }
            keys.endRecording()
        }
        .onAppear { applyMotionSetting() }
        .onChange(of: reduceMotion) { _, _ in applyMotionSetting() }
        .onDisappear {
            if keys.drag != nil { keys.end() }
            keys.endRecording()
            keys.clearNotice()
        }
        }
    }

    /// 다른 쪽에서 지정 단축키 상자로 올 때 한 번 스크롤하고 앵커를 지운다(HelpPage.consumeAnchor와 같은 모양).
    /// 움직임 줄이기면 빈 칸 강조를 생략한다.
    private func consumeKeysAnchor(_ proxy: ScrollViewProxy) {
        guard let anchor = ui.keysAnchor else { return }
        ui.keysAnchor = nil
        DispatchQueue.main.async {
            proxy.scrollTo(anchor, anchor: .top)
        }
        if reduceMotion {
            ui.keysChordHighlight = []
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { ui.keysChordHighlight = [] }
        }
    }

    private func ringBox(_ list: SourceList) -> some View {
        let all = rows(list)
        let key = triggerKey(list)
        let entry = key.map { snapshot.entry[$0] } ?? .next
        let entryID: SourceID?
        if case let .source(id) = entry { entryID = id } else { entryID = nil }
        return KeyRingBox(list: list, rows: all, slotIDs: keys.slotIDs(for: list, ids: all.map(\.id)),
                          frozenHeight: keys.frozenHeights[list],
                          highlighted: keys.isHighlighted(list), countWarning: keys.isRefused(list),
                          currentID: snapshot.currentSourceID, newIDs: newIDs, keys: keys,
                          placeholderID: keys.placeholder(in: list),
                          entry: entry, entryID: entryID,
                          showsEntryControl: true,
                          entryControlDisabled: keys.drag != nil,
                          onEntry: { if let key { model.setEntry(key, $0) } }) {
            tile($0, in: list)
        }
    }

    /// Caps·fn 목록을 엔진의 키 값으로 옮긴다. 지정·사용 안 함은 진입 언어가 없다(D-04).
    private func triggerKey(_ list: SourceList) -> TriggerKey? {
        switch list {
        case .caps: return .caps
        case .fn: return .fn
        default: return nil
        }
    }

    // MARK: 끌어 놓기(재설계 §4)

    /// 놓기·취소 애니메이션. 동작 줄이기가 켜지면 미끄러짐 대신 0.15초 페이드.
    private var settleAnimation: Animation {
        reduceMotion ? .easeInOut(duration: 0.15) : .spring(response: 0.3, dampingFraction: 0.8)
    }

    /// 고리 위 자리 열기·닫기, 다른 상자 바탕(§4). 동작 줄이기면 즉시 배치.
    private var slotAnimation: Animation? {
        reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.85)
    }

    private func applyMotionSetting() {
        keys.settleAnimation = settleAnimation
        keys.slotAnimation = slotAnimation
    }

    private var liftAnimation: Animation {
        reduceMotion ? .easeInOut(duration: 0.15) : .spring(response: 0.25, dampingFraction: 0.8)
    }

    private var counts: [SourceList: Int] {
        [.caps: snapshot.capsRows.count, .fn: snapshot.fnRows.count,
         .assigned: snapshot.assignedRows.count, .excluded: snapshot.unassignedRows.count]
    }

    /// 잡은 점 아래의 타일과 그 목록·자리(보이는 소스 기준).
    private func tileHit(at point: CGPoint) -> (id: SourceID, list: SourceList, index: Int)? {
        guard let key = keys.tileFrames.first(where: { $0.value.contains(point) })?.key,
              let index = rows(key.list).firstIndex(where: { $0.id == key.id }) else { return nil }
        return (key.id, key.list, index)
    }

    /// origin 밖에서 이 소스가 든 엔진 상자(복제).
    private func present(_ id: SourceID, besides origin: SourceList) -> Set<SourceList> {
        Set([SourceList.caps, .fn, .assigned].filter { $0 != origin && rows($0).contains(where: { $0.id == id }) })
    }

    /// 쪽 전체에 건 한 제스처. 타일마다 걸면 잡은 타일이 슬롯에서 빠질 때 제스처가 끊긴다.
    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .named("keys"))
            .onChanged { value in
                if keys.canBeginInThisGesture {
                    guard let hit = tileHit(at: value.startLocation) else { return }
                    withAnimation(liftAnimation) {
                        // ⌥를 누른 채 시작하면 복제다(Finder 관례). 끄는 중에도 ⌥로 바꿀 수 있다.
                        keys.begin(id: hit.id, origin: hit.list, index: hit.index,
                                   at: value.startLocation, counts: counts,
                                   present: present(hit.id, besides: hit.list),
                                   copy: NSEvent.modifierFlags.contains(.option))
                    }
                }
                keys.move(to: value.location, counts: counts)
            }
            .onEnded { _ in drop() }
    }

    /// 놓기. 끌기 경로의 모델 반영은 여기 한 곳, 한 번뿐이다(T-04-51).
    private func drop() {
        defer { keys.onGestureEnded() }
        guard let drag = keys.drag else { return }  // Esc로 이미 취소됨
        let origin = drag.origin
        switch keys.finish() {
        case let .move(id, list, index):
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
            let hadChord = snapshot.assignedChordText[id] != nil
            withAnimation(settleAnimation) {
                // 지정·사용 안 함 상자는 줄 상자라 끝에 넣는다. 원래 상자의 그 칸만 옮긴다(복제는 그대로).
                let ring = list == .caps || list == .fn
                model.moveSource(id: id, from: origin, to: list, at: ring ? index : nil)
                keys.end()
            }
            // 다른 상자에서 지정 상자로 들어오면 바로 녹화한다(D-46). 지정 상자 안 재배치는 녹화하지 않는다(W3).
            // 이미 단축키가 있는 복제와 합쳐졌으면 다시 녹화하지 않는다.
            if list == .assigned, origin != .assigned, !hadChord,
               snapshot.assignedRows.contains(where: { $0.id == id }) {
                startRecording(id)
            }
        case let .copy(id, list, index):
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
            withAnimation(settleAnimation) {
                model.copySource(id: id, to: list, at: list == .assigned ? nil : index)
                keys.end()
            }
            if list == .assigned, snapshot.assignedRows.contains(where: { $0.id == id }) {
                startRecording(id)
            }
        case .none:
            // 제자리, 꽉 찬 상자, 상자 밖: 원래 자리로 돌아간다. 모델은 바뀌지 않는다.
            withAnimation(settleAnimation) { keys.end() }
        }
    }

    private func row(for id: SourceID) -> SourceRow? {
        (snapshot.capsRows + snapshot.fnRows + snapshot.assignedRows + snapshot.unassignedRows)
            .first(where: { $0.id == id })
    }

    /// 포인터를 따라다니는 떠오른 타일. 놓으면 matchedGeometryEffect로 새 자리(또는 원래 자리)로 미끄러진다.
    @ViewBuilder
    private var liftedTile: some View {
        if let drag = keys.drag, let row = row(for: drag.id) {
            SourceTile(row: row, style: drag.origin == .excluded ? .unused : .normal,
                       isCurrent: snapshot.currentSourceID == drag.id, isNew: newIDs.contains(drag.id),
                       lifted: true)
                .modifier(DragMatch(id: liftedKey(drag), namespace: dragNS, enabled: !reduceMotion))
                .position(x: keys.pointer.x - keys.grabOffset.width,
                          y: keys.pointer.y - keys.grabOffset.height)
                .transition(reduceMotion ? .opacity
                            : .asymmetric(insertion: .scale(scale: 1 / 1.08), removal: .opacity))
                .allowsHitTesting(false)
                .accessibilityHidden(true)
                .zIndex(10)
        }
    }

    /// 떠오른 타일을 놓일 자리의 타일과 묶는다. 옮기기는 대상(없으면 원래) 상자, 복제는 다른 대상 상자일 때만.
    /// 복제 중 원래 상자의 타일은 그대로 보이므로 같은 정체로 묶지 않는다(nil).
    private func liftedKey(_ drag: FnCapsCore.DragSession) -> TileKey? {
        if case let .slot(list, _) = drag.target, list != drag.origin || !drag.copy {
            return TileKey(list: list, id: drag.id)
        }
        return drag.copy ? nil : TileKey(list: drag.origin, id: drag.id)
    }

    /// Caps 상자 바로 아래 안내(다른 매핑이 Caps를 쓸 때만). Control+Space 안내는 머리글에 합쳤다.
    private var capsNotes: some View {
        note(L("keys.caps.blocked"))
        .padding(.horizontal, DS.s(4))
        .padding(.top, DS.s(-4))
    }

    private func note(_ text: String) -> some View {
        Text(verbatim: text)
            .font(DS.caption)
            .foregroundStyle(.secondary)
            .lineSpacing(DS.s(2))
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: 타일

    private func rows(_ list: SourceList) -> [SourceRow] {
        switch list {
        case .caps: return snapshot.capsRows
        case .fn: return snapshot.fnRows
        case .assigned: return snapshot.assignedRows
        case .excluded: return snapshot.unassignedRows
        }
    }

    /// 보이는 소스가 6개면 그 목록으로 옮길 수 없다(D-30). Caps·fn·지정 세 상자에만 상한이 있다.
    /// 모델도 거절한다(04-10).
    private func isFull(_ list: SourceList) -> Bool {
        list != .excluded && rows(list).count >= KeyLists.maxPerKey
    }

    /// 타일 하나의 옮기기 항목. 메뉴와 접근성 동작이 같은 표를 쓴다.
    /// 「~로 옮기기」는 이 상자의 칸만 옮기고, 「~에도 넣기」는 복제한다(2026-11-11).
    private struct TileMoves {
        let ringTile: Bool
        let assignedTile: Bool
        let canEarlier: Bool
        let canLater: Bool
        let other: SourceList
        let canOther: Bool
        let canCopyOther: Bool
        let canToAssigned: Bool
        let canCopyAssigned: Bool
        let canAddCaps: Bool
        let canAddFn: Bool
        let canCopyCaps: Bool
        let canCopyFn: Bool
        let canAddToAssigned: Bool
        let hasChord: Bool

        var otherKey: String { other == .fn ? "keys.move.toFn" : "keys.move.toCaps" }
        var copyOtherKey: String { other == .fn ? "keys.copy.toFn" : "keys.copy.toCaps" }
    }

    private func contains(_ list: SourceList, _ id: SourceID) -> Bool {
        rows(list).contains(where: { $0.id == id })
    }

    /// 옮기기: 꽉 찼어도 이미 복제가 있으면 합쳐지므로 된다. 복제: 이미 있거나 꽉 찼으면 안 된다.
    private func canMove(_ id: SourceID, to list: SourceList) -> Bool { contains(list, id) || !isFull(list) }
    private func canCopy(_ id: SourceID, to list: SourceList) -> Bool { !contains(list, id) && !isFull(list) }

    private func moves(in list: SourceList, id: SourceID, index: Int, count: Int) -> TileMoves {
        let ringTile = list == .caps || list == .fn
        let assignedTile = list == .assigned
        let unusedTile = list == .excluded
        let other: SourceList = list == .caps ? .fn : .caps
        return TileMoves(
            ringTile: ringTile,
            assignedTile: assignedTile,
            canEarlier: ringTile && index > 0,
            canLater: ringTile && index < count - 1,
            other: other,
            canOther: ringTile && canMove(id, to: other),
            canCopyOther: ringTile && canCopy(id, to: other),
            canToAssigned: ringTile && canMove(id, to: .assigned),
            canCopyAssigned: ringTile && canCopy(id, to: .assigned),
            canAddCaps: !ringTile && canMove(id, to: .caps),
            canAddFn: !ringTile && canMove(id, to: .fn),
            canCopyCaps: assignedTile && canCopy(id, to: .caps),
            canCopyFn: assignedTile && canCopy(id, to: .fn),
            canAddToAssigned: unusedTile && !isFull(.assigned),
            hasChord: assignedTile && snapshot.assignedChordText[id] != nil)
    }

    private func tile(_ row: SourceRow, in list: SourceList) -> AnyView {
        let id = row.id
        let all = rows(list)
        let index = all.firstIndex(where: { $0.id == id }) ?? 0
        let count = all.count
        let isCurrent = snapshot.currentSourceID == id
        let isNew = newIDs.contains(id)
        let m = moves(in: list, id: id, index: index, count: count)
        let key = TileKey(list: list, id: id)

        var label = row.name
        if isCurrent { label += ", " + L("keys.tile.current") }
        if isNew { label += ", " + L("keys.newTag") }
        // V-9: 진입 언어 타일은 「한국어, 진입 언어」로 읽는다(D-07). 우클릭 메뉴에는 넣지 않는다(D-06).
        let isEntry = triggerKey(list).map { snapshot.entry[$0] == .source(id) } ?? false
        let tileLabel = isEntry ? LF("keys.entry.tileA11y", label) : label

        let earlier = { model.nudgeSource(id: id, in: list, by: -1) }
        let later = { model.nudgeSource(id: id, in: list, by: 1) }
        let toOther = { model.moveSource(id: id, from: list, to: m.other) }
        let copyOther = { model.copySource(id: id, to: m.other) }
        // 지금 소스여도 전환하지 않는다(M4). 이 상자에서만 뺀다.
        let remove = { model.removeSource(id: id, from: list) }
        let addCaps = { model.moveSource(id: id, from: list, to: .caps) }
        let addFn = { model.moveSource(id: id, from: list, to: .fn) }
        let copyCaps = { model.copySource(id: id, to: .caps) }
        let copyFn = { model.copySource(id: id, to: .fn) }
        // 지정 상자로 들어간 뒤 단축키가 없으면 바로 녹화한다(D-46). 꽉 차 거절되면 녹화하지 않는다.
        let recordIfNeeded = {
            if snapshot.assignedRows.contains(where: { $0.id == id }),
               snapshot.assignedChordText[id] == nil { startRecording(id) }
        }
        let toAssigned = {
            model.moveSource(id: id, from: list, to: .assigned)
            recordIfNeeded()
        }
        let copyAssigned = {
            model.copySource(id: id, to: .assigned)
            recordIfNeeded()
        }
        let changeChord = { startRecording(id) }
        let clearChord = { model.setAssignedChord(nil, for: id) }

        let position = LF("keys.tile.position", index + 1, count)
        let value: String
        if m.assignedTile {
            let chord = snapshot.assignedChordText[id].map { LF("keys.assigned.value", $0) }
                ?? L("keys.assigned.noShortcut")
            value = chord + ", " + position
        } else {
            value = position
        }

        let view = SourceTile(row: row, style: m.ringTile || m.assignedTile ? .normal : .unused,
                              isCurrent: isCurrent, isNew: isNew,
                              hovered: keys.drag == nil && keys.isHovered(id, in: list))
            .modifier(DragMatch(id: key, namespace: dragNS, enabled: !reduceMotion))
            .background(GeometryReader { geo in
                Color.clear.preference(key: TileFrameKey.self, value: [key: geo.frame(in: .named("keys"))])
            })
            .contentShape(Rectangle())
            .onHover { inside in
                if keys.drag != nil { return }
                if inside {
                    keys.hoveredID = id
                    keys.hoveredList = list
                    keys.hoverStarts[id] = Date()
                } else {
                    if keys.isHovered(id, in: list) {
                        keys.hoveredID = nil
                        keys.hoveredList = nil
                    }
                    // 마우스를 올렸다 떼면 「새로 추가됨」 점을 지운다(04.1 UAT R1).
                    // 스크롤로 타일이 커서 아래를 지나갈 때는 지우지 않도록 0.3초 이상 머문 경우만(리뷰 WR-02).
                    if let start = keys.hoverStarts.removeValue(forKey: id),
                       Date().timeIntervalSince(start) >= KeysPageState.newTagDwell {
                        ui.newTagIDs.remove(id)
                    }
                }
            }
        // 긴 수식은 타입 검사가 오래 걸려 단계마다 AnyView로 끊는다.
        let withMenu = AnyView(view.contextMenu {
                if m.ringTile {
                    Button(L("keys.moveEarlier"), action: earlier).disabled(!m.canEarlier)
                    Button(L("keys.moveLater"), action: later).disabled(!m.canLater)
                    Divider()
                    Button(L(m.otherKey), action: toOther).disabled(!m.canOther)
                    Button(L("keys.move.toAssigned"), action: toAssigned).disabled(!m.canToAssigned)
                    Divider()
                    Button(L(m.copyOtherKey), action: copyOther).disabled(!m.canCopyOther)
                    Button(L("keys.copy.toAssigned"), action: copyAssigned).disabled(!m.canCopyAssigned)
                    Divider()
                    Button(L("keys.remove"), action: remove)
                } else if m.assignedTile {
                    Button(L(m.hasChord ? "keys.assigned.change" : "keys.assigned.set"),
                           action: changeChord)
                    if m.hasChord {
                        Button(L("keys.assigned.clear"), action: clearChord)
                    }
                    Divider()
                    Button(L("keys.move.toCaps"), action: addCaps).disabled(!m.canAddCaps)
                    Button(L("keys.move.toFn"), action: addFn).disabled(!m.canAddFn)
                    Divider()
                    Button(L("keys.copy.toCaps"), action: copyCaps).disabled(!m.canCopyCaps)
                    Button(L("keys.copy.toFn"), action: copyFn).disabled(!m.canCopyFn)
                    Divider()
                    Button(L("keys.remove"), action: remove)
                } else {
                    Button(L("keys.addToCaps"), action: addCaps).disabled(!m.canAddCaps)
                    Button(L("keys.addToFn"), action: addFn).disabled(!m.canAddFn)
                    Button(L("keys.addToAssigned"), action: toAssigned).disabled(!m.canAddToAssigned)
                }
            })
        let moveActions = AnyView(withMenu
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(tileLabel)
            .accessibilityValue(value)
            // 비활성 항목은 넣지 않는다.
            .accessibilityAction(named: L("keys.moveEarlier"), if: m.canEarlier, earlier)
            .accessibilityAction(named: L("keys.moveLater"), if: m.canLater, later)
            .accessibilityAction(named: L(m.otherKey), if: m.canOther, toOther)
            .accessibilityAction(named: L("keys.move.toAssigned"), if: m.canToAssigned, toAssigned)
        )
        let copyActions = AnyView(moveActions
            .accessibilityAction(named: L(m.copyOtherKey), if: m.canCopyOther, copyOther)
            .accessibilityAction(named: L("keys.copy.toAssigned"), if: m.canCopyAssigned, copyAssigned)
            .accessibilityAction(named: L(m.hasChord ? "keys.assigned.change" : "keys.assigned.set"),
                                 if: m.assignedTile, changeChord)
            .accessibilityAction(named: L("keys.assigned.clear"), if: m.hasChord, clearChord)
            .accessibilityAction(named: L("keys.remove"), if: m.ringTile || m.assignedTile, remove)
        )
        return AnyView(copyActions
            .accessibilityAction(named: L(m.assignedTile ? "keys.move.toCaps" : "keys.addToCaps"),
                                 if: m.canAddCaps, addCaps)
            .accessibilityAction(named: L(m.assignedTile ? "keys.move.toFn" : "keys.addToFn"),
                                 if: m.canAddFn, addFn)
            .accessibilityAction(named: L("keys.copy.toCaps"), if: m.canCopyCaps, copyCaps)
            .accessibilityAction(named: L("keys.copy.toFn"), if: m.canCopyFn, copyFn)
            .accessibilityAction(named: L("keys.addToAssigned"), if: m.canAddToAssigned, toAssigned))
    }

    // MARK: 녹화(D-46)

    /// 지정 소스 녹화를 시작한다. 처리 묶음은 이 뷰가 만들고 상태 객체는 모델을 부르지 않는다.
    private func startRecording(_ id: SourceID) {
        let name: (SourceID) -> String = { target in row(for: target)?.name ?? target }
        keys.startRecording(id, handlers: KeysPageState.RecordHandlers(
            validate: { keyCode, flags in model.validateChord(keyCode: keyCode, flags: flags, for: id) },
            commit: { chord in model.setAssignedChord(chord, for: id) },
            began: { model.startShortcutRecording() },
            ended: { model.endShortcutRecording() },
            announce: { announce($0) },
            message: { refusal in
                switch refusal {
                case .noModifier: return L("keys.assigned.refused.noModifier")
                case .notAKey: return L("keys.assigned.refused.notAKey")
                }
            },
            format: { chord in ChordFormatter.text(chord, keyName: KeyNames.character) },
            takenNotice: { source in LF("keys.assigned.taken", name(source)) },
            sourceName: name))
    }

    /// VoiceOver 알림. 녹화 시작·저장·거절을 소리로 알린다(연구 §7-3).
    private func announce(_ text: String) {
        NSAccessibility.post(
            element: NSApp as Any, notification: .announcementRequested,
            userInfo: [.announcement: text,
                       .priority: NSAccessibilityPriorityLevel.high.rawValue])
    }
}

/// 타일 프레임(좌표계 "keys"). 잡은 타일을 찾고 잡은 오프셋을 잴 때 쓴다.
struct TileFrameKey: PreferenceKey {
    static var defaultValue: [TileKey: CGRect] = [:]
    static func reduce(value: inout [TileKey: CGRect], nextValue: () -> [TileKey: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

/// 떠오른 타일과 고리 타일을 같은 정체로 묶는다. 동작 줄이기가 켜지면 묶지 않는다(페이드만).
private struct DragMatch: ViewModifier {
    let id: TileKey?
    let namespace: Namespace.ID
    let enabled: Bool

    func body(content: Content) -> some View {
        if enabled, let id {
            content.matchedGeometryEffect(id: id, in: namespace)
        } else {
            content
        }
    }
}

private extension View {
    /// enabled일 때만 이름 있는 접근성 동작을 붙인다.
    @ViewBuilder
    func accessibilityAction(named title: String, if enabled: Bool,
                             _ action: @escaping () -> Void) -> some View {
        if enabled {
            accessibilityAction(named: Text(verbatim: title), action)
        } else {
            self
        }
    }
}
