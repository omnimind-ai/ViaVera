import Foundation

enum ModelUsageRankingMetric: String, CaseIterable, Identifiable {
    case responses = "响应次数"
    case tokens = "Token"

    var id: Self { self }

    var title: String {
        switch self {
        case .responses: String(localized: "响应次数")
        case .tokens: "Token"
        }
    }

    func value(for model: ModelUsageModel) -> Int {
        switch self {
        case .responses: model.responseCount
        case .tokens: model.totalTokens
        }
    }
}
