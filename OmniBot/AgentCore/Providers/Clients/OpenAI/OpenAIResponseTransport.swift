import Foundation

nonisolated enum OpenAIResponseTransportError: Error, Equatable, Sendable {
    case responseTooLarge(maximumBytes: Int)
    case httpError(statusCode: Int, data: Data)
}

/// Streams provider responses into a bounded buffer.
///
/// `URLSession.data(for:)` buffers the complete response before returning. A
/// provider endpoint is user-configurable, so that API would let an endpoint
/// grow the app's memory without a limit. `AsyncBytes` exposes its data task,
/// allowing us to stop the transfer as soon as the first byte beyond the limit
/// arrives while retaining URLSession's normal cancellation behavior.
nonisolated final class OpenAIResponseTransport: @unchecked Sendable {
    static let defaultMaximumResponseBytes = 8 * 1024 * 1024

    private let session: URLSession
    private let maximumResponseBytes: Int

    init(
        session: URLSession,
        maximumResponseBytes: Int = defaultMaximumResponseBytes
    ) {
        precondition(maximumResponseBytes > 0)
        self.session = session
        self.maximumResponseBytes = maximumResponseBytes
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let cancellationRelay = OpenAIURLSessionTaskCancellationRelay()

        return try await withTaskCancellationHandler {
            let (bytes, response) = try await session.bytes(for: request)
            cancellationRelay.register(bytes.task)
            defer { cancellationRelay.clear(bytes.task) }

            try Task.checkCancellation()
            if response.expectedContentLength > Int64(maximumResponseBytes) {
                bytes.task.cancel()
                throw OpenAIResponseTransportError.responseTooLarge(
                    maximumBytes: maximumResponseBytes
                )
            }

            var data = Data()
            if response.expectedContentLength > 0 {
                data.reserveCapacity(
                    min(Int(response.expectedContentLength), maximumResponseBytes)
                )
            }

            for try await byte in bytes {
                guard data.count < maximumResponseBytes else {
                    bytes.task.cancel()
                    throw OpenAIResponseTransportError.responseTooLarge(
                        maximumBytes: maximumResponseBytes
                    )
                }
                data.append(byte)
            }
            try Task.checkCancellation()
            return (data, response)
        } onCancel: {
            cancellationRelay.cancel()
        }
    }

    func lines(
        for request: URLRequest,
        onLine: @escaping @Sendable (String) async throws -> Void
    ) async throws -> URLResponse {
        let cancellationRelay = OpenAIURLSessionTaskCancellationRelay()

        return try await withTaskCancellationHandler {
            let (bytes, response) = try await session.bytes(for: request)
            cancellationRelay.register(bytes.task)
            defer { cancellationRelay.clear(bytes.task) }

            try Task.checkCancellation()
            if response.expectedContentLength > Int64(maximumResponseBytes) {
                bytes.task.cancel()
                throw OpenAIResponseTransportError.responseTooLarge(
                    maximumBytes: maximumResponseBytes
                )
            }

            let statusCode = (response as? HTTPURLResponse)?.statusCode
            var totalBytes = 0
            var lineData = Data()
            var errorData = Data()

            for try await byte in bytes {
                guard totalBytes < maximumResponseBytes else {
                    bytes.task.cancel()
                    throw OpenAIResponseTransportError.responseTooLarge(
                        maximumBytes: maximumResponseBytes
                    )
                }
                totalBytes += 1

                if let statusCode, !(200..<300).contains(statusCode) {
                    errorData.append(byte)
                    continue
                }

                if byte == 0x0A {
                    if lineData.last == 0x0D { lineData.removeLast() }
                    if let line = String(data: lineData, encoding: .utf8) {
                        try await onLine(line)
                    }
                    lineData.removeAll(keepingCapacity: true)
                } else {
                    lineData.append(byte)
                }
            }

            if let statusCode, !(200..<300).contains(statusCode) {
                throw OpenAIResponseTransportError.httpError(
                    statusCode: statusCode,
                    data: errorData
                )
            }
            if !lineData.isEmpty, let line = String(data: lineData, encoding: .utf8) {
                try await onLine(line)
            }
            try Task.checkCancellation()
            return response
        } onCancel: {
            cancellationRelay.cancel()
        }
    }
}

nonisolated private final class OpenAIURLSessionTaskCancellationRelay: @unchecked Sendable {
    private let lock = NSLock()
    private var task: URLSessionTask?
    private var isCancelled = false

    func register(_ task: URLSessionTask) {
        lock.lock()
        if isCancelled {
            lock.unlock()
            task.cancel()
        } else {
            self.task = task
            lock.unlock()
        }
    }

    func clear(_ task: URLSessionTask) {
        lock.lock()
        if self.task === task {
            self.task = nil
        }
        lock.unlock()
    }

    func cancel() {
        lock.lock()
        isCancelled = true
        let task = self.task
        self.task = nil
        lock.unlock()
        task?.cancel()
    }
}
