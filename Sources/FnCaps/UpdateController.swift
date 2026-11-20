// 구조 참고: Sparkle SPUUpdater scheduleNextUpdateCheck (MIT)
import AppKit
import Dispatch
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
    /// 자동 확인에서 중요 표시가 있는 릴리스를 찾았을 때의 창 값(D-14~D-16). 정기 확인마다 새로 넣는다.
    /// 버전을 저장하는 defaults 키는 두지 않는다(D-19-1: 다시 알림은 정기 확인 주기가 정한다).
    @Published private(set) var importantOffer: ImportantOffer?

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
    /// 자동 확인 타이머. 마지막 확인 + 하루에 한 번 울리는 벽시계 일회성 타이머 하나뿐이다(D-11).
    private var checkTimer: DispatchSourceTimer?
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

    /// 수동 「지금 확인」. 창을 열지 않는다(사용자가 이미 정보 쪽을 보고 있다, UI-SPEC 열기 규칙 1).
    func checkNow() { runCheck(automatic: false) }

    /// 확인 한 번. automatic이면 결과에 중요 표시가 있을 때 중요 업데이트 창을 낸다(D-14, D-17).
    private func runCheck(automatic: Bool) {
        if isBusy { return }
        phase = .checking
        let fetch = self.fetch
        let version = Self.currentVersion
        Task {
            let result = await UpdateCheck.check(
                owner: ExternalLinks.repoOwner, repo: ExternalLinks.repoName,
                appVersion: version, fetch: fetch)
            await MainActor.run {
                self.apply(result.outcome, body: result.releaseBody, automatic: automatic)
            }
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

    private func apply(_ outcome: UpdateOutcome, body: String?, automatic: Bool) {
        // 성공한 확인만 「마지막 확인」으로 남긴다. 실패·요청 한도면 남기지 않는다. 실패해도 바로 다시 묻지
        // 않고 하루 뒤에 묻는다(D-11). 로그인 직후 네트워크 없음으로 멈추지 않게 하려면 이 재예약이 필요하다
        // (04-REVIEW WR-03의 한 시간 재시도를 대체).
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
        // 성공·실패 모두 지금부터 하루 뒤로 다시 건다. Sparkle usingCurrentDate:NO와 같다(D-11).
        scheduleNextCheck(after: UpdateCheck.interval)
        // 자동 확인(타이머)이고 중요 표시가 있으면 창 값을 넣는다. 같은 값이어도 확인마다 한 번 넣는다
        // (한 번의 정기 확인에 많아야 한 번, D-19-1). 안내 글 원문은 로그에 남기지 않는다(T-06-12).
        if automatic, case .available(let version, _) = outcome {
            let language = Bundle.main.preferredLocalizations.first ?? "en"
            if let offer = ImportantNotice.offer(body: body, latest: version,
                                                  currentVersion: Self.currentVersion,
                                                  language: language) {
                importantOffer = offer
                AppLog.info("update important offer version=\(UpdateCheckLog.safe(version))")
            }
        }
    }

    /// 중요 업데이트 창을 닫을 때 값도 지운다. 다음 정기 확인에서 다시 판정한다(D-19-1).
    func clearImportantOffer() {
        importantOffer = nil
    }

    func setAutoCheck(_ on: Bool) {
        autoCheck = on
        defaults?.set(on, forKey: Key.autoCheck)
        // 켜면 lastChecked 기준으로 다시 걸고, 끄면 아래 off 분기에서 타이머만 없어진다(D-11).
        // 켠 직후의 확인은 창을 열지 않는다(UI-SPEC 열기 규칙 1).
        scheduleNextCheck(after: UpdateCheck.nextCheckDelay(lastChecked: lastChecked, now: Date()),
                          offerImportant: false)
    }

    /// lastChecked + 하루에 벽시계 일회성 타이머 하나(D-11). 그 시각이 이미 지났으면 바로 확인한다.
    func startAutomatic() {
        scheduleNextCheck(after: UpdateCheck.nextCheckDelay(lastChecked: lastChecked, now: Date()))
    }

    /// 다음 확인까지 delay초 뒤에 울리는 타이머를 하나만 둔다. 걸린 타이머는 먼저 없앤다.
    /// offerImportant가 거짓이면 바로 확인하더라도 중요 업데이트 창을 열지 않는다.
    private func scheduleNextCheck(after delay: TimeInterval, offerImportant: Bool = true) {
        dispatchPrecondition(condition: .onQueue(.main))
        checkTimer?.cancel()
        checkTimer = nil
        guard autoCheck else {
            AppLog.info("update schedule off")
            return
        }
        if delay <= 0 {
            AppLog.info("update schedule in=0s")
            fireScheduledCheck(offerImportant: offerImportant)
            return
        }
        // 벽시계 기준이라 잠자는 시간도 센다. 깨어날 때 시각이 지났으면 바로 확인이 돈다(REL-03).
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(wallDeadline: .now() + delay, repeating: .never, leeway: .seconds(30))
        // 타이머가 울린 확인은 항상 창 열기 대상이다.
        timer.setEventHandler { [weak self] in self?.fireScheduledCheck() }
        timer.resume()
        checkTimer = timer
        AppLog.info("update schedule in=\(Int(delay))s")
    }

    /// 타이머가 울렸을 때. 진행 중인 확인·설치와 겹치면 새 요청 없이 하루 뒤로 다시 건다(edge REL-03 concurrency).
    private func fireScheduledCheck(offerImportant: Bool = true) {
        checkTimer?.cancel()
        checkTimer = nil
        if isBusy {
            scheduleNextCheck(after: UpdateCheck.interval)
        } else {
            runCheck(automatic: offerImportant)
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

    /// DEBUG 중요 업데이트 창 실행 전용. 자동 확인 경로를 한 번 돌린다(D-19-5).
    func debugRunAutomaticCheck() { runCheck(automatic: true) }
    #endif
}

/// 로그에 넣는 버전 글자. 숫자·점·짧은 표기만 남긴다.
private enum UpdateCheckLog {
    static func safe(_ s: String) -> String {
        let allowed = Set("0123456789.-abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ")
        return String(s.filter { allowed.contains($0) }.prefix(32))
    }
}
