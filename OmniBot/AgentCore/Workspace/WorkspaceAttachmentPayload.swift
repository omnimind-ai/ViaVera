import Foundation

nonisolated public struct WorkspaceAttachmentPayload: Sendable {
    public let data: Data
    public let preferredName: String

    public init(data: Data, preferredName: String) {
        self.data = data
        self.preferredName = preferredName
    }
}
