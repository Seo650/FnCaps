import AppKit
import FnCapsCore
import FnCapsSystem

// 제품 경로: 앱이 켜진 입력 소스 목록의 기준으로 읽는 출력(FreshSourceLister). 새 프로세스의 TIS 값을
// JSON으로 내고 바로 끝낸다. 분류에 언어 값이 필요해 ID 줄만으로는 부족하다.
if CommandLine.arguments.contains("--list-enabled-source-ids") {
    FileHandle.standardOutput.write(EnabledSourceList.encode(InputSourceCatalog().loadEnabled()))
    exit(0)
}

// 앱 안 업데이트(D-08) 도우미. 애플리케이션·모델·키 매핑을 만들기 전에 분기한다(RESEARCH Pitfall 5, T-05-13).
if CommandLine.arguments.contains(UpdateHelper.argument) {
    exit(UpdateHelper.run(CommandLine.arguments))
}

#if DEBUG
// debug 전용 화면 밖 렌더 점검. release 바이너리에는 이 분기가 없다.
if let i = CommandLine.arguments.firstIndex(of: "--render-settings"),
   CommandLine.arguments.indices.contains(i + 1)
{
    exit(SettingsRenderHarness.run(outputDir: URL(fileURLWithPath: CommandLine.arguments[i + 1])))
}
// debug 전용: 가짜 중요 릴리스로 중요 업데이트 창만 띄운다(D-19-5). AppModel을 만들지 않는다.
if CommandLine.arguments.contains(ImportantUpdateDebug.argument) {
    exit(ImportantUpdateDebug.run(CommandLine.arguments))
}
#endif

// 중복 실행이면 앱 객체·AppDelegate·CapsController를 만들기 전에 끝난다. 그래야 끝나는 쪽이
// Caps 매핑과 #60에 닿지 않고 applicationShouldTerminate의 복원도 돌지 않는다(T-dvj-01).
// 앞의 CLI 분기(FreshSourceLister 자식, 업데이트 도우미)는 이미 끝났으므로 영향이 없다.
// 업데이트·재시작 재실행은 부모 종료를 기다린 뒤 띄우므로 옛 인스턴스를 보지 않는다(T-dvj-02).
// swift run처럼 번들 ID가 없으면 건너뛴다.
if let bundleID = Bundle.main.bundleIdentifier {
    let peers = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).map {
        RunningPeer(pid: $0.processIdentifier, terminated: $0.isTerminated, alive: kill($0.processIdentifier, 0) == 0)
    }
    if SingleInstanceCheck.shouldExit(selfPid: getpid(), parentPid: getppid(), peers: peers) {
        AppLog.info("launch duplicate result=exit")
        exit(0)
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
