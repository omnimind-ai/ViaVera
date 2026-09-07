import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class ModelUsageViewModel {
    private(set) var summary: ModelUsageSummary?
    private(set) var errorMessage: String?
    private var latestRequest = UUID()

    func load(container: ModelContainer, range: ModelUsageRange) async {
        let request = UUID()
        latestRequest = request
        errorMessage = nil
        if summary?.range != range { summary = nil }
        do {
            let result = try await ModelUsageReader.read(
                container: container, range: range, now: .now, calendar: .current
            )
            guard latestRequest == request, !Task.isCancelled else { return }
            summary = result
        } catch is CancellationError {
            return
        } catch {
            guard latestRequest == request, !Task.isCancelled else { return }
            errorMessage = "无法读取本地用量记录：\(error.localizedDescription)"
        }
    }
}
