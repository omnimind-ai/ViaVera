import Foundation

nonisolated enum NativeToolQRCodePayload {
    static func extract(_ payloads: [String]) throws -> String {
        let texts = Set(payloads)
        guard texts.count == 1, let text = texts.first, !text.isEmpty, text.utf8.count <= 32_768 else {
            throw NativeToolError("请一次只识别一个内容不超过 32 KB 的二维码。")
        }
        return text
    }
}
