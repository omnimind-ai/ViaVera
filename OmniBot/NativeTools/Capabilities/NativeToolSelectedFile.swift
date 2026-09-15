import Foundation

nonisolated enum NativeToolSelectedFile {
    static func read(_ url: URL, maximumBytes: Int = 1_024 * 1_024) throws -> Data {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true, let size = values.fileSize, size <= maximumBytes else { throw NativeToolError("请选择不超过 1 MB 的文件。") }
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        var data = Data()
        while data.count <= maximumBytes {
            guard let chunk = try file.read(upToCount: maximumBytes + 1 - data.count), !chunk.isEmpty else { break }
            data.append(chunk)
        }
        guard data.count <= maximumBytes else { throw NativeToolError("文件超过大小限制。") }
        return data
    }
}
