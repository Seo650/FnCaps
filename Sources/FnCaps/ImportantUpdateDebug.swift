#if DEBUG
import AppKit
import Combine
import FnCapsCore

/// DEBUG 전용: 가짜 중요 릴리스 확인 결과로 중요 업데이트 창만 띄운다(D-19-5).
///
/// AppModel·CapsController·키 탭·사용자 defaults를 만들지 않으므로 Caps 매핑과 #60에 닿지 않는다.
/// `UpdateController(defaults: nil, fetch:)`에 고정 응답을 넣고 자동 확인 경로를 한 번 돌린다.
/// 릴리스 빌드에는 이 파일과 시작 인수가 들어가지 않는다(T-06-13). 실제 설치 성공은 시험하지 않는다.
enum ImportantUpdateDebug {
    static let argument = "--debug-important-update"

    private static var subscriptions = Set<AnyCancellable>()
    /// app.run() 동안 창 컨트롤러를 붙잡아 둔다.
    private static var windowController: ImportantUpdateWindowController?

    static func run(_ arguments: [String]) -> Int32 {
        let app = NSApplication.shared
        // main.swift 끝과 같은 정책. 화면에 Dock 아이콘을 만들지 않는다.
        app.setActivationPolicy(.accessory)

        let launchedAt = Date()
        let delay = delayArgument(arguments)
        let autoClose = arguments.contains("--debug-auto-close")
        // 상자가 DS.s(160)을 넘어 스크롤하는지 보는 긴 글(06-02 V1).
        let releaseData = fakeReleaseData(long: arguments.contains("--debug-long-text"))

        let updates = UpdateController(defaults: nil, fetch: { _ in
            (releaseData, HTTPURLResponse(
                url: URL(string: "https://api.github.com/repos/Seo650/FnCaps/releases/latest")!,
                statusCode: 200, httpVersion: nil, headerFields: nil)!)
        })
        let controller = ImportantUpdateWindowController(updates: updates, launchedAt: launchedAt)
        windowController = controller
        controller.onClose = {
            print("important debug closed")
            exit(0)
        }

        var shown = false
        updates.$importantOffer
            .compactMap { $0 }
            .sink { _ in
                guard !shown else { return }
                shown = true
                // 창 컨트롤러도 같은 값을 받아 창을 만든다. 구독 순서에 기대지 않고 한 박자 뒤에 확인한다.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    let activate = ImportantNotice.activatesOnShow(launchedAt: launchedAt, now: Date())
                    print("important debug shown=\(controller.isOpen) activate=\(activate)")
                    if autoClose {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { controller.close() }
                    }
                }
            }
            .store(in: &subscriptions)

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            updates.debugRunAutomaticCheck()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay + 15) {
            if !shown {
                print("important debug no offer")
                exit(1)
            }
        }

        app.run()
        return 0
    }

    /// `--debug-delay N`(초). 없거나 잘못되면 0.
    private static func delayArgument(_ arguments: [String]) -> TimeInterval {
        guard let i = arguments.firstIndex(of: "--debug-delay"),
              arguments.indices.contains(i + 1),
              let value = Double(arguments[i + 1]), value >= 0 else { return 0 }
        return value
    }

    /// 형식 계약(06-01 견본과 같다)을 따르는 고정 릴리스 노트. below=99.0.0이라 이 빌드(0.9.x)는 항상 낮다.
    private static let fakeBody = """
    ## Important

    Fixed a problem in this test build.

    <!-- fncaps:important below=99.0.0
    ko: 테스트 빌드의 문제를 고쳤습니다.
    ja: テストビルドの問題を修正しました。
    zh-Hans: 修复了此测试版本中的问题。
    zh-Hant: 修正了此測試版本中的問題。
    de: Ein Problem in diesem Testbuild wurde behoben.
    es: Se ha corregido un problema en esta compilación de prueba.
    fr: Un problème de cette version de test a été corrigé.
    ru: Исправлена проблема в этой тестовой сборке.
    uk: Виправлено проблему в цій тестовій збірці.
    -->
    """

    private static func fakeReleaseData(long: Bool) -> Data {
        let dict: [String: Any] = [
            "tag_name": "v99.0.0",
            "html_url": "https://github.com/Seo650/FnCaps/releases/tag/v99.0.0",
            "draft": false,
            "prerelease": false,
            "assets": [Any](),
            "body": long ? fakeBody.replacingOccurrences(of: "ko: 테스트 빌드의 문제를 고쳤습니다.",
                with: "ko: " + Array(repeating: "테스트 빌드의 문제를 고쳤습니다. 스크롤을 확인하려고 늘린 문장입니다.",
                                     count: 14).joined(separator: " ")) : fakeBody,
        ]
        return (try? JSONSerialization.data(withJSONObject: dict)) ?? Data()
    }
}
#endif
