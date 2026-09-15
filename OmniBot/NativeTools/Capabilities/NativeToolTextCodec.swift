import Foundation

nonisolated enum NativeToolTextCodec {
    static func decode(_ data: Data) throws -> String {
        let text: String?
        if data.starts(with: [0xFF, 0xFE]) { text = String(data: data.dropFirst(2), encoding: .utf16LittleEndian) }
        else if data.starts(with: [0xFE, 0xFF]) { text = String(data: data.dropFirst(2), encoding: .utf16BigEndian) }
        else { text = String(data: data.starts(with: [0xEF, 0xBB, 0xBF]) ? data.dropFirst(3) : data, encoding: .utf8) }
        guard let text else { throw NativeToolError("请选择 UTF-8 或带 BOM 的 UTF-16 文本。") }
        return text
    }
}
