import Foundation
import Observation

@MainActor
@Observable
final class NativeToolLibraryModel {
    let store: NativeToolStore
    private(set) var records: [NativeToolRecord] = []
    private(set) var isLoading = false
    var alert: NativeToolAlert?
    private var reloadRequested = false

    init(store: NativeToolStore) { self.store = store }

    var hasMissingBuiltInTools: Bool {
        !isLoading && store.builtInTools.contains { tool in
            !records.contains { $0.builtInID == tool.id }
        }
    }

    func restoreBuiltInTools() async {
        do { try await store.restoreBuiltInTools(); await load() }
        catch { alert = NativeToolAlert(error.localizedDescription) }
    }

    func load() async {
        guard !isLoading else { reloadRequested = true; return }
        isLoading = true
        defer { isLoading = false }
        repeat {
            reloadRequested = false
            do { records = try await store.list() }
            catch { alert = NativeToolAlert(error.localizedDescription) }
        } while reloadRequested
    }

    func setFavorite(_ record: NativeToolRecord) async {
        do { try await store.setFavorite(!record.isFavorite, for: record.id); await load() }
        catch { alert = NativeToolAlert(error.localizedDescription) }
    }

    func delete(_ record: NativeToolRecord) async {
        do {
            try TOTPKeychainVault(toolID: record.id).delete()
            try await store.delete(record.id)
            await load()
        } catch { alert = NativeToolAlert(error.localizedDescription) }
    }
}
