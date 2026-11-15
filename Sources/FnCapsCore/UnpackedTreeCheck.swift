import Foundation

/// 압축을 푼 뒤의 디렉터리 검사(05 WR-05). zip 목록의 크기는 자기 신고라 실제로 풀린 양과 다를 수 있으므로
/// 풀린 트리를 `lstat` 의미(링크를 따라가지 않음)로 직접 훑는다.
/// 총 실제 크기·항목 수 한도를 넘거나, 번들 밖을 가리키는 심볼릭 링크, 하드 링크, 특수 파일이 있으면 거부한다.
public enum UnpackedTreeCheck {
    public enum Verdict: Equatable, Sendable {
        case ok
        case rootInvalid
        case tooManyEntries
        case tooLarge
        /// 번들 밖을 가리키거나 절대 경로인 심볼릭 링크. 값은 루트 기준 상대 경로.
        case escapingSymlink(String)
        /// 링크 수가 2 이상인 일반 파일.
        case hardLink(String)
        /// 일반 파일·디렉터리·심볼릭 링크가 아닌 항목(소켓, 장치, 파이프).
        case specialFile(String)
        case unreadable(String)
    }

    /// `root`(풀린 `FnCaps.app` 디렉터리) 아래를 훑는다. 루트 자체가 링크이거나 디렉터리가 아니면 `.rootInvalid`.
    public static func inspect(root: String,
                               maxBytes: Int = UpdateAssets.maxUnpackedBytes,
                               maxEntries: Int = UpdateAssets.maxEntries) -> Verdict {
        var rootStat = stat()
        guard lstat(root, &rootStat) == 0, (rootStat.st_mode & S_IFMT) == S_IFDIR else { return .rootInvalid }
        let rootPath = (root as NSString).standardizingPath

        var entries = 0
        var bytes = 0
        var stack: [String] = [rootPath]
        let fileManager = FileManager.default

        while let directory = stack.popLast() {
            guard let names = try? fileManager.contentsOfDirectory(atPath: directory) else {
                return .unreadable(relative(directory, to: rootPath))
            }
            for name in names {
                entries += 1
                if entries > maxEntries { return .tooManyEntries }
                let path = directory + "/" + name
                let rel = relative(path, to: rootPath)
                var info = stat()
                guard lstat(path, &info) == 0 else { return .unreadable(rel) }
                switch info.st_mode & S_IFMT {
                case S_IFDIR:
                    stack.append(path)
                case S_IFREG:
                    if info.st_nlink > 1 { return .hardLink(rel) }
                    bytes += Int(info.st_size)
                    if bytes > maxBytes { return .tooLarge }
                case S_IFLNK:
                    guard let target = try? fileManager.destinationOfSymbolicLink(atPath: path) else {
                        return .unreadable(rel)
                    }
                    if !linkStaysInside(target: target, linkDirectory: directory, root: rootPath) {
                        return .escapingSymlink(rel)
                    }
                    bytes += Int(info.st_size)
                    if bytes > maxBytes { return .tooLarge }
                default:
                    return .specialFile(rel)
                }
            }
        }
        return .ok
    }

    /// 링크 대상이 절대 경로가 아니고, 링크가 있는 폴더에서 풀어 쓴 결과가 루트 안에 머무는지 본다.
    /// `Versions/Current -> A` 같은 번들 안 링크와 루트 안에 머무는 `..` 대상은 허용한다.
    static func linkStaysInside(target: String, linkDirectory: String, root: String) -> Bool {
        guard !target.isEmpty, !target.hasPrefix("/") else { return false }
        var parts = linkDirectory.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        let rootParts = root.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        for component in target.split(separator: "/", omittingEmptySubsequences: true) {
            switch component {
            case ".": continue
            case "..":
                guard parts.count > rootParts.count else { return false }
                parts.removeLast()
            default:
                parts.append(String(component))
            }
        }
        return parts.count >= rootParts.count && Array(parts.prefix(rootParts.count)) == rootParts
    }

    private static func relative(_ path: String, to root: String) -> String {
        guard path.hasPrefix(root) else { return path }
        let rest = path.dropFirst(root.count)
        return rest.hasPrefix("/") ? String(rest.dropFirst()) : String(rest)
    }
}
