import Foundation
@testable import Via_Vera

func makeTemporaryWorkspace() throws -> (paths: WorkspacePaths, root: URL) {
    let container = FileManager.default.temporaryDirectory
        .appending(path: "OmniBotTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    let paths = WorkspacePaths(
        root: container.appending(path: "workspace", directoryHint: .isDirectory),
        controlRoot: container.appending(path: "control", directoryHint: .isDirectory)
    )
    try paths.prepare()
    return (paths, container)
}
