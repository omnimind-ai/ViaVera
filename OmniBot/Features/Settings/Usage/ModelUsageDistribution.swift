import SwiftUI

struct ModelUsageDistribution: View {
    let summary: ModelUsageSummary
    @State private var metric = ModelUsageRankingMetric.responses
    @State private var showAllModels = false
    private var models: [ModelUsageModel] { metric == .responses ? summary.models : summary.modelsByTokens }
    private var visibleModels: ArraySlice<ModelUsageModel> {
        showAllModels ? models[...] : models.prefix(8)
    }
    private var maximum: Int { models.first.map { metric.value(for: $0) } ?? 0 }
    private var total: Int { metric == .responses ? summary.total.responseCount : summary.total.totalTokens }

    var body: some View {
        ModelUsagePanel(
            title: "模型使用分布",
            subtitle: "了解常用模型，以及各模型的消耗占比。",
            systemImage: "cpu"
        ) {
            Picker("模型分布指标", selection: $metric) {
                ForEach(ModelUsageRankingMetric.allCases) { metric in
                    Text(metric.rawValue).tag(metric)
                }
            }
            .pickerStyle(.segmented)

            if models.isEmpty {
                ContentUnavailableView(
                    "暂无模型响应", systemImage: "cpu",
                    description: Text("完成对话后，模型使用分布会显示在这里。")
                )
            } else {
                VStack(spacing: AppDesign.contentPadding) {
                    ForEach(visibleModels) { model in
                        ModelUsageModelBar(model: model, metric: metric, maximum: maximum, total: total)
                    }
                }
                if models.count > 8 {
                    Button(showAllModels ? "收起" : "查看全部 \(models.count) 个模型", action: toggleAllModels)
                        .frame(minHeight: 44)
                        .frame(maxWidth: .infinity)
                        .tint(ModelUsageStyle.accent)
                }
            }
            if summary.hasUnknownModels {
                Text("部分历史消息未记录模型，已归入“未记录模型”。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func toggleAllModels() { showAllModels.toggle() }
}
