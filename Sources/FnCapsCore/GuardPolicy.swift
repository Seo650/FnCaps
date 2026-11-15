import Foundation

/// Where a strategy is allowed to post synthetic keys.
public enum PostTarget: Equatable, Sendable {
    /// Any frontmost app. Allowed only for re-posting the user's own system shortcut.
    case anyApp
    /// Only while the app with this pid is frontmost.
    case pid(Int32)
}

/// Decides whether a strategy may post synthetic events. There is no "nil means anywhere" path:
/// Return or printable-key posting must always use `.pid`; `.anyApp` is allowed only for re-posting
/// the user's own system shortcut.
public enum GuardPolicy {
    public static func shouldPost(_ target: PostTarget, frontmostPid: Int32?) -> Bool {
        switch target {
        case .anyApp: return true
        case .pid(let pid): return pid > 0 && frontmostPid == pid
        }
    }
}
