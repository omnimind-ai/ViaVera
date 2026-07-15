import Foundation
import Observation

@MainActor
@Observable
final class AlpineRootFileSystemManager {
    private(set) var sizeInBytes: Int64?
    private(set) var isRefreshingSize = false
    private(set) var isSchedulingReset = false
    private(set) var isResetScheduled: Bool
    private(set) var errorMessage: String?

    @ObservationIgnored
    private let storage: AlpineRootFileSystemStorage

    init(stateDirectory: URL, resetRequestURL: URL) {
        storage = AlpineRootFileSystemStorage(
            stateDirectory: stateDirectory,
            resetRequestURL: resetRequestURL
        )
        isResetScheduled = FileManager.default.fileExists(atPath: resetRequestURL.path)
    }

    func refreshSize() async {
        guard !isRefreshingSize else { return }
        isRefreshingSize = true
        errorMessage = nil
        defer { isRefreshingSize = false }

        do {
            sizeInBytes = try await storage.sizeInBytes()
        } catch {
            errorMessage = "无法读取 Rootfs 大小：\(error.localizedDescription)"
        }
    }

    func scheduleReset() async {
        guard !isSchedulingReset, !isResetScheduled else { return }
        isSchedulingReset = true
        errorMessage = nil
        defer { isSchedulingReset = false }

        do {
            try await storage.scheduleReset()
            isResetScheduled = true
        } catch {
            errorMessage = "无法安排 Rootfs 重置：\(error.localizedDescription)"
        }
    }
}
