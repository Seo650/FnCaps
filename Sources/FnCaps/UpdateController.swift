import AppKit
import FnCapsCore

/// 업데이트 확인(D-38). 앱에서 네트워크를 쓰는 곳은 여기 한 곳뿐이다.
/// GitHub Releases 최신 태그와 현재 버전을 비교하고, 사용자가 누를 때만 내려받기·교체·재시작한다(D-06).
final class UpdateController: ObservableObject {
    enum Phase: Equatable {
        case idle
        case checking
        case done(UpdateOutcome)
        case downloading
        case verifying
        case installing
        case installFailed(UpdateInstaller.Failure)
        case rolledBack
    }

    typealias Fetch = (URLRequest) async throws -> (Data, URLResponse)

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var autoCheck: Bool
    @Published private(set) var lastChecked: Date?

    private enum Key {
        static let autoCheck = "update.autoCheck"
        static let lastChecked = "update.lastChecked"
        static let latestVersion = "update.latestVersion"
        /// 마지막 확인 결과 종류. 다시 켠 뒤에도 noRelease·rateLimited·failed를 구분해 보여 준다(IN-06).
        static let lastResult = "update.lastResult"
    }

    /// nil이면 메모리에만 둔다(렌더 도구용).
    private let defaults: UserDefaults?
    private let fetch: Fetch
    private var firstTimer: Timer?
    private var repeatTimer: Timer?
    /// 진행 중인 설치. 한 번에 하나만 둔다(T-05-15).
    private var installer: UpdateInstaller?

    /// 확인·설치가 진행 중인지. 진행 중에는 새 확인과 설치를 받지 않는다.
    var isBusy: Bool {
        switch phase {
        case .checking, .downloading, .verifying, .installing:
            return true
        case .idle, .done, .installFailed, .rolledBack:
            return false
        }
    }

    /// 현재 앱 버전(CFBundleShortVersionString).
    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    init(defaults: UserDefaults?, fetch: Fetch? = nil) {
        self.defaults = defaults
        if let fetch {
            self.fetch = fetch
        } else {
            // 쿠키·캐시를 저장하지 않는 세션(T-04-45).
            let session = URLSession(configuration: .ephemeral)
            self.fetch = { request in try await session.data(for: request) }
        }
        // 기본 켬, 하루 1번(FINAL-REVIEW M8).
        autoCheck = defaults?.object(forKey: Key.autoCheck) as? Bool ?? true
        if let seconds = defaults?.object(forKey: Key.lastChecked) as? Double {
            lastChecked = Date(timeIntervalSince1970: seconds)
        }
        // IN-06: 실패 종류를 잃지 않는다. 다시 켠 뒤에도 「확인 실패」로 뭉개지 않는다.
        switch defaults?.string(forKey: Key.lastResult) {
        case "noRelease":
            phase = .done(.noRelease)
        case "rateLimited":
            phase = .done(.rateLimited)
        case "failed":
            phase = .done(.failed)
        default:
            if let latest = defaults?.string(forKey: Key.latestVersion) {
                phase = Self.restoredPhase(latest: latest)
            }
        }
        restoreInstallMarker()
    }

    /// 도우미가 남긴 설치 결과 표지. 고정 문자열 세 개만 해석하고 키는 값과 무관하게 지운다(T-05-16).
    private func restoreInstallMarker() {
        guard let marker = defaults?.string(forKey: UpdateResultMarker.defaultsKey) else { return }
        AppLog.info("update install marker=\(Self.markerLabel(marker))")
        defaults?.removeObject(forKey: UpdateResultMarker.defaultsKey)
        if marker == "rolledBack" || marker == "rollbackFailed" {
            phase = .rolledBack
        }
    }

    /// 표지 값을 로그에 넣을 이름으로 줄인다. 그 밖의 값은 "other".
    private static func markerLabel(_ marker: String) -> String {
        switch marker {
        case "installed", "rolledBack", "rollbackFailed":
            return marker
        default:
            return "other"
        }
    }

    /// 저장한 최신 태그를 지금 버전과 다시 비교한다. 파싱되지 않으면 확인 전 상태로 둔다(T-04-47).
    private static func restoredPhase(latest: String) -> Phase {
        guard let l = AppVersion(latest), let c = AppVersion(currentVersion) else { return .idle }
        if l > c {
            return .done(.available(version: latest, url: ExternalLinks.releasesLatest))
        }
        return .done(.upToDate(latest: latest))
    }

    // MARK: 확인

    /// 수동 확인. 진행 중이면 무시한다(T-04-46, T-05-15).
    func checkNow() {
        if isBusy { return }
        phase = .checking
        let fetch = self.fetch
        let version = Self.currentVersion
        Task {
            let outcome = await UpdateCheck.run(
                owner: ExternalLinks.repoOwner, repo: ExternalLinks.repoName,
                appVersion: version, fetch: fetch)
            await MainActor.run { self.apply(outcome) }
        }
    }

    // MARK: 설치

    /// 「업데이트」 버튼. 새 버전이 있거나 지난 설치가 실패·되돌림일 때만 시작한다(T-05-15).
    /// 설치기는 단계마다 phase를 바꾸고, 성공하면 앱이 곧 종료된다(D-06, D-08).
    func install() {
        switch phase {
        case .done(.available), .installFailed, .rolledBack:
            break
        default:
            return
        }
        if isBusy { return }
        AppLog.info("update install start")
        let installer = UpdateInstaller(
            owner: ExternalLinks.repoOwner, repo: ExternalLinks.repoName,
            currentVersion: Self.currentVersion,
            session: URLSession(configuration: .ephemeral))
        self.installer = installer
        installer.start(onStage: { [weak self] stage in
            guard let self else { return }
            switch stage {
            case .downloading:
                self.phase = .downloading
            case .verifying:
                self.phase = .verifying
            case .installing:
                self.phase = .installing
            }
        }, completion: { [weak self] failure in
            guard let self else { return }
            // 성공(nil)이면 도우미가 앱을 종료할 때까지 「설치 중」 그대로 둔다.
            if let failure {
                self.phase = .installFailed(failure)
            } else {
                self.phase = .installing
            }
            self.installer = nil
        })
    }

    private func apply(_ outcome: UpdateOutcome) {
        // 성공한 확인만 「마지막 확인」으로 남긴다. 실패·요청 한도면 남기지 않아 한 시간 타이머가
        // 다시 묻는다(로그인 직후 네트워크 없음으로 24시간 멈추던 문제, 04-REVIEW WR-03).
        switch outcome {
        case .upToDate, .available, .noRelease:
            let now = Date()
            lastChecked = now
            defaults?.set(now.timeIntervalSince1970, forKey: Key.lastChecked)
        case .rateLimited, .failed:
            break
        }
        let result: String
        var latest = "-"
        switch outcome {
        case .upToDate(let v):
            result = "upToDate"
            latest = v
            defaults?.set(v, forKey: Key.latestVersion)
        case .available(let v, _):
            result = "available"
            latest = v
            defaults?.set(v, forKey: Key.latestVersion)
        case .noRelease:
            result = "noRelease"
        case .rateLimited:
            result = "rateLimited"
        case .failed:
            result = "failed"
        }
        phase = .done(outcome)
        // 다시 켠 뒤에도 같은 결과 종류를 보여 준다(IN-06).
        defaults?.set(result, forKey: Key.lastResult)
        // URL, 헤더, 응답 본문은 남기지 않는다(T-04-45).
        AppLog.info("update check result=\(result) latest=\(UpdateCheckLog.safe(latest))")
    }

    func setAutoCheck(_ on: Bool) {
        autoCheck = on
        defaults?.set(on, forKey: Key.autoCheck)
        if on { checkIfDue() }
    }

    /// 앱 시작 뒤 10초에 한 번, 그 뒤 한 시간마다 확인할 때인지 본다. 하루 1번은 isDue가 정한다.
    func startAutomatic() {
        firstTimer?.invalidate()
        repeatTimer?.invalidate()
        firstTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: false) { [weak self] _ in
            self?.checkIfDue()
        }
        repeatTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            self?.checkIfDue()
        }
    }

    func checkIfDue() {
        if UpdateCheck.isDue(lastChecked: lastChecked, now: Date(), autoEnabled: autoCheck) {
            checkNow()
        }
    }

    /// url은 UpdateCheck.safeReleaseURL이 검증한 값이나 고정 주소만 들어온다(T-04-44).
    func openRelease(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    // MARK: 화면용 문구

    private func format(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .short
        f.doesRelativeDateFormatting = true
        f.locale = Locale(identifier: Bundle.main.preferredLocalizations.first ?? "en")
        return f.string(from: date)
    }

    /// 「FnCaps 정보」 업데이트 행 설명.
    func statusText() -> String {
        switch phase {
        case .idle:
            if let lastChecked { return LF("about.update.failed", format(lastChecked)) }
            return L("about.update.never")
        case .checking:
            return L("about.update.checking")
        case .done(let outcome):
            switch outcome {
            case .upToDate:
                return LF("about.update.upToDate", format(lastChecked ?? Date()))
            case .available(let v, _):
                return LF("about.update.available", v)
            case .noRelease:
                return L("about.update.noRelease")
            case .rateLimited:
                // 인증 없이 IP당 시간 60회(BUILD N4). 다음 「지금 확인」은 평소처럼 다시 요청한다.
                return L("about.update.rateLimited")
            case .failed:
                if let lastChecked { return LF("about.update.failed", format(lastChecked)) }
                return L("about.update.failedNever")
            }
        case .downloading:
            return L("about.update.downloading")
        case .verifying:
            return L("about.update.verifying")
        case .installing:
            return L("about.update.installing")
        case .installFailed(let failure):
            switch failure {
            case .notInstallable:
                return L("about.update.notInstallable")
            case .unsignedBuild:
                return L("about.update.unsignedBuild")
            default:
                return L("about.update.installFailed")
            }
        case .rolledBack:
            return LF("about.update.rolledBack", Self.currentVersion)
        }
    }

    /// 사이드바 앱 머리 상태 줄(D-41, FINAL-REVIEW §7 R4).
    func sidebarLine(version: String) -> (text: String, available: Bool) {
        switch phase {
        case .done(.available(let v, _)):
            return (LF("sidebar.header.newVersion", v), true)
        case .done(.upToDate):
            return (LF("sidebar.header.upToDate", version), false)
        default:
            return (LF("sidebar.header.version", version), false)
        }
    }

    #if DEBUG
    /// 렌더 도구 전용.
    func debugSet(phase: Phase, lastChecked: Date?) {
        self.phase = phase
        self.lastChecked = lastChecked
    }
    #endif
}

/// 로그에 넣는 버전 글자. 숫자·점·짧은 표기만 남긴다.
private enum UpdateCheckLog {
    static func safe(_ s: String) -> String {
        let allowed = Set("0123456789.-abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ")
        return String(s.filter { allowed.contains($0) }.prefix(32))
    }
}
