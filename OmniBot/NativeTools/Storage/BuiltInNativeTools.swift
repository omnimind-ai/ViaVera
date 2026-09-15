import Foundation

nonisolated enum BuiltInNativeTools {
    static func load(from skillsDirectory: URL) throws -> [BuiltInNativeTool] {
        let url = skillsDirectory.appending(path: "native-tool-builder/assets/totp.json")
        return [BuiltInNativeTool(id: "totp", package: try NativeToolValidator.decode(Data(contentsOf: url)))]
    }
}
