import Foundation

public enum TriggerKey: String, Sendable {
    case caps
    case fn
}

public enum Decision: Equatable, Sendable {
    case switchTo(SourceID)
    case passThrough
    case noop
}
