import Foundation
import Testing
@testable import FnCapsSystem

/// 권한 재설정의 재시도·시간 제한과 재시작 구성만 본다.
/// 실제 재설정(`PermissionReset.run`)과 실제 재시작(`AppRestart.relaunchAfterExit`)은 부르지 않는다.
@Suite struct PermissionSystemTests {
    @Test func resetTriesEachServiceThreeTimesAndReportsFailures() {
        var calls: [String] = []
        var sleeps: [TimeInterval] = []
        let failed = PermissionReset.resetAll(
            bundleID: "example.bundle",
            sleep: { sleeps.append($0) },
            runner: { service, id in
                #expect(id == "example.bundle")
                calls.append(service)
                return false
            }
        )
        #expect(failed == ["Accessibility", "PostEvent"])
        #expect(calls == ["Accessibility", "Accessibility", "Accessibility", "PostEvent", "PostEvent", "PostEvent"])
        #expect(sleeps == [0.3, 0.3, 0.3, 0.3])
    }

    @Test func resetReportsOnlyTheServiceThatFailed() {
        let failed = PermissionReset.resetAll(
            bundleID: "example.bundle",
            sleep: { _ in },
            runner: { service, _ in service == "Accessibility" }
        )
        #expect(failed == ["PostEvent"])
    }

    @Test func emptyBundleIDRunsNothing() {
        for id in ["", "  \n"] {
            var calls = 0
            let failed = PermissionReset.resetAll(
                bundleID: id,
                sleep: { _ in },
                runner: { _, _ in
                    calls += 1
                    return true
                }
            )
            #expect(calls == 0)
            #expect(failed == PermissionReset.services)
        }
    }

    @Test func runProcessUsesExitStatus() {
        #expect(PermissionReset.runProcess(path: "/usr/bin/true", arguments: [], timeout: 5) == true)
        #expect(PermissionReset.runProcess(path: "/usr/bin/false", arguments: [], timeout: 5) == false)
        #expect(PermissionReset.runProcess(path: "/nonexistent/fncaps-tool", arguments: [], timeout: 5) == false)
    }

    @Test func runProcessGivesUpAtTimeout() {
        let start = Date()
        #expect(PermissionReset.runProcess(path: "/bin/sleep", arguments: ["5"], timeout: 0.2) == false)
        #expect(Date().timeIntervalSince(start) < 2)
    }

    @Test func restartRefusesNonAppBundle() {
        #expect(AppRestart.makeProcess(bundlePath: "/usr/local/bin/fncaps") == nil)
    }

    @Test func restartPassesPathOnlyThroughEnvironment() throws {
        let path = "/tmp/a b\"; touch /tmp/x; \"/FnCaps.app"
        let process = try #require(AppRestart.makeProcess(bundlePath: path))
        #expect(process.executableURL?.path == "/bin/sh")
        #expect(process.environment?["BUNDLE_PATH"] == path)
        #expect(process.arguments == ["-c", AppRestart.script])
        #expect(AppRestart.script.contains("touch") == false)
        #expect(AppRestart.script.contains("\"$BUNDLE_PATH\" --args --show-settings"))
    }
}
