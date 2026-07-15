import Testing
@testable import Via_Vera

@Suite("Workspace browser paths")
struct WorkspaceBrowserPathTests {
    @Test("Builds breadcrumbs from the workspace root to the current folder")
    func buildsBreadcrumbPaths() {
        let path = WorkspaceBrowserPath(components: ["Projects", "OmniBot", "Sources"])

        #expect(path.breadcrumbPaths.map(\.shellPath) == [
            "/workspace",
            "/workspace/Projects",
            "/workspace/Projects/OmniBot",
            "/workspace/Projects/OmniBot/Sources",
        ])
        #expect(WorkspaceBrowserPath.root.breadcrumbPaths == [.root])
    }
}
