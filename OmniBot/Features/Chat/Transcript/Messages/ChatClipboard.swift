import SwiftUI

enum ChatClipboard {
    @discardableResult
    static func copy(_ text: String) -> Bool {
#if os(iOS)
        UIPasteboard.general.string = text
        return UIPasteboard.general.string == text
#else
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        return pasteboard.setString(text, forType: .string)
#endif
    }
}
