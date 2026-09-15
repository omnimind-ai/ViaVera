import SwiftUI
import UniformTypeIdentifiers

struct NativeToolJSONDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    let data: Data

    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw NativeToolError("文件无法读取。") }
        self.data = data
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}
