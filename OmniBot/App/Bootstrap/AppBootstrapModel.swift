import Observation

@MainActor
@Observable
final class AppBootstrapModel {
    private(set) var dependencies: AppDependencies?
    private(set) var errorMessage: String?

    init() {
        retry()
    }

    func retry() {
        do {
            dependencies = try AppDependencies.live()
            errorMessage = nil
        } catch {
            dependencies = nil
            errorMessage = error.localizedDescription
        }
    }
}
