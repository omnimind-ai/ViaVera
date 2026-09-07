import Foundation

enum ModelUsageRankingMetric: String, CaseIterable, Identifiable {
    case responses = "响应次数"
    case tokens = "Token"

    var id: Self { self }

    func value(for model: ModelUsageModel) -> Int {
        switch self {
        case .responses: model.responseCount
        case .tokens: model.totalTokens
        }
    }
}
