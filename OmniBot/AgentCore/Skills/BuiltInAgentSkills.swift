import Foundation

nonisolated enum BuiltInAgentSkills {
    static func directory(in bundle: Bundle = .main) -> URL? {
        bundle.url(forResource: "BuiltInSkills", withExtension: "bundle")
    }
}
