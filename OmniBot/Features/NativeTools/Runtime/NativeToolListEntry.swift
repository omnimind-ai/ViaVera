import Foundation

nonisolated struct NativeToolListEntry: Identifiable {
    let id: String
    let value: AgentValue

    init?(_ value: AgentValue) {
        guard let id = value.objectValue?["id"]?.stringValue else { return nil }
        self.id = id
        self.value = value
    }
}
