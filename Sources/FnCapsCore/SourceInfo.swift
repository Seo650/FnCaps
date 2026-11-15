import Foundation

public typealias SourceID = String

/// Plain-value snapshot of one input source (filled from TIS in a later plan).
public struct SourceInfo: Hashable, Codable, Sendable {
    public let id: SourceID
    public let localizedName: String
    public let languages: [String]
    public let type: String
    public let bundleID: String?
    public let inputModeID: String?
    public let isSelectCapable: Bool
    public let isEnabled: Bool

    public init(
        id: SourceID,
        localizedName: String,
        languages: [String],
        type: String,
        bundleID: String?,
        inputModeID: String?,
        isSelectCapable: Bool,
        isEnabled: Bool
    ) {
        self.id = id
        self.localizedName = localizedName
        self.languages = languages
        self.type = type
        self.bundleID = bundleID
        self.inputModeID = inputModeID
        self.isSelectCapable = isSelectCapable
        self.isEnabled = isEnabled
    }
}
