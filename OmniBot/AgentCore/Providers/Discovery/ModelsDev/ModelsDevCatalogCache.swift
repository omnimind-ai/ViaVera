import Foundation

actor ModelsDevCatalogCache {
    private var catalog: ModelsDevCatalog?
    private var fetchedAt: Date?

    func value(maximumAge: TimeInterval) -> ModelsDevCatalog? {
        guard let catalog, let fetchedAt,
            fetchedAt.addingTimeInterval(maximumAge) > .now
        else {
            return nil
        }
        return catalog
    }

    func store(_ catalog: ModelsDevCatalog) {
        self.catalog = catalog
        fetchedAt = .now
    }
}
