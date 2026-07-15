nonisolated struct ProviderModelSelection: Hashable {
    let providerID: String
    let modelID: String

    func availability(in profiles: [ProviderProfile]) -> ProviderModelSelectionAvailability {
        guard !modelID.isEmpty else { return .none }
        guard let provider = profiles.first(where: { $0.id == providerID }) else {
            return .providerMissing
        }
        guard provider.isEnabled else { return .providerDisabled }
        guard let model = provider.models.first(where: { $0.id == modelID }) else {
            return .modelMissing
        }
        return model.isHidden ? .modelHidden : .available
    }
}

nonisolated enum ProviderModelSelectionAvailability: Equatable {
    case none
    case available
    case providerMissing
    case providerDisabled
    case modelMissing
    case modelHidden

    var needsCurrentEntry: Bool {
        switch self {
        case .none, .available:
            false
        case .providerMissing, .providerDisabled, .modelMissing, .modelHidden:
            true
        }
    }
}
