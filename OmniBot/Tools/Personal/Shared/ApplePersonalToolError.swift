import Foundation

nonisolated struct ApplePersonalToolError: LocalizedError, Sendable {
    let message: String
    let code: String
    let permission: String?
    let authorizationStatus: String?
    let backend: String?
    let requiresSystemSettings: Bool
    let requiresUserInteraction: Bool
    let guidance: String?

    init(
        _ message: String,
        code: String,
        permission: String? = nil,
        authorizationStatus: String? = nil,
        backend: String? = nil,
        requiresSystemSettings: Bool = false,
        requiresUserInteraction: Bool = false,
        guidance: String? = nil
    ) {
        self.message = message
        self.code = code
        self.permission = permission
        self.authorizationStatus = authorizationStatus
        self.backend = backend
        self.requiresSystemSettings = requiresSystemSettings
        self.requiresUserInteraction = requiresUserInteraction
        self.guidance = guidance
    }

    var errorDescription: String? { message }

    var metadata: [String: AgentValue] {
        var result: [String: AgentValue] = [
            "code": .string(code),
            "requiresSystemSettings": .bool(requiresSystemSettings),
            "requiresUserInteraction": .bool(requiresUserInteraction),
        ]
        if let permission {
            result["permission"] = .string(permission)
        }
        if let authorizationStatus {
            result["authorizationStatus"] = .string(authorizationStatus)
        }
        if let backend {
            result["backend"] = .string(backend)
        }
        if let guidance {
            result["guidance"] = .string(guidance)
        }
        return result
    }

    var actions: [AgentArtifactAction] {
        var result: [AgentArtifactAction] = []
        if requiresSystemSettings {
            result.append(AgentArtifactAction(
                type: "open_system_settings",
                label: "Open System Settings",
                payload: [
                    "permission": permission.map(AgentValue.string) ?? .null,
                ]
            ))
        }
        return result
    }
}
