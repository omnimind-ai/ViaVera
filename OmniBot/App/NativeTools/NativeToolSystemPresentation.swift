import Foundation
import Observation

@MainActor @Observable
final class NativeToolSystemPresentation {
    var request: NativeToolSystemRequest?
    private var continuation: CheckedContinuation<NativeToolSystemResult, any Error>?
    private var result: Result<NativeToolSystemResult, any Error>?

    func present(_ kind: NativeToolSystemRequest.Kind) async throws -> NativeToolSystemResult {
        guard continuation == nil else { throw NativeToolError("请先完成当前系统操作。") }
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            result = nil
            request = NativeToolSystemRequest(kind: kind)
        }
    }

    func complete(_ result: Result<NativeToolSystemResult, any Error>, id: UUID) {
        guard request?.id == id else { return }
        self.result = result
        request = nil
    }

    func dismissed() {
        let continuation = continuation
        self.continuation = nil
        let result = result ?? .failure(CancellationError())
        self.result = nil
        continuation?.resume(with: result)
    }

    func cancel() { request = nil; result = .failure(CancellationError()); dismissed() }
}
