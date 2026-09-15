import Foundation

nonisolated struct NativeToolSystemRequest: Identifiable {
    enum Kind {
        case camera, photo, openText, openData
        case save(Data, String)
        case confirm(String, String)
    }
    let id = UUID()
    let kind: Kind
}
