import Foundation

/// Explicit allowlist. Never restore a cloud path into arbitrary host files,
/// the Alpine rootfs, permission grants, arbitrary Keychain items, browser state
/// or tool secrets. Provider credentials use the dedicated provider importer.
nonisolated enum CloudSyncScope {
    static let maximumDocumentBytes = 64 * 1_024 * 1_024

    static func accepts(_ key: String) -> Bool {
        let parts = key.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count >= 2, parts.allSatisfy({
            !$0.isEmpty && $0 != "." && $0 != ".." && !$0.contains("\\")
                && !$0.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
        }) else { return false }
        switch parts[0] {
        case "conversation": return parts.count == 2 && UUID(uuidString: String(parts[1])) != nil
        case "provider": return parts.count == 2 && parts[1].utf8.count <= 128
        case "preference": return key == "preference/model"
        case "control":
            if key == "control/agent/SOUL.md" { return true }
            if parts[1] == "appearance" {
                return key == "control/appearance/appearance.json" || key == "control/appearance/chat-background.data"
            }
            if parts[1] == "memory" { return parts.count >= 3 && key.hasSuffix(".md") }
            return parts[1] == "skills" && parts.count >= 3
        case "attachment", "shared", "offload": return parts.count >= 2
        default: return false
        }
    }
}
