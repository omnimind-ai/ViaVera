import Foundation

nonisolated struct NativeToolImportRequest: Identifiable {
    let id = UUID()
    let package: NativeToolPackage
}
