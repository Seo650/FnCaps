import Foundation

/// 사용자 입력으로 URL을 만들지 않는다. 고정 상수만 연다.
enum ExternalLinks {
    static let buyMeACoffee = URL(string: "https://buymeacoffee.com/seo650")!

    /// 「문제 알리기」 전송 주소(D-11). 앱에는 GitHub 토큰이 없고 Worker가 대신 만든다.
    static let reportEndpoint = URL(string: "https://fncaps-reports.fncaps.workers.dev/report")!

    // 업데이트 확인 저장소(D-38).
    // 2026-11-14 사용자가 확인한 저장소 주소(Seo650/FnCaps). 공개 여부는 Phase 5에서 확인한다.
    static let repoOwner = "Seo650"
    static let repoName = "FnCaps"
    static var releasesLatest: URL {
        URL(string: "https://github.com/\(repoOwner)/\(repoName)/releases/latest")!
    }

    /// GitHub 저장소 쪽. 정보 쪽 [☆ Star]가 이 고정 주소만 연다(UI-SPEC §9).
    static var githubRepo: URL {
        URL(string: "https://github.com/\(repoOwner)/\(repoName)")!
    }
}
