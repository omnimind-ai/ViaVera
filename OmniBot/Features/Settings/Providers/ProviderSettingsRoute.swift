import Foundation

enum ProviderSettingsRoute: Hashable {
    case create
    case edit(String)

    var providerID: String? {
        switch self {
        case .create:
            nil
        case let .edit(providerID):
            providerID
        }
    }
}
