import Foundation
@testable import Via_Vera

nonisolated enum NativeToolTestFixtures {
    static var skillDirectory: URL {
        if let path = ProcessInfo.processInfo.environment["OMNIBOT_NATIVE_TOOL_SKILL_DIRECTORY"] { return URL(fileURLWithPath: path) }
        return URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "OmniBot/Resources/BuiltInSkills.bundle/native-tool-builder")
    }

    static func package(_ name: String = "checklist") throws -> NativeToolPackage {
        try NativeToolValidator.decode(Data(contentsOf: skillDirectory.appending(path: "assets/\(name).json")))
    }

    static func workspace() throws -> (root: URL, paths: WorkspacePaths) {
        let root = FileManager.default.temporaryDirectory.appending(path: "native-tools-test-\(UUID().uuidString)")
        let paths = WorkspacePaths(root: root.appending(path: "workspace"), controlRoot: root.appending(path: "control"))
        try paths.prepare()
        return (root, paths)
    }

    static func modifying(_ package: NativeToolPackage, _ change: (inout [String: AgentValue]) -> Void) throws -> NativeToolPackage {
        var object = try JSONDecoder().decode(AgentValue.self, from: JSONEncoder().encode(package)).objectValue!
        change(&object)
        return try NativeToolValidator.decode(JSONEncoder().encode(AgentValue.object(object)))
    }
}
