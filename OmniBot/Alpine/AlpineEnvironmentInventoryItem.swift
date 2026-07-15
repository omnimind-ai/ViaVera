import Foundation

struct AlpineEnvironmentInventoryItem: Equatable, Sendable {
    let isReady: Bool
    let version: String?

    static func parse(_ output: String) -> [String: AlpineEnvironmentInventoryItem] {
        output
            .replacing("\r\n", with: "\n")
            .replacing("\r", with: "\n")
            .split(separator: "\n")
            .reduce(into: [:]) { inventory, line in
                let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
                guard fields.count >= 4, fields[0] == "__OMNI_ENV__" else { return }
                let identifier = String(fields[1])
                let version = fields.dropFirst(3).joined(separator: " ")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                inventory[identifier] = AlpineEnvironmentInventoryItem(
                    isReady: fields[2] == "READY",
                    version: version.isEmpty ? nil : version
                )
            }
    }
}
