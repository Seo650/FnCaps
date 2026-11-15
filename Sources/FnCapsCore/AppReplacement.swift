import Foundation

/// 교체에 쓰는 파일 연산. 실제 파일을 부르지 않고 시험에서 실패를 주입할 수 있게 나눈다(T-05-07).
public protocol ReplacementFileOps {
    func exists(_ path: String) -> Bool
    func copy(_ from: String, to: String) throws
    func move(_ from: String, to: String) throws
    func remove(_ path: String) throws
}

/// 설치본을 새 앱으로 바꾸는 순서(D-08). 같은 폴더 안 move로 원자적에 가깝게 교체하고,
/// 새 앱이 스스로 살아 있다고 알리지 못하면 백업을 되돌린다(T-05-07).
public enum AppReplacement {
    public enum Result: Equatable {
        case installed
        /// 어느 단계에서 실패해 되돌렸는지. `stage`, `backup`, `swap`, `launch`.
        case rolledBack(step: String)
        /// 되돌리지도 못했다. 백업이 남아 있는 경로를 알린다.
        case rollbackFailed(backupPath: String)
    }

    /// 설치본 옆에 두는 작업 경로 세 개. 이름은 RESEARCH Pattern 1의 규칙을 따른다.
    public static func paths(installed: String, token: String)
        -> (stage: String, backup: String, failed: String) {
        let folder = (installed as NSString).deletingLastPathComponent
        return (
            stage: "\(folder)/.fncaps-update-\(token).app",
            backup: "\(folder)/.fncaps-rollback-\(token).app",
            failed: "\(folder)/.fncaps-failed-\(token).app"
        )
    }

    /// 후보를 stage로 복사하고 설치본과 자리를 바꾼다. `launchAndConfirm`이 true를 돌려줘야 성공이다.
    /// false면 새 앱을 failed로 옮기고 백업을 설치본 자리로 되돌린다.
    /// `verifyStage`는 복사가 끝난 stage를 swap 직전에 다시 검증한다(05 WR-03). false면 stage를 지우고 되돌린다.
    public static func replace(installed: String, candidate: String, token: String,
                               ops: ReplacementFileOps,
                               verifyStage: (String) -> Bool = { _ in true },
                               launchAndConfirm: (String) -> Bool) -> Result {
        let p = paths(installed: installed, token: token)

        // (1) 후보를 stage로 복사한다. 같은 볼륨의 같은 폴더 안에서만 움직인다.
        // 이전 실행이 남긴 stage가 있으면 먼저 지운다.
        if ops.exists(p.stage) { try? ops.remove(p.stage) }
        do {
            try ops.copy(candidate, to: p.stage)
        } catch {
            try? ops.remove(p.stage)
            return .rolledBack(step: "stage")
        }
        guard verifyStage(p.stage) else {
            try? ops.remove(p.stage)
            return .rolledBack(step: "stage")
        }

        // (2) 설치본을 백업으로 옮긴다. 설치본 자리가 비워진다.
        do {
            try ops.move(installed, to: p.backup)
        } catch {
            try? ops.remove(p.stage)
            return .rolledBack(step: "backup")
        }

        // (3) stage를 설치본 자리로 옮긴다.
        do {
            try ops.move(p.stage, to: installed)
        } catch {
            do {
                try ops.move(p.backup, to: installed)
            } catch {
                return .rollbackFailed(backupPath: p.backup)
            }
            try? ops.remove(p.stage)
            return .rolledBack(step: "swap")
        }

        // (4) 새 앱이 살아 있다고 알리면 성공이다. 백업 삭제 실패는 설치 결과를 뒤집지 않는다.
        if launchAndConfirm(installed) {
            try? ops.remove(p.backup)
            return .installed
        }

        // (5) 새 앱이 뜨지 못했다. failed로 치우고 백업을 되돌린다.
        do {
            try ops.move(installed, to: p.failed)
        } catch {
            return .rollbackFailed(backupPath: p.backup)
        }
        do {
            try ops.move(p.backup, to: installed)
        } catch {
            return .rollbackFailed(backupPath: p.backup)
        }
        try? ops.remove(p.failed)
        return .rolledBack(step: "launch")
    }
}

/// `FileManager.default`를 쓰는 실제 구현. 도우미 프로세스만 이것을 쓴다.
public struct LiveReplacementFileOps: ReplacementFileOps {
    public init() {}

    public func exists(_ path: String) -> Bool {
        FileManager.default.fileExists(atPath: path)
    }

    public func copy(_ from: String, to: String) throws {
        try FileManager.default.copyItem(atPath: from, toPath: to)
    }

    public func move(_ from: String, to: String) throws {
        try FileManager.default.moveItem(atPath: from, toPath: to)
    }

    public func remove(_ path: String) throws {
        try FileManager.default.removeItem(atPath: path)
    }
}
