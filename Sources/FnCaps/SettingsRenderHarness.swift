#if DEBUG
import AppKit
import FnCapsCore
import SwiftUI

/// debug 전용: 설정창 장면을 화면 밖에서 2배 PNG로 그린다. AppModel.start()를 부르지 않으므로
/// 키 탭, 권한, 키 매핑, 설정 쓰기에 닿지 않는다. release 빌드에는 들어가지 않는다.
/// 창 버튼(닫기 등)은 창이 그리므로 PNG에 없다. 화면 밖 렌더는 비활성 창 모양으로 나온다(U15).
enum SettingsRenderHarness {
    struct Scene {
        let name: String
        let page: SettingsPage
        let dark: Bool
        var height: CGFloat = DS.s(675)
        let fixture: (inout AppSnapshot) -> Void
        var setup: (SettingsUIState, UpdateController, ReportController) -> Void = { _, _, _ in }
        /// 첫 배치 뒤 차례로 부를 단계. 단계마다 다시 배치해 영역 좌표가 채워진 뒤에 다음 단계를 한다(04-17 끌기 장면).
        var postLayout: [(SettingsUIState) -> Void] = []
        /// 사이드바 「처음 설정 n/5」 행을 보일 때의 메모리 저장 단계. nil이면 행이 없다.
        var onboardingStep: Int? = nil
    }

    static func run(outputDir: URL) -> Int32 {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        do {
            try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        } catch {
            fail("출력 폴더를 만들 수 없습니다: \(error)")
            return 1
        }
        let lang = Bundle.main.preferredLocalizations.first ?? "en"
        let fx = Fixtures(lang: lang)
        var scenes = makeScenes(fx)
        var onboarding = onboardingScenes(fx)
        var important = importantScenes(lang: lang)
        if let only = ProcessInfo.processInfo.environment["FNCAPS_RENDER_ONLY"], !only.isEmpty {
            let names = Set(only.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) })
            scenes = scenes.filter { names.contains($0.name) }
            onboarding = onboarding.filter { names.contains($0.name) }
            important = important.filter { names.contains($0.name) }
            // 설정창·처음 설정·중요 업데이트 장면을 모두 걸러 낸 뒤에야 실패로 본다.
            if scenes.isEmpty && onboarding.isEmpty && important.isEmpty {
                fail("FNCAPS_RENDER_ONLY에 맞는 장면이 없습니다: \(only)")
                return 1
            }
        }

        let model = AppModel()
        // 렌더는 사용자 defaults와 네트워크를 쓰지 않는다. 상태는 장면마다 debugSet으로 정한다.
        let updates = UpdateController(defaults: nil, fetch: { _ in throw URLError(.notConnectedToInternet) })
        // 「문제 알리기」 쪽도 defaults·네트워크를 쓰지 않는다. 미리보기는 장면마다 고정 문자열로 넣는다.
        let reports = ReportController(defaults: nil, fetch: { _ in throw URLError(.notConnectedToInternet) })
        var written: [String] = []
        var failed = false
        for scene in scenes {
            var s = model.snapshot
            scene.fixture(&s)
            model.debugSnapshotOverride = s
            let ui = SettingsUIState()
            // KeysPage가 새 소스 알림을 지우며 defaults를 쓰지 않도록 창은 보이지 않는 상태로 둔다(T-04-41).
            ui.windowVisible = false
            ui.selectedPage = scene.page
            // 처음 설정 진행은 장면마다 메모리 저장 상태로 새로 둔다(사용자 defaults에 쓰지 않는다, T-04.4-04).
            let onboarding = OnboardingUIState()
            if let step = scene.onboardingStep { onboarding.firstRun.setStep(step) }
            updates.debugSet(phase: .done(.upToDate(latest: UpdateController.currentVersion)),
                             lastChecked: fixedCheckTime)
            // 쪽마다 미리보기가 준비된 대기 상태에서 시작한다. 신고 장면은 setup에서 덮어쓴다.
            reports.debugSet(phase: .idle, preview: reportPreviewFixture)
            scene.setup(ui, updates, reports)
            let file = "\(lang)-\(scene.name).png"
            if render(SettingsRootView(model: model, ui: ui, onboarding: onboarding,
                                       openOnboarding: {}, updates: updates, reports: reports),
                      ui: ui, scene: scene,
                      to: outputDir.appendingPathComponent(file)) {
                written.append(file)
            } else {
                failed = true
            }
        }
        // 처음 설정 창은 폭이 설정 창과 다르고(600) 뷰가 바탕을 깐다. 설정 창 장면 뒤에 그려 같은 목록에 이어 적는다.
        for scene in onboarding {
            let file = "\(lang)-\(scene.name).png"
            if renderOnboarding(scene, model: model, to: outputDir.appendingPathComponent(file)) {
                written.append(file)
            } else {
                failed = true
            }
        }
        // 중요 업데이트 창은 설정창과 폭이 다르다(DS.s(420)). 따로 그려 같은 목록에 이어 적는다.
        for scene in important {
            let file = "\(lang)-\(scene.name).png"
            if renderImportant(scene, to: outputDir.appendingPathComponent(file)) {
                written.append(file)
            } else {
                failed = true
            }
        }
        let manifest = outputDir.appendingPathComponent("manifest-\(lang).txt")
        do {
            try (written.map { $0 + "\n" }.joined()).write(to: manifest, atomically: true, encoding: .utf8)
        } catch {
            fail("manifest 쓰기 실패: \(error)")
            failed = true
        }
        return failed ? 1 : 0
    }

    private static func render(_ root: SettingsRootView, ui: SettingsUIState, scene: Scene, to url: URL) -> Bool {
        // 설정 창은 늘 690×675(×DS.scale)이고 처음 설정은 별도 하니스가 그린다.
        let size = NSSize(width: DS.s(690), height: scene.height)
        let view = NSHostingView(rootView: root)
        view.frame = NSRect(origin: .zero, size: size)
        view.appearance = NSAppearance(named: scene.dark ? .darkAqua : .aqua)
        settle(view)
        for step in scene.postLayout {
            step(ui)
            settle(view)
        }

        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        else {
            fail("렌더 실패(비트맵 없음): \(scene.name)")
            return false
        }
        rep.size = size
        view.cacheDisplay(in: view.bounds, to: rep)
        guard rep.pixelsWide >= Int(DS.s(690) * 2),  // 설정 창 폭(690)
              let png = rep.representation(using: .png, properties: [:]), !png.isEmpty
        else {
            fail("렌더 실패(PNG 비었음 또는 폭 부족): \(scene.name)")
            return false
        }
        do {
            try png.write(to: url)
            return true
        } catch {
            fail("쓰기 실패: \(scene.name) \(error)")
            return false
        }
    }

    // MARK: 중요 업데이트 창(REL-05, 06-02)

    private struct ImportantScene {
        let name: String
        let dark: Bool
        let phase: UpdateController.Phase
        let offerText: String
    }

    private static func importantScenes(lang: String) -> [ImportantScene] {
        let offered = offeredText(lang: lang)
        let available = UpdateController.Phase.done(
            .available(version: "1.1", url: ExternalLinks.releasesLatest))
        return [
            ImportantScene(name: "update-important-offered-light", dark: false,
                           phase: available, offerText: offered),
            ImportantScene(name: "update-important-offered-dark", dark: true,
                           phase: available, offerText: offered),
            ImportantScene(name: "update-important-long-light", dark: false,
                           phase: available, offerText: longText),
            ImportantScene(name: "update-important-working", dark: false,
                           phase: .downloading, offerText: offered),
            ImportantScene(name: "update-important-failed", dark: false,
                           phase: .installFailed(.download), offerText: offered),
        ]
    }

    /// 렌더 전용 고정 안내 글(약 100~150자). `.lproj`에 넣지 않는다. 없는 언어는 영어로 되돌린다.
    private static func offeredText(lang: String) -> String {
        switch lang {
        case "ko":
            return "잠자기에서 깨어난 뒤 FnCaps를 다시 시작할 때까지 Caps Lock 전환이 멈출 수 있던 문제를 고쳤습니다. 설치하면 해결됩니다."
        case "fr":
            return "Corrigé : après le réveil du Mac, le changement avec Verr. Maj pouvait cesser de fonctionner jusqu’au redémarrage de FnCaps. Cette mise à jour règle le problème."
        default:
            return "Fixed an issue where switching with Caps Lock could stop working after your Mac woke from sleep until FnCaps was restarted. This update resolves it."
        }
    }

    /// 4000자 상한(D-19-6)을 채운 고정 영어 글. 상자가 DS.s(160)에 머물고 안에서 스크롤하는지 본다.
    private static let longText: String = {
        let sentence = "This long note checks that the note box scrolls inside and the window stops growing at the height limit. "
        var text = ""
        while text.count < ImportantNotice.maxLength + 200 { text += sentence }
        return ImportantNotice.clean(text)
    }()

    private static func renderImportant(_ scene: ImportantScene, to url: URL) -> Bool {
        let updates = UpdateController(defaults: nil, fetch: { _ in throw URLError(.notConnectedToInternet) })
        updates.debugSet(phase: scene.phase, lastChecked: fixedCheckTime)
        let offer = ImportantOffer(version: "1.1", text: scene.offerText)
        // 실제 창은 NSWindow가 바탕을 칠한다. 화면 밖 렌더에는 창이 없으므로 같은 바탕을 깔아 준다.
        let content = ImportantUpdateView(updates: updates, offer: offer, close: {})
            .background(Color(nsColor: .windowBackgroundColor))
        let view = NSHostingView(rootView: content)
        let width = DS.s(420)
        view.frame = NSRect(x: 0, y: 0, width: width, height: DS.s(300))
        view.appearance = NSAppearance(named: scene.dark ? .darkAqua : .aqua)
        settle(view)
        let size = NSSize(width: width, height: max(view.fittingSize.height, DS.s(1)))
        view.frame = NSRect(origin: .zero, size: size)
        settle(view)

        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        else {
            fail("렌더 실패(비트맵 없음): \(scene.name)")
            return false
        }
        rep.size = size
        view.cacheDisplay(in: view.bounds, to: rep)
        guard rep.pixelsWide >= Int(DS.s(420) * 2),
              let png = rep.representation(using: .png, properties: [:]), !png.isEmpty
        else {
            fail("렌더 실패(PNG 비었음 또는 폭 부족): \(scene.name)")
            return false
        }
        do {
            try png.write(to: url)
            return true
        } catch {
            fail("쓰기 실패: \(scene.name) \(error)")
            return false
        }
    }

    // MARK: 처음 설정 창(08.1-03)

    /// 처음 설정 뷰(`OnboardingView`, 순수 뷰)를 창 크기 DS.s(600)×DS.s(500)으로 그린다.
    /// 진행 상태는 메모리 저장(`OnboardingUIState()`)이라 사용자 defaults에 쓰지 않는다(T-08.1-11, T-04.4-04).
    private struct OnboardingScene {
        let name: String
        let dark: Bool
        let step: Int
        var branch = false
        /// 실제 창은 500이다. 스크롤 밖에 있는 5단계 목록 전체를 볼 때만 늘린다.
        var height: CGFloat = 500
        let fixture: (inout AppSnapshot) -> Void
    }

    private static func onboardingScenes(_ fx: Fixtures) -> [OnboardingScene] {
        [
            OnboardingScene(name: "onboarding-1", dark: false, step: 1, fixture: fx.base),
            OnboardingScene(name: "onboarding-1-dark", dark: true, step: 1, fixture: fx.base),
            OnboardingScene(name: "onboarding-2", dark: false, step: 2, fixture: fx.permission),
            OnboardingScene(name: "onboarding-2-dark", dark: true, step: 2, fixture: fx.permission),
            OnboardingScene(name: "onboarding-2-granted", dark: false, step: 2, fixture: fx.base),
            OnboardingScene(name: "onboarding-2-conflict", dark: false, step: 2, fixture: fx.detected),
            OnboardingScene(name: "onboarding-2-stuck", dark: false, step: 2, fixture: fx.stuck),
            OnboardingScene(name: "onboarding-2-lost", dark: false, step: 2, fixture: fx.lost),
            OnboardingScene(name: "onboarding-3", dark: false, step: 3, fixture: fx.globe),
            OnboardingScene(name: "onboarding-3-ok", dark: false, step: 3, fixture: fx.base),
            OnboardingScene(name: "onboarding-4", dark: false, step: 4, fixture: fx.base),
            OnboardingScene(name: "onboarding-4-dark", dark: true, step: 4, fixture: fx.base),
            OnboardingScene(name: "onboarding-5", dark: false, step: 5, fixture: { fx.help(count: 4, &$0) }),
            OnboardingScene(name: "onboarding-5-dark", dark: true, step: 5, fixture: { fx.help(count: 4, &$0) }),
            OnboardingScene(name: "onboarding-5-single", dark: false, step: 5, fixture: { fx.help(count: 1, &$0) }),
            // 5단계 목록 전체. 키 그림이 폭 안에 들어오고 잘리지 않는지 보는 용도다.
            OnboardingScene(name: "onboarding-5-full", dark: false, step: 5, height: 1750,
                            fixture: { fx.help(count: 4, &$0) }),
            OnboardingScene(name: "onboarding-5-custom", dark: false, step: 5, branch: true,
                            fixture: { fx.help(count: 4, &$0) }),
            OnboardingScene(name: "onboarding-5-custom-dark", dark: true, step: 5, branch: true,
                            fixture: { fx.help(count: 4, &$0) }),
        ]
    }

    private static func renderOnboarding(_ scene: OnboardingScene, model: AppModel, to url: URL) -> Bool {
        var s = model.snapshot
        scene.fixture(&s)
        model.debugSnapshotOverride = s
        let ui = OnboardingUIState()
        ui.setupStep = scene.step
        ui.setupBranch = scene.branch
        let content = OnboardingView(model: model, ui: ui, close: {}, finish: {})
        let size = NSSize(width: DS.s(600), height: DS.s(scene.height))
        let view = NSHostingView(rootView: content)
        view.frame = NSRect(origin: .zero, size: size)
        view.appearance = NSAppearance(named: scene.dark ? .darkAqua : .aqua)
        settle(view)

        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        else {
            fail("렌더 실패(비트맵 없음): \(scene.name)")
            return false
        }
        rep.size = size
        view.cacheDisplay(in: view.bounds, to: rep)
        guard rep.pixelsWide >= Int(DS.s(600) * 2),
              let png = rep.representation(using: .png, properties: [:]), !png.isEmpty
        else {
            fail("렌더 실패(PNG 비었음 또는 폭 부족): \(scene.name)")
            return false
        }
        do {
            try png.write(to: url)
            return true
        } catch {
            fail("쓰기 실패: \(scene.name) \(error)")
            return false
        }
    }

    /// 배치하고, 선호값으로 전달되는 좌표가 한 번 더 돌게 한 뒤 다시 배치한다.
    private static func settle(_ view: NSView) {        view.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        view.layoutSubtreeIfNeeded()
    }

    // MARK: 끌기 장면(04-17)

    /// 실제 제스처 없이 좌표로 끌기 상태를 만든다. 커서·Esc 감시는 붙이지 않고(interactive false), 애니메이션은 끈다.
    /// target은 영역 좌표(keys 상태)로 포인터 위치를 정한다. 모델은 부르지 않는다.
    private static func dragSteps(id: SourceID, from origin: SourceList, index: Int,
                                  counts: [SourceList: Int],
                                  target: @escaping (KeysPageState) -> CGPoint?) -> [(SettingsUIState) -> Void] {
        [
            { ui in
                let keys = ui.keys
                keys.slotAnimation = nil
                keys.settleAnimation = nil
                guard let frame = keys.tileFrames[TileKey(list: origin, id: id)] else {
                    fail("끌기 장면: 타일 프레임이 없습니다 \(id)")
                    return
                }
                // 타일 가운데에서 조금 오른쪽 아래를 잡는다(잡은 오프셋 확인용).
                keys.begin(id: id, origin: origin, index: index,
                           at: CGPoint(x: frame.midX + 6, y: frame.midY + 4), counts: counts, interactive: false)
            },
            { ui in
                guard let point = target(ui.keys) else {
                    fail("끌기 장면: 목표 좌표가 없습니다")
                    return
                }
                ui.keys.move(to: point, counts: counts)
            },
        ]
    }

    /// 고리 가운데에서 각도 t, 그 고리 표시 칸 수 slots의 반지름 위 점.
    private static func ringPoint(_ keys: KeysPageState, _ list: SourceList, angle t: Double, slots: Int) -> CGPoint? {
        guard let c = keys.ringCenters[list] else { return nil }
        let r = keys.frozenHeights[list].map { RingGeometry.radii(count: slots, maxBoxHeight: Double($0)) }
            ?? RingGeometry.radii(count: slots)
        return CGPoint(x: c.x + r.a * cos(t), y: c.y + r.b * sin(t))
    }

    /// 고정 확인 시각: 렌더하는 날 15:12(확정 초안 「마지막 확인 오늘 오후 3:12」).
    private static var fixedCheckTime: Date {
        Calendar.current.date(bySettingHour: 15, minute: 12, second: 0, of: Date()) ?? Date()
    }

    private static func fail(_ message: String) {
        FileHandle.standardError.write(Data((message + "\n").utf8))
    }

    // MARK: 장면

    private static func makeScenes(_ fx: Fixtures) -> [Scene] {
        [
            Scene(name: "general-light", page: .general, dark: false, fixture: fx.base),
            Scene(name: "general-dark", page: .general, dark: true, fixture: fx.base),
            Scene(name: "general-permission", page: .general, dark: false, fixture: fx.permission),
            Scene(name: "general-off", page: .general, dark: false, fixture: fx.off),
            Scene(name: "general-conflict", page: .general, dark: false, fixture: fx.capsBlocked),
            Scene(name: "general-warnings", page: .general, dark: false, fixture: fx.detectedGlobe),
            Scene(name: "general-warnings-dark", page: .general, dark: true, fixture: fx.detectedGlobe),
            Scene(name: "general-detected", page: .general, dark: false, fixture: fx.detected),
            // 04.2-07: 🌐 안내 + [자세히] 한 줄.
            Scene(name: "general-globe", page: .general, dark: false, fixture: fx.globe),
            Scene(name: "keys-light", page: .keys, dark: false, fixture: fx.base),
            Scene(name: "keys-dark", page: .keys, dark: true, fixture: fx.base),
            Scene(name: "keys-full-light", page: .keys, dark: false, fixture: fx.full),
            Scene(name: "keys-full-dark", page: .keys, dark: true, fixture: fx.full),
            Scene(name: "keys-empty", page: .keys, dark: false, fixture: fx.empty),
            // 「사용 안 함」 상자와 새 소스(주황 점, 말풍선)까지 보이는 높이.
            Scene(name: "keys-full-tall", page: .keys, dark: false, height: DS.s(820), fixture: fx.full,
                  setup: { ui, _, _ in
                      ui.keys.hoveredID = ID.arabic
                      ui.keys.hoveredList = .excluded
                  }),
            Scene(name: "keys-full-tall-dark", page: .keys, dark: true, height: DS.s(820), fixture: fx.full),
            // 04-17 끄는 중 모습(재설계 §4). 키 상자 높이가 늘므로 「사용 안 함」 상자까지 보이게 높인다.
            Scene(name: "keys-drag-reorder", page: .keys, dark: false, height: DS.s(760), fixture: fx.base,
                  postLayout: dragSteps(id: ID.korean, from: .fn, index: 0, counts: Fixtures.baseCounts) {
                      ringPoint($0, .fn, angle: 0, slots: 3)
                  }),
            Scene(name: "keys-drag-cross", page: .keys, dark: false, height: DS.s(760), fixture: fx.base,
                  postLayout: dragSteps(id: ID.abc, from: .caps, index: 0, counts: Fixtures.baseCounts) {
                      // 열린 자리가 떠오른 타일에 가리지 않게 고리 위쪽 바깥을 가리킨다(각도는 같다).
                      ringPoint($0, .fn, angle: 3 * .pi / 2, slots: 4).map { CGPoint(x: $0.x, y: $0.y - 26) }
                  }),
            Scene(name: "keys-drag-full", page: .keys, dark: false, height: DS.s(820), fixture: fx.full,
                  postLayout: dragSteps(id: ID.abc, from: .caps, index: 0, counts: Fixtures.fullCounts) {
                      ringPoint($0, .fn, angle: 0, slots: 6)
                  }),
            Scene(name: "keys-drag-unused-dark", page: .keys, dark: true, height: DS.s(760), fixture: fx.base,
                  postLayout: dragSteps(id: ID.japanese, from: .fn, index: 1, counts: Fixtures.baseCounts) {
                      $0.zoneFrames[.excluded].map { CGPoint(x: $0.midX + 60, y: $0.midY + 8) }
                  }),
            // 04.3 진입 언어(D-04, D-05, D-07, D-09). 고리 크기별 화살표와 푸터.
            Scene(name: "keys-entry-2", page: .keys, dark: false, fixture: fx.entry2),
            Scene(name: "keys-entry-2-dark", page: .keys, dark: true, fixture: fx.entry2),
            Scene(name: "keys-entry-3", page: .keys, dark: false, fixture: fx.entry3),
            Scene(name: "keys-entry-3-dark", page: .keys, dark: true, fixture: fx.entry3),
            Scene(name: "keys-entry-4", page: .keys, dark: false, fixture: fx.entry4),
            Scene(name: "keys-entry-4-dark", page: .keys, dark: true, fixture: fx.entry4),
            Scene(name: "keys-entry-6", page: .keys, dark: false, height: DS.s(820), fixture: fx.entry6),
            Scene(name: "keys-entry-6-dark", page: .keys, dark: true, height: DS.s(820), fixture: fx.entry6),
            Scene(name: "keys-entry-none", page: .keys, dark: false, fixture: fx.entryNone),
            // 진입 타일을 같은 목록 안에서 끄는 중: 화살표 숨김, 상자 높이 고정, Picker 비활성.
            Scene(name: "keys-entry-drag", page: .keys, dark: false, height: DS.s(760), fixture: fx.entry4,
                  postLayout: dragSteps(id: ID.japanese, from: .fn, index: 1, counts: Fixtures.entry4Counts) {
                      ringPoint($0, .fn, angle: 0, slots: 4)
                  }),
            // 지정 단축키 상자(D-46, 04-22). 기본 높이 장면은 Scene.height를 생략한다.
            Scene(name: "keys-assigned", page: .keys, dark: false, fixture: fx.assigned),
            Scene(name: "keys-assigned-dark", page: .keys, dark: true, fixture: fx.assigned),
            Scene(name: "keys-assigned-tall", page: .keys, dark: false, height: DS.s(860), fixture: fx.assigned),
            Scene(name: "keys-assigned-recording", page: .keys, dark: false, fixture: fx.assigned,
                  setup: { ui, _, _ in
                      ui.keys.debugRecording(id: ID.pinyin, modifiers: 0xC0000, message: nil)
                  }),
            Scene(name: "keys-assigned-refused", page: .keys, dark: false, fixture: fx.assigned,
                  setup: { ui, _, _ in
                      ui.keys.debugRecording(id: ID.pinyin, modifiers: 0,
                                             message: L("keys.assigned.refused.noModifier"))
                  }),
            Scene(name: "keys-assigned-taken", page: .keys, dark: false, fixture: fx.assigned,
                  setup: { ui, _, _ in
                      ui.keys.debugRecording(id: nil, modifiers: 0, message: nil)
                      ui.keys.debugNotice(LF("keys.assigned.taken", fx.name(ID.vietnamese)))
                  }),
            Scene(name: "keys-assigned-conflict", page: .keys, dark: false, fixture: fx.assignedConflict),
            Scene(name: "keys-assigned-typing", page: .keys, dark: false, fixture: fx.assignedTyping),
            Scene(name: "keys-drag-assigned", page: .keys, dark: false, height: DS.s(760), fixture: fx.assigned,
                  postLayout: dragSteps(id: ID.japanese, from: .fn, index: 1,
                                        counts: Fixtures.assignedCounts) {
                      $0.zoneFrames[.assigned].map { CGPoint(x: $0.midX, y: $0.midY) }
                  }),
            Scene(name: "keys-drag-assigned-full", page: .keys, dark: false, height: DS.s(760),
                  fixture: fx.assignedFull,
                  postLayout: dragSteps(id: ID.japanese, from: .fn, index: 1,
                                        counts: Fixtures.assignedFullCounts) {
                      $0.zoneFrames[.assigned].map { CGPoint(x: $0.midX, y: $0.midY) }
                  }),
            Scene(name: "keys-drag-from-assigned", page: .keys, dark: false, height: DS.s(760),
                  fixture: fx.assigned,
                  postLayout: dragSteps(id: ID.pinyin, from: .assigned, index: 0,
                                        counts: Fixtures.assignedCounts) {
                      $0.zoneFrames[.excluded].map { CGPoint(x: $0.midX + 60, y: $0.midY + 8) }
                  }),
            Scene(name: "advanced-light", page: .advanced, dark: false, fixture: fx.base),
            Scene(name: "advanced-dark", page: .advanced, dark: true, fixture: fx.base),
            Scene(name: "advanced-tall", page: .advanced, dark: false, height: DS.s(1000), fixture: fx.base),
            Scene(name: "help-light", page: .help, dark: false, height: DS.s(1400), fixture: fx.base),
            Scene(name: "help-dark", page: .help, dark: true, height: DS.s(1400), fixture: fx.base),
            Scene(name: "help-1", page: .help, dark: false, height: DS.s(1400),
                  fixture: { fx.help(count: 1, &$0) }),
            Scene(name: "help-2", page: .help, dark: false, height: DS.s(1400),
                  fixture: { fx.help(count: 2, &$0) }),
            Scene(name: "help-3", page: .help, dark: false, height: DS.s(1400),
                  fixture: { fx.help(count: 3, &$0) }),
            Scene(name: "help-4", page: .help, dark: false, height: DS.s(1400),
                  fixture: { fx.help(count: 4, &$0) }),
            Scene(name: "help-5", page: .help, dark: false, height: DS.s(1400),
                  fixture: { fx.help(count: 5, &$0) }),
            // 04.2-13 D-47·D-48: 「설정하기」의 macOS 기본 그림(최근 순서, 회전 화살표 없음).
            Scene(name: "help-macos", page: .help, dark: false, height: DS.s(1400), fixture: fx.base,
                  setup: { ui, _, _ in ui.helpSetupSegment = .macOS }),
            Scene(name: "help-macos-dark", page: .help, dark: true, height: DS.s(1400), fixture: fx.base,
                  setup: { ui, _, _ in ui.helpSetupSegment = .macOS }),
            Scene(name: "help-macos-2", page: .help, dark: false, height: DS.s(1400),
                  fixture: { fx.help(count: 2, &$0) },
                  setup: { ui, _, _ in ui.helpSetupSegment = .macOS }),
            // 고리 6칸에 가까운 수(영어 1 + 외국어 4)를 macOS 그림으로 본다.
            Scene(name: "help-macos-5", page: .help, dark: false, height: DS.s(1400),
                  fixture: { fx.help(count: 5, &$0) },
                  setup: { ui, _, _ in ui.helpSetupSegment = .macOS }),
            // 04.4 D-12: 권장 3(Caps [영어] + fn [중심] + 지정 2개)이 사용 중.
            Scene(name: "help-same", page: .help, dark: false, height: DS.s(1400),
                  fixture: { fx.helpRecommended(&$0) }),
            // 04.4 D-04·D-05·D-07·D-08: 후보 목록(후보 1~3개).
            Scene(name: "help-cand-2", page: .help, dark: false, height: DS.s(1400), fixture: { fx.help(count: 2, &$0) }),
            Scene(name: "help-cand-3", page: .help, dark: false, height: DS.s(1400), fixture: { fx.help(count: 3, &$0) }),
            Scene(name: "help-cand-4", page: .help, dark: false, height: DS.s(1400), fixture: { fx.help(count: 4, &$0) }),
            Scene(name: "help-cand-5", page: .help, dark: false, height: DS.s(1400), fixture: { fx.help(count: 5, &$0) }),
            Scene(name: "help-cand-4-dark", page: .help, dark: true, height: DS.s(1400), fixture: { fx.help(count: 4, &$0) }),
            // 04.4 D-12: 권장 1(Caps [한, 영] + fn [일, 중])이 사용 중.
            Scene(name: "help-cand-inuse1", page: .help, dark: false, height: DS.s(1400), fixture: { fx.helpInUse1(&$0) }),
            // 04.4 D-16·D-17: 사이드바 「처음 설정 n/5」 행. 처음 설정 화면 자체는 onboarding-* 하니스가 그린다.
            Scene(name: "sidebar-setup", page: .general, dark: false, fixture: fx.permission,
                  onboardingStep: 2),
            // 04.4 D-21: 푸터에 설명 줄 없이 제목 옆 ⓘ(팝오버는 오프스크린에 안 나올 수 있다).
            Scene(name: "keys-entry-info", page: .keys, dark: false, fixture: fx.entry2,
                  setup: { ui, _, _ in ui.keys.entryInfoOpen = .fn }),
            // 04.4: 빈 녹화 칸 강조(지정 2개 중 하나만 조합이 있다).
            Scene(name: "keys-chord-highlight", page: .keys, dark: false, height: DS.s(820), fixture: fx.assignedHalfEmpty,
                  setup: { ui, _, _ in ui.keysChordHighlight = [ID.vietnamese] }),
            // 04.2-07: 알아 둘 점 묶음으로 스크롤해 도착한 모습.
            Scene(name: "help-notes", page: .help, dark: false, height: DS.s(1400), fixture: fx.base,
                  setup: { ui, _, _ in ui.helpAnchor = "help.notes" }),
            Scene(name: "about-light", page: .about, dark: false, fixture: fx.base),
            Scene(name: "about-dark", page: .about, dark: true, fixture: fx.base),
            Scene(name: "about-tall", page: .about, dark: false, height: DS.s(760), fixture: fx.base),
            // 04.1-09 배지 글자 확인: 10개 언어 대표 소스가 한 화면에 보인다.
            Scene(name: "keys-badges-light", page: .keys, dark: false, height: DS.s(820), fixture: fx.badges),
            Scene(name: "keys-badges-dark", page: .keys, dark: true, height: DS.s(820), fixture: fx.badges),
            // 새 버전이 있을 때: 사이드바 머리 주황 점 + 「새 버전 1.1」, 정보 쪽 강조 버튼 「업데이트」.
            Scene(name: "about-available-light", page: .about, dark: false, fixture: fx.base,
                  setup: { _, updates, _ in
                      updates.debugSet(
                          phase: .done(.available(version: "1.1", url: ExternalLinks.releasesLatest)),
                          lastChecked: fixedCheckTime)
                  }),
            // 04.5: 정보 쪽 [☆ Star] 열기 실패 캡션.
            Scene(name: "about-github-failed", page: .about, dark: false, fixture: fx.base,
                  setup: { ui, _, _ in ui.githubOpenFailed = true }),
            // 04.2-08 문제 알리기 쪽: 대기 · 채운 상태(미리보기 펼침) · 오류 · 보내는 중.
            Scene(name: "report-light", page: .report, dark: false, fixture: fx.base),
            Scene(name: "report-dark", page: .report, dark: true, fixture: fx.base),
            Scene(name: "report-filled", page: .report, dark: false, fixture: fx.base,
                  setup: { ui, _, reports in
                      ui.reportMessage = "Switched to Japanese and the first letter came out in English."
                      ui.reportEmail = "name@example.com"
                      ui.reportPreviewOpen = true
                      reports.debugSet(phase: .idle, preview: reportPreviewFixture)
                  }),
            Scene(name: "report-error", page: .report, dark: false, fixture: fx.base,
                  setup: { ui, _, reports in
                      ui.reportMessage = "Switched to Japanese and the first letter came out in English."
                      reports.debugSet(phase: .done(.rateLimited), preview: reportPreviewFixture)
                  }),
            Scene(name: "report-sending", page: .report, dark: false, fixture: fx.base,
                  setup: { ui, _, reports in
                      ui.reportMessage = "Switched to Japanese and the first letter came out in English."
                      reports.debugSet(phase: .sending, preview: reportPreviewFixture)
                  }),
        ]
    }

    /// 「문제 알리기」 미리보기 예시. 실제 diagnosticsText() 모양을 줄인 고정 문자열이다.
    private static let reportPreviewFixture = """
    FnCaps 1.0.0 (1)
    macOS 14.5
    strategy capsFn
    status running
    sources
      com.apple.keylayout.ABC ABC
      com.apple.inputmethod.Korean.2SetKorean 두벌식
    caps com.apple.keylayout.ABC
    fn com.apple.inputmethod.Korean.2SetKorean
    assigned
    notUsed
    assignedChords
    appsOff
    appsSettle
    loginItem on
    appLanguage ko
    systemLanguage ko-KR
    globeUsage changeInputSource
    hotkey60 free
    userKeyMapping
      0x700000039->0x70000006D
    accessibility on
    macModel Mac15,12
    keyboards
      Apple Internal Trackpad
    settings
      holdMs=300
    recent
      15:12:01 switch caps->fn
    """

    /// 고정 스냅숏. 소스 ID는 실제 Apple ID, 이름은 그 언어 표시 이름.
    private struct Fixtures {
        let lang: String

        /// 끌기 장면이 begin/move에 넘기는 목록별 보이는 수(base, full 고정값과 같다).
        static let baseCounts: [SourceList: Int] = [.caps: 1, .fn: 3, .assigned: 0, .excluded: 1]
        static let fullCounts: [SourceList: Int] = [.caps: 2, .fn: 6, .assigned: 0, .excluded: 2]
        static let entry4Counts: [SourceList: Int] = [.caps: 1, .fn: 4, .assigned: 0, .excluded: 1]
        /// 지정 단축키 장면의 수. base에서 병음·베트남어를 지정 상자로 옮긴 구성.
        static let assignedCounts: [SourceList: Int] = [.caps: 1, .fn: 2, .assigned: 2, .excluded: 1]
        /// 지정 상자가 꽉 찬 구성.
        static let assignedFullCounts: [SourceList: Int] = [.caps: 1, .fn: 2, .assigned: 6, .excluded: 1]

        private static let names: [SourceID: [String: String]] = [
            ID.abc: ["ko": "ABC", "en": "ABC", "ja": "ABC",
                     "fr": "ABC", "de": "ABC", "ru": "ABC", "uk": "ABC", "es": "ABC",
                     "zh-Hans": "ABC", "zh-Hant": "ABC"],
            ID.dvorak: ["ko": "Dvorak", "en": "Dvorak", "ja": "Dvorak",
                        "fr": "Dvorak", "de": "Dvorak", "ru": "Дворак", "uk": "Дворак", "es": "Dvorak",
                        "zh-Hans": "德沃夏克", "zh-Hant": "德沃夏克"],
            ID.korean: ["ko": "두벌식", "en": "2-Set Korean", "ja": "2-Set Korean",
                        "fr": "Coréen 2-Set", "de": "Koreanisch - 2-Set", "ru": "Корейская (2-Set)",
                        "uk": "Корейська (два набори)", "es": "Coreano - Dubeolsik",
                        "zh-Hans": "2-Set韩语", "zh-Hant": "2-Set韓文"],
            ID.japanese: ["ko": "일본어 - 로마자 입력", "en": "Japanese – Romaji", "ja": "日本語 - ローマ字入力",
                          "fr": "Japonais – Romaji", "de": "Japanisch – Romaji",
                          "ru": "Японский\u{00A0}— ромадзи", "uk": "Японська — ромадзі",
                          "es": "Japonés (Romaji)", "zh-Hans": "日文 – 罗马字", "zh-Hant": "日文 - 羅馬字"],
            ID.pinyin: ["ko": "병음 - 간체", "en": "Pinyin – Simplified", "ja": "ピンイン - 簡体字",
                        "fr": "Pinyin simplifié", "de": "Pinyin – Vereinfacht",
                        "ru": "Пиньинь\u{00A0}— упрощенная", "uk": "Піньїнь\u{00A0}— спрощена",
                        "es": "Pinyin (simplificado)", "zh-Hans": "简体拼音", "zh-Hant": "簡體拼音"],
            ID.zhuyin: ["ko": "주음 - 번체", "en": "Zhuyin – Traditional", "ja": "注音 - 繁体字",
                        "fr": "Zhuyin traditionnel", "de": "Zhuyin – Traditionell",
                        "ru": "Чжуинь\u{00A0}— традиционная", "uk": "Чжуїнь\u{00A0}— традиційна",
                        "es": "Zhuyin (tradicional)", "zh-Hans": "繁体注音", "zh-Hant": "繁體注音"],
            ID.vietnamese: ["ko": "베트남어", "en": "Vietnamese", "ja": "ベトナム語",
                            "fr": "Vietnamien", "de": "Vietnamesisch", "ru": "Вьетнамская",
                            "uk": "Вʼєтнамська", "es": "Vietnamita",
                            "zh-Hans": "越南语", "zh-Hant": "越南文"],
            ID.hindi: ["ko": "데바나가리 - QWERTY", "en": "Devanagari – QWERTY", "ja": "デーヴァナーガリー - QWERTY",
                       "fr": "Devanagari – QWERTY", "de": "Hindi (Devanagari) – QWERTY",
                       "ru": "Деванагари\u{00A0}— QWERTY", "uk": "Деванагарі\u{00A0}— QWERTY",
                       "es": "Devanagari – QWERTY", "zh-Hans": "天城文 – QWERTY", "zh-Hant": "天城文字 – QWERTY"],
            ID.arabic: ["ko": "아랍어", "en": "Arabic", "ja": "アラビア語",
                        "fr": "Arabe", "de": "Arabisch", "ru": "Арабская", "uk": "Арабська", "es": "Árabe",
                        "zh-Hans": "阿拉伯语", "zh-Hant": "阿拉伯文"],
            ID.unicodeHex: ["ko": "유니코드 16진수 입력", "en": "Unicode Hex Input", "ja": "Unicode 16進入力",
                            "fr": "Universel (Unicode Hex)", "de": "Unicode Hex-Eingabe",
                            "ru": "Ввод Unicode Hex", "uk": "Unicode шістнадцяткова", "es": "Entrada Unicode Hex",
                            "zh-Hans": "Unicode十六进制输入", "zh-Hant": "Unicode十六進位輸入"],
            ID.ukrainian: ["ko": "우크라이나 – 레거시", "en": "Ukrainian – Legacy", "ja": "ウクライナ – レガシー",
                           "fr": "Ukrainien – Ancien clavier", "de": "Ukrainisch – Ältere Version",
                           "ru": "Украинская\u{00A0}— традиционная", "uk": "Українська\u{00A0}— класична",
                           "es": "Ucraniano – Teclado antiguo",
                           "zh-Hans": "乌克兰 – 传统", "zh-Hant": "烏克蘭 – 舊式"],
            ID.russian: ["ko": "러시아", "en": "Russian", "ja": "ロシア",
                         "fr": "Russe", "de": "Russisch",
                         "ru": "Русская", "uk": "Російська", "es": "Ruso",
                         "zh-Hans": "俄罗斯", "zh-Hant": "俄羅斯"],
            ID.french: ["ko": "프랑스", "en": "French", "ja": "フランス",
                        "fr": "Français", "de": "Französisch",
                        "ru": "Французская", "uk": "Французька", "es": "Francés",
                        "zh-Hans": "法国", "zh-Hant": "法國"],
            ID.spanish: ["ko": "스페인 – 레거시", "en": "Spanish – Legacy", "ja": "スペイン – レガシー",
                         "fr": "Espagnol – Ancien clavier", "de": "Spanisch – Ältere Version",
                         "ru": "Испанская\u{00A0}— традиционная", "uk": "Іспанська\u{00A0}— класична",
                         "es": "Español – Teclado antiguo",
                         "zh-Hans": "西班牙 – 传统", "zh-Hant": "西班牙 – 舊式"],
            ID.german: ["ko": "독일", "en": "German", "ja": "ドイツ",
                        "fr": "Allemand", "de": "Deutsch",
                        "ru": "Немецкая", "uk": "Німецька", "es": "Alemán",
                        "zh-Hans": "德国", "zh-Hant": "德國"],
        ]

        private static let languages: [SourceID: [String]] = [
            ID.abc: ["en"], ID.dvorak: ["en"], ID.korean: ["ko"], ID.japanese: ["ja"],
            ID.pinyin: ["zh-Hans"], ID.zhuyin: ["zh-Hant"], ID.vietnamese: ["vi"],
            ID.hindi: ["hi"], ID.arabic: ["ar"], ID.unicodeHex: ["en"],
            ID.ukrainian: ["uk"], ID.russian: ["ru"], ID.french: ["fr"],
            ID.spanish: ["es"], ID.german: ["de"],
        ]

        func name(_ id: SourceID) -> String {
            Self.names[id]?[lang] ?? Self.names[id]?["en"] ?? id
        }

        private func row(_ id: SourceID) -> SourceRow {
            let name = name(id)
            return SourceRow(
                id: id, name: name, enabled: true,
                glyph: SourceGlyph.text(id: id, languages: Self.languages[id] ?? [], name: name))
        }

        /// 도움말 쪽 입력(켜 둔 소스 전체)용 SourceInfo. 언어 코드는 위 표를 쓴다.
        private func info(_ id: SourceID) -> SourceInfo {
            SourceInfo(
                id: id, localizedName: name(id), languages: Self.languages[id] ?? [],
                type: "TISTypeKeyboardLayout", bundleID: nil, inputModeID: nil,
                isSelectCapable: true, isEnabled: true)
        }

        /// 렌더 프로세스의 자판에 기대지 않게 고정 글자 표로 조합 글자를 만든다.
        private static let chordKeys: [UInt16: String] = [8: "c", 9: "v", 38: "j", 1: "s", 49: " "]

        private func chord(_ keyCode: UInt16, _ modifiers: UInt64) -> String {
            ChordFormatter.text(KeyChord(keyCode: keyCode, modifiers: modifiers),
                                keyName: { Self.chordKeys[$0] })
        }

        func base(_ s: inout AppSnapshot) {
            s.status = .running
            s.trusted = true
            s.enabled = true
            s.permissionPanel = .hidden
            s.capsBlocked = false
            s.conflictApps = []
            // 사용자 defaults에서 읽은 「경고 닫음」이 렌더에 남지 않게 되돌린다.
            s.conflictDismissed = false
            // 렌더 프로세스의 실제 값(🌐 설정, 빈 키 배치)에 기대지 않게 고정한다.
            s.globeNotice = false
            s.capsRows = [row(ID.abc)]
            s.fnRows = [row(ID.korean), row(ID.japanese), row(ID.pinyin)]
            // 장면마다 앞 장면의 스냅숏에서 시작하므로 새 필드도 여기서 되돌린다.
            s.assignedRows = []
            s.assignedChordText = [:]
            s.assignedConflictIDs = []
            s.assignedTypingIDs = []
            s.hasShortcuts = false
            s.unassignedRows = [row(ID.unicodeHex)]
            s.currentSourceID = ID.korean
            s.pendingNewSourceIDs = []
            s.entry = EntryChoices()
            // 도움말 쪽 입력. 장면마다 앞 스냅숏에서 시작하므로 여기서 되돌린다.
            s.helpSources = [ID.abc, ID.korean, ID.japanese, ID.pinyin].map(info)
            s.systemLanguage = "ko-KR"
            s.settleExceptions = [
                SettleException(bundleID: "com.apple.TextEdit", ms: SettleTimePolicy.defaultMs, off: true),
                SettleException(bundleID: "com.apple.Terminal", ms: SettleTimePolicy.defaultMs, off: true),
            ]
        }

        func full(_ s: inout AppSnapshot) {
            base(&s)
            s.capsRows = [row(ID.abc), row(ID.dvorak)]
            s.fnRows = [ID.korean, ID.japanese, ID.pinyin, ID.zhuyin, ID.vietnamese, ID.hindi].map(row)
            s.unassignedRows = [row(ID.arabic), row(ID.unicodeHex)]
            s.pendingNewSourceIDs = [ID.arabic]
        }

        // 04.3 진입 언어 장면. Caps [영, 한] 진입 한 + fn [일, 중] 진입 일(2개 고리 좌우 타일).
        func entry2(_ s: inout AppSnapshot) {
            base(&s)
            s.capsRows = [row(ID.abc), row(ID.korean)]
            s.fnRows = [row(ID.japanese), row(ID.pinyin)]
            s.entry = EntryChoices(caps: .source(ID.korean), fn: .source(ID.japanese))
        }

        /// Caps [영, 한] 「쓰던 언어」(화살표 없음) + fn 3개 진입 일(index 1).
        func entry3(_ s: inout AppSnapshot) {
            base(&s)
            s.capsRows = [row(ID.abc), row(ID.korean)]
            s.entry = EntryChoices(caps: .last, fn: .source(ID.japanese))
        }

        /// fn 4개 진입 일(index 1 = 위).
        func entry4(_ s: inout AppSnapshot) {
            base(&s)
            s.fnRows = [ID.korean, ID.japanese, ID.pinyin, ID.zhuyin].map(row)
            s.entry = EntryChoices(caps: .next, fn: .source(ID.japanese))
        }

        /// 가득 찬 배치. fn 진입 베트남어(index 4), Caps 진입 ABC.
        func entry6(_ s: inout AppSnapshot) {
            full(&s)
            s.entry = EntryChoices(caps: .source(ID.abc), fn: .source(ID.vietnamese))
        }

        /// Caps 1개(푸터 없음, D-09) + fn 「쓰던 언어」(화살표 없음).
        func entryNone(_ s: inout AppSnapshot) {
            base(&s)
            s.entry = EntryChoices(caps: .next, fn: .last)
        }

        /// 04.1-09 배지 글자 확인. Caps 1 + fn 6 + 사용 안 함 3으로 10개 언어 대표 소스가 한 화면에 들어온다.
        func badges(_ s: inout AppSnapshot) {
            base(&s)
            s.capsRows = [row(ID.abc)]
            s.fnRows = [ID.korean, ID.japanese, ID.pinyin, ID.zhuyin,
                        ID.ukrainian, ID.russian].map(row)
            s.unassignedRows = [ID.french, ID.spanish, ID.german].map(row)
            s.currentSourceID = ID.korean
        }

        func empty(_ s: inout AppSnapshot) {
            base(&s)
            s.capsRows = []
            s.fnRows = [row(ID.korean)]
            s.unassignedRows = []
        }

        /// 도움말 쪽 언어 수 장면(1~5). 영어 1 + 외국어(count-1)를 켜 둔 상태로 맞춘다.
        /// 시스템 언어는 한국어라 중심 언어가 한국어가 된다(D-27). 1개는 영어 없이 외국어 하나만 켠다.
        func help(count: Int, _ s: inout AppSnapshot) {
            base(&s)
            let foreign = [ID.korean, ID.japanese, ID.pinyin, ID.zhuyin]
            let picked = Array(foreign.prefix(max(count - 1, 0)))
            s.systemLanguage = "ko-KR"
            s.assignedRows = []
            s.unassignedRows = []
            if count >= 2 {
                s.helpSources = ([ID.abc] + picked).map(info)
                s.capsRows = [row(ID.abc)]
                s.fnRows = picked.map(row)
                s.currentSourceID = picked.first ?? ID.abc
            } else {
                s.helpSources = [info(ID.korean)]
                s.capsRows = []
                s.fnRows = [row(ID.korean)]
                s.currentSourceID = ID.korean
            }
        }

        /// 04.2-13 D-46: 4개 언어에서 권장 배치(Caps [영어] + fn [중심] + 지정 [나머지])와 같은 구성.
        func helpRecommended(_ s: inout AppSnapshot) {
            help(count: 4, &s)
            s.fnRows = [row(ID.korean)]
            s.assignedRows = [row(ID.japanese), row(ID.pinyin)]
        }

        /// 04.4 D-12: 권장 1이 사용 중인 구성(Caps [한, 영] + fn [일, 중], 진입 한·일).
        func helpInUse1(_ s: inout AppSnapshot) {
            help(count: 4, &s)
            s.capsRows = [row(ID.korean), row(ID.abc)]
            s.fnRows = [row(ID.japanese), row(ID.pinyin)]
            s.assignedRows = []
            s.entry = EntryChoices(caps: .source(ID.korean), fn: .source(ID.japanese))
        }

        /// 04.4: 지정 2개 중 베트남어만 조합이 비어 있는 구성.
        func assignedHalfEmpty(_ s: inout AppSnapshot) {
            assigned(&s)
            s.assignedChordText = [ID.pinyin: chord(8, 0xC0000)]
        }

        func permission(_ s: inout AppSnapshot) {
            base(&s)
            s.status = .permissionNeeded
            s.trusted = false
            s.permissionPanel = .grant
        }

        func off(_ s: inout AppSnapshot) {
            base(&s)
            s.status = .off
            s.enabled = false
            s.globeNotice = true
        }

        func capsBlocked(_ s: inout AppSnapshot) {
            base(&s)
            s.capsBlocked = true
        }

        func detected(_ s: inout AppSnapshot) {
            base(&s)
            s.conflictApps = ["gksdud"]
        }

        /// 2026-11-13: 충돌 경고(X 있음)와 🌐 경고(X 없음)가 상태 상자 안에 함께 보이는 상태.
        func detectedGlobe(_ s: inout AppSnapshot) {
            detected(&s)
            s.globeNotice = true
        }

        /// 04.2-07: 🌐 값이 권장과 다를 때의 안내 한 줄.
        func globe(_ s: inout AppSnapshot) {
            base(&s)
            s.globeNotice = true
        }

        /// 04.5 2단계: 권한이 꺼지고 다시 켜도 키를 읽지 못하는 막힘 상태.
        func stuck(_ s: inout AppSnapshot) {
            base(&s)
            s.permissionPanel = .stuck
        }

        /// 04.5 2단계: 권한을 잃은 상태. 이유 줄이 「권한을 잃었다」로 바뀐다.
        func lost(_ s: inout AppSnapshot) {
            permission(&s)
            s.permissionLost = true
        }

        // MARK: 지정 단축키(D-46)

        /// Caps 1 + fn 2 + 지정 2 구성. 사용자가 쓰는 모양에 가깝다.
        func assigned(_ s: inout AppSnapshot) {
            base(&s)
            s.fnRows = [row(ID.korean), row(ID.japanese)]
            s.assignedRows = [row(ID.pinyin), row(ID.vietnamese)]
            s.assignedChordText = [ID.pinyin: chord(8, 0xC0000),      // ⌃⌥C
                                   ID.vietnamese: chord(9, 0x180000)] // ⌥⌘V
            s.currentSourceID = ID.pinyin
        }

        /// 베트남어 조합이 시스템 단축키(⌘Space)와 겹치는 구성.
        func assignedConflict(_ s: inout AppSnapshot) {
            assigned(&s)
            s.assignedChordText[ID.vietnamese] = chord(49, 0x100000)
            s.assignedConflictIDs = [ID.vietnamese]
        }

        /// 베트남어가 ⇧ 하나짜리 조합(⇧J)이라 대문자 입력을 가로채는 구성.
        func assignedTyping(_ s: inout AppSnapshot) {
            assigned(&s)
            s.assignedChordText[ID.vietnamese] = chord(38, 0x20000)
            s.assignedTypingIDs = [ID.vietnamese]
        }

        /// 지정 상자 6/6. 다른 상자에서 끌어 오면 거절되는지 본다.
        func assignedFull(_ s: inout AppSnapshot) {
            base(&s)
            s.fnRows = [row(ID.korean), row(ID.japanese)]
            s.assignedRows = [ID.pinyin, ID.vietnamese, ID.zhuyin, ID.hindi,
                              ID.arabic, ID.dvorak].map(row)
            s.assignedChordText = [
                ID.pinyin: chord(8, 0xC0000), ID.vietnamese: chord(9, 0x180000),
                ID.zhuyin: chord(1, 0x140000), ID.hindi: chord(38, 0x140000),
                ID.arabic: chord(1, 0x180000), ID.dvorak: chord(38, 0x180000),
            ]
            s.currentSourceID = ID.pinyin
        }
    }

    private enum ID {
        static let abc = "com.apple.keylayout.ABC"
        static let dvorak = "com.apple.keylayout.Dvorak"
        static let korean = "com.apple.inputmethod.Korean.2SetKorean"
        static let japanese = "com.apple.inputmethod.Kotoeri.RomajiTyping.Japanese"
        static let pinyin = "com.apple.inputmethod.SCIM.ITABC"
        static let zhuyin = "com.apple.inputmethod.TCIM.Zhuyin"
        static let vietnamese = "com.apple.keylayout.Vietnamese"
        static let hindi = "com.apple.keylayout.Devanagari-QWERTY"
        static let arabic = "com.apple.keylayout.Arabic"
        static let unicodeHex = "com.apple.keylayout.UnicodeHexInput"
        static let ukrainian = "com.apple.keylayout.Ukrainian"
        static let russian = "com.apple.keylayout.Russian"
        static let french = "com.apple.keylayout.French"
        static let spanish = "com.apple.keylayout.Spanish"
        static let german = "com.apple.keylayout.German"
    }
}
#endif
