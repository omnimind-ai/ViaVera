import Darwin
import Foundation

/// A transparent, user-readable memory store. It intentionally starts with lexical
/// retrieval so the Agent core has no embedding or third-party dependency.
public actor MarkdownMemoryStore {
    private static let maximumHarnessFailureEntries = 80

    private struct DailyFile: Sendable {
        let url: URL
        let size: Int
    }

    private struct DailyInventory: Sendable {
        let files: [DailyFile]
        let totalBytes: Int

        var sizeByPath: [String: Int] {
            Dictionary(uniqueKeysWithValues: files.map {
                ($0.url.standardizedFileURL.path, $0.size)
            })
        }
    }

    private let paths: WorkspacePaths
    private let timeZone: TimeZone
    private let limits: MarkdownMemoryLimits

    public init(
        paths: WorkspacePaths,
        timeZone: TimeZone = .current,
        limits: MarkdownMemoryLimits = .default
    ) {
        self.paths = paths
        self.timeZone = timeZone
        self.limits = limits
    }

    public func loadLongTermMemory() throws -> String {
        try prepare()
        return try readIfPresent(
            paths.longTermMemoryFile,
            maximumBytes: limits.maximumLongTermFileBytes
        )
    }

    public func saveLongTermMemory(_ markdown: String) throws {
        try prepare()
        try enforceByteLimit(
            markdown.utf8.count,
            for: paths.longTermMemoryFile,
            maximumBytes: limits.maximumLongTermFileBytes
        )
        try writeDocument(
            normalizedDocument(markdown),
            to: paths.longTermMemoryFile,
            maximumBytes: limits.maximumLongTermFileBytes
        )
    }

    @discardableResult
    public func appendDailyMemory(_ text: String, at date: Date = Date()) throws -> Bool {
        try prepare()
        let file = dailyFile(for: date)
        try enforceByteLimit(
            text.utf8.count,
            for: file,
            maximumBytes: limits.maximumDailyFileBytes
        )
        let clean = cleanEntry(text)
        guard !clean.isEmpty else { return false }

        let inventory = try validatedDailyInventory()
        let existing = try readIfPresent(
            file,
            maximumBytes: limits.maximumDailyFileBytes
        )
        let normalized = normalizedForComparison(clean)
        guard !entries(in: existing).contains(where: {
            normalizedForComparison(stripDailyTimestamp(from: $0)) == normalized
        }) else {
            return false
        }

        let timestamp = timestampString(for: date)
        let line = "- [\(timestamp)] \(clean)"
        let document = try documentByAppending(
            line: line,
            to: file,
            existing: existing,
            maximumBytes: limits.maximumDailyFileBytes
        )
        let documentBytes = document.utf8.count
        try validateDailyProjection(
            inventory: inventory,
            replacing: file,
            withByteCount: documentBytes
        )
        try writeDocument(
            document,
            to: file,
            maximumBytes: limits.maximumDailyFileBytes
        )
        return true
    }

    @discardableResult
    public func upsertLongTermMemory(_ text: String) throws -> Bool {
        try prepare()
        try enforceByteLimit(
            text.utf8.count,
            for: paths.longTermMemoryFile,
            maximumBytes: limits.maximumLongTermFileBytes
        )
        let clean = cleanEntry(text)
        guard !clean.isEmpty else { return false }

        let existing = try readIfPresent(
            paths.longTermMemoryFile,
            maximumBytes: limits.maximumLongTermFileBytes
        )
        let normalized = normalizedForComparison(clean)
        guard !entries(in: existing).contains(where: {
            normalizedForComparison($0) == normalized
        }) else {
            return false
        }

        let document = try documentByAppending(
            line: "- \(clean)",
            to: paths.longTermMemoryFile,
            existing: existing,
            maximumBytes: limits.maximumLongTermFileBytes
        )
        try writeDocument(
            document,
            to: paths.longTermMemoryFile,
            maximumBytes: limits.maximumLongTermFileBytes
        )
        return true
    }

    public func loadDailyMemory(at date: Date = Date()) throws -> String {
        try prepare()
        return try readIfPresent(
            dailyFile(for: date),
            maximumBytes: limits.maximumDailyFileBytes
        )
    }

    public func loadHarnessFailures() throws -> String {
        try prepare()
        return try readIfPresent(
            paths.harnessFailuresFile,
            maximumBytes: limits.maximumHarnessFailureFileBytes
        )
    }

    /// Records a bounded, redacted failure lesson for later retrieval. Repeated
    /// failures update one entry instead of growing the file without limit.
    @discardableResult
    public func recordHarnessFailure(
        toolName: String,
        summary: String,
        runID: UUID,
        at date: Date = Date()
    ) throws -> Bool {
        try prepare()
        let tool = sanitizedToolName(toolName)
        let failure = redactedFailureSummary(summary)
        guard !failure.isEmpty else { return false }

        let identifier = stableSlug("\(tool) \(normalizedForComparison(failure))")
        let existing = try readIfPresent(
            paths.harnessFailuresFile,
            maximumBytes: limits.maximumHarnessFailureFileBytes
        )
        var failureEntries = entries(in: existing)
        let matchingIndex = failureEntries.firstIndex {
            $0.contains("[id=\(identifier)]")
        }
        let count = matchingIndex.map {
            saturatingSum(harnessFailureCount(in: failureEntries[$0]), 1)
        } ?? 1
        if let matchingIndex {
            failureEntries.remove(at: matchingIndex)
        }

        failureEntries.append(
            "[\(timestampString(for: date))] [tool=\(tool)] [count=\(count)] "
                + "[id=\(identifier)] [run=\(runID.uuidString.lowercased())] \(failure)"
        )
        failureEntries = Array(failureEntries.suffix(Self.maximumHarnessFailureEntries))
        let document = "# Harness failures\n\n"
            + failureEntries.map { "- \($0)" }.joined(separator: "\n")
            + "\n"
        try writeDocument(
            document,
            to: paths.harnessFailuresFile,
            maximumBytes: limits.maximumHarnessFailureFileBytes
        )
        return matchingIndex == nil
    }

    public func promptContext(at date: Date = Date()) throws -> MemoryPromptContext {
        MemoryPromptContext(
            longTermMemory: try loadLongTermMemory(),
            todayMemory: try loadDailyMemory(at: date)
        )
    }

    public func search(_ query: String, limit: Int = 4) throws -> [MemorySearchHit] {
        try prepare()
        // Validate the complete persistent daily inventory before reading any
        // candidate. This prevents a pre-existing oversized inventory from
        // turning search into an unbounded series of allocations.
        let inventory = try validatedDailyInventory()
        guard limit > 0 else { return [] }
        let normalizedQuery = normalizedForComparison(query)
        guard !normalizedQuery.isEmpty else { return [] }

        var candidates: [(String, MemorySource)] = entries(in: try readIfPresent(
            paths.longTermMemoryFile,
            maximumBytes: limits.maximumLongTermFileBytes
        )).map { ($0, .longTerm) }

        for dailyFile in inventory.files {
            let date = dailyFile.url.deletingPathExtension().lastPathComponent
            let dailyEntries = entries(in: try readIfPresent(
                dailyFile.url,
                maximumBytes: limits.maximumDailyFileBytes
            ))
            candidates.append(contentsOf: dailyEntries.map {
                (stripDailyTimestamp(from: $0), .daily(date: date))
            })
        }

        candidates.append(contentsOf: entries(in: try readIfPresent(
            paths.harnessFailuresFile,
            maximumBytes: limits.maximumHarnessFailureFileBytes
        )).map { ($0, .harnessFailure) })

        return candidates.compactMap { text, source in
            let score = lexicalScore(query: normalizedQuery, candidate: text)
            guard score > 0 else { return nil }
            return MemorySearchHit(
                id: stableSlug(text),
                text: text,
                source: source,
                score: score
            )
        }
        .sorted {
            if $0.score == $1.score { return $0.id < $1.id }
            return $0.score > $1.score
        }
        .prefix(limit)
        .map { $0 }
    }

    private func prepare() throws {
        try paths.prepare()
        try validateDirectory(paths.memoryDirectory)
        try validateDirectory(paths.shortMemoryDirectory)
        if try inspectRegularFileIfPresent(
            paths.longTermMemoryFile,
            maximumBytes: limits.maximumLongTermFileBytes
        ) == nil {
            try writeDocument(
                "# Long-term memory\n\n",
                to: paths.longTermMemoryFile,
                maximumBytes: limits.maximumLongTermFileBytes
            )
        }
        if try inspectRegularFileIfPresent(
            paths.harnessFailuresFile,
            maximumBytes: limits.maximumHarnessFailureFileBytes
        ) == nil {
            try writeDocument(
                "# Harness failures\n\n",
                to: paths.harnessFailuresFile,
                maximumBytes: limits.maximumHarnessFailureFileBytes
            )
        }
    }

    private func dailyFile(for date: Date) -> URL {
        paths.shortMemoryDirectory.appending(path: dayString(for: date) + ".md")
    }

    private func dayString(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private func timestampString(for date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = timeZone
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    private func validatedDailyInventory() throws -> DailyInventory {
        let files = try dailyMarkdownURLs()

        var dailyFiles: [DailyFile] = []
        dailyFiles.reserveCapacity(files.count)
        var totalBytes = 0
        for file in files {
            guard let size = try inspectRegularFileIfPresent(
                file,
                maximumBytes: limits.maximumDailyFileBytes
            ) else {
                throw fileSystemError("inspect", url: file, code: ENOENT)
            }
            let (newTotal, overflow) = totalBytes.addingReportingOverflow(size)
            totalBytes = overflow ? .max : newTotal
            guard totalBytes <= limits.maximumDailyTotalBytes else {
                throw MarkdownMemoryStoreError.dailyTotalBytesExceeded(
                    actualBytes: totalBytes,
                    maximumBytes: limits.maximumDailyTotalBytes
                )
            }
            dailyFiles.append(DailyFile(url: file, size: size))
        }
        return DailyInventory(files: dailyFiles, totalBytes: totalBytes)
    }

    private func dailyMarkdownURLs() throws -> [URL] {
        let descriptor = paths.shortMemoryDirectory.path.withCString {
            Darwin.open($0, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        }
        guard descriptor >= 0 else {
            throw fileSystemError(
                "open directory",
                url: paths.shortMemoryDirectory,
                code: errno
            )
        }
        guard let directory = Darwin.fdopendir(descriptor) else {
            let code = errno
            Darwin.close(descriptor)
            throw fileSystemError(
                "enumerate directory",
                url: paths.shortMemoryDirectory,
                code: code
            )
        }
        defer { Darwin.closedir(directory) }

        var files: [URL] = []
        while true {
            errno = 0
            guard let entry = Darwin.readdir(directory) else {
                if errno != 0 {
                    throw fileSystemError(
                        "enumerate directory",
                        url: paths.shortMemoryDirectory,
                        code: errno
                    )
                }
                break
            }
            let nameLength = Int(entry.pointee.d_namlen)
            let name = withUnsafePointer(to: &entry.pointee.d_name) { pointer in
                pointer.withMemoryRebound(to: UInt8.self, capacity: nameLength) {
                    String(
                        decoding: UnsafeBufferPointer(start: $0, count: nameLength),
                        as: UTF8.self
                    )
                }
            }
            guard name != ".", name != ".." else { continue }
            let file = paths.shortMemoryDirectory.appending(path: name)
            guard file.pathExtension.lowercased() == "md" else { continue }
            files.append(file)
            guard files.count <= limits.maximumDailyFileCount else {
                throw MarkdownMemoryStoreError.dailyFileCountExceeded(
                    actual: files.count,
                    maximum: limits.maximumDailyFileCount
                )
            }
        }
        return files.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private func validateDailyProjection(
        inventory: DailyInventory,
        replacing file: URL,
        withByteCount byteCount: Int
    ) throws {
        let existingSize = inventory.sizeByPath[file.standardizedFileURL.path]
        if existingSize == nil, inventory.files.count >= limits.maximumDailyFileCount {
            throw MarkdownMemoryStoreError.dailyFileCountExceeded(
                actual: saturatingSum(inventory.files.count, 1),
                maximum: limits.maximumDailyFileCount
            )
        }

        let retainedBytes = inventory.totalBytes - (existingSize ?? 0)
        let projectedBytes = saturatingSum(retainedBytes, byteCount)
        guard byteCount <= limits.maximumDailyTotalBytes - retainedBytes else {
            throw MarkdownMemoryStoreError.dailyTotalBytesExceeded(
                actualBytes: projectedBytes,
                maximumBytes: limits.maximumDailyTotalBytes
            )
        }
    }

    private func validateDirectory(_ url: URL) throws {
        var status = stat()
        let result = url.path.withCString { Darwin.lstat($0, &status) }
        guard result == 0 else {
            throw fileSystemError("inspect directory", url: url, code: errno)
        }
        switch status.st_mode & S_IFMT {
        case S_IFLNK:
            throw MarkdownMemoryStoreError.symbolicLinkNotAllowed(file: displayName(url))
        case S_IFDIR:
            return
        default:
            throw MarkdownMemoryStoreError.notDirectory(path: displayName(url))
        }
    }

    private func inspectRegularFileIfPresent(
        _ url: URL,
        maximumBytes: Int
    ) throws -> Int? {
        var status = stat()
        let result = url.path.withCString { Darwin.lstat($0, &status) }
        if result != 0 {
            let code = errno
            if code == ENOENT { return nil }
            throw fileSystemError("inspect", url: url, code: code)
        }

        switch status.st_mode & S_IFMT {
        case S_IFLNK:
            throw MarkdownMemoryStoreError.symbolicLinkNotAllowed(file: displayName(url))
        case S_IFREG:
            break
        default:
            throw MarkdownMemoryStoreError.notRegularFile(file: displayName(url))
        }

        guard status.st_size >= 0 else {
            throw fileSystemError("inspect size of", url: url, code: EOVERFLOW)
        }
        let size = Int(status.st_size)
        try enforceByteLimit(size, for: url, maximumBytes: maximumBytes)
        return size
    }

    private func readIfPresent(_ url: URL, maximumBytes: Int) throws -> String {
        let descriptor = url.path.withCString {
            Darwin.open($0, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        }
        if descriptor < 0 {
            let code = errno
            if code == ENOENT { return "" }
            if code == ELOOP {
                throw MarkdownMemoryStoreError.symbolicLinkNotAllowed(file: displayName(url))
            }
            throw fileSystemError("open", url: url, code: code)
        }
        defer { Darwin.close(descriptor) }

        var status = stat()
        guard Darwin.fstat(descriptor, &status) == 0 else {
            throw fileSystemError("inspect open", url: url, code: errno)
        }
        guard status.st_mode & S_IFMT == S_IFREG else {
            throw MarkdownMemoryStoreError.notRegularFile(file: displayName(url))
        }
        guard status.st_size >= 0 else {
            throw fileSystemError("inspect size of", url: url, code: EOVERFLOW)
        }
        try enforceByteLimit(
            Int(status.st_size),
            for: url,
            maximumBytes: maximumBytes
        )

        var data = Data()
        data.reserveCapacity(Int(status.st_size))
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            let remaining = maximumBytes - data.count
            let requestedCount = remaining >= buffer.count
                ? buffer.count
                : remaining + 1
            let count = buffer.withUnsafeMutableBytes { rawBuffer in
                Darwin.read(descriptor, rawBuffer.baseAddress, requestedCount)
            }
            if count == 0 { break }
            if count < 0 {
                if errno == EINTR { continue }
                throw fileSystemError("read", url: url, code: errno)
            }
            guard count <= remaining else {
                throw MarkdownMemoryStoreError.fileTooLarge(
                    file: displayName(url),
                    actualBytes: saturatingSum(data.count, count),
                    maximumBytes: maximumBytes
                )
            }
            data.append(contentsOf: buffer.prefix(count))
        }

        guard let value = String(data: data, encoding: .utf8) else {
            throw MarkdownMemoryStoreError.invalidUTF8(file: displayName(url))
        }
        return value
    }

    private func writeDocument(
        _ document: String,
        to url: URL,
        maximumBytes: Int
    ) throws {
        let byteCount = document.utf8.count
        try enforceByteLimit(byteCount, for: url, maximumBytes: maximumBytes)
        _ = try inspectRegularFileIfPresent(url, maximumBytes: maximumBytes)
        try Data(document.utf8).write(to: url, options: .atomic)
    }

    private func enforceByteLimit(
        _ byteCount: Int,
        for url: URL,
        maximumBytes: Int
    ) throws {
        guard byteCount <= maximumBytes else {
            throw MarkdownMemoryStoreError.fileTooLarge(
                file: displayName(url),
                actualBytes: byteCount,
                maximumBytes: maximumBytes
            )
        }
    }

    private func normalizedDocument(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        // Keep an explicit deletion empty instead of recreating the starter heading.
        return trimmed.isEmpty ? "" : trimmed + "\n"
    }

    private func cleanEntry(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func documentByAppending(
        line: String,
        to file: URL,
        existing: String,
        maximumBytes: Int
    ) throws -> String {
        var document = existing
        if document.isEmpty {
            document = file == paths.longTermMemoryFile ? "# Long-term memory\n\n" : ""
        } else if !document.hasSuffix("\n") {
            document += "\n"
        }
        document += line + "\n"
        try enforceByteLimit(
            document.utf8.count,
            for: file,
            maximumBytes: maximumBytes
        )
        return document
    }

    private func entries(in markdown: String) -> [String] {
        markdown.split(whereSeparator: \Character.isNewline).compactMap { rawLine in
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("- ") else { return nil }
            return String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
        }
    }

    private func stripDailyTimestamp(from text: String) -> String {
        guard text.hasPrefix("["), let closing = text.firstIndex(of: "]") else { return text }
        return text[text.index(after: closing)...].trimmingCharacters(in: .whitespaces)
    }

    private func harnessFailureCount(in text: String) -> Int {
        guard let marker = text.range(of: "[count=") else { return 1 }
        let suffix = text[marker.upperBound...]
        guard let closing = suffix.firstIndex(of: "]") else { return 1 }
        return Int(suffix[..<closing]) ?? 1
    }

    private func sanitizedToolName(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-"))
        let scalars = value.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" }
        let sanitized = String(scalars).trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        return sanitized.isEmpty ? "unknown" : String(sanitized.prefix(80))
    }

    private func redactedFailureSummary(_ value: String) -> String {
        var redacted = cleanEntry(value)
        let replacements: [(String, String)] = [
            (#"(?i)(authorization|api[-_ ]?key|password|secret|token)\s*[:=]\s*[^\s,;]+"#, "$1=[REDACTED]"),
            (#"(?i)bearer\s+[A-Za-z0-9._~+\-/]+=*"#, "Bearer [REDACTED]"),
            (#"\bsk-[A-Za-z0-9_-]{8,}\b"#, "[REDACTED]")
        ]
        for (pattern, replacement) in replacements {
            redacted = redacted.replacingOccurrences(
                of: pattern,
                with: replacement,
                options: .regularExpression
            )
        }
        return String(redacted.prefix(1_000))
    }

    private func normalizedForComparison(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .split(whereSeparator: \Character.isWhitespace)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func lexicalScore(query: String, candidate: String) -> Double {
        let normalizedCandidate = normalizedForComparison(candidate)
        let queryTokens = Set(tokens(query))
        let candidateTokens = Set(tokens(normalizedCandidate))
        let overlap = queryTokens.intersection(candidateTokens)
        let tokenScore = queryTokens.isEmpty ? 0 : Double(overlap.count) / Double(queryTokens.count)
        let phraseScore = normalizedCandidate.contains(query) ? 1.0 : 0.0
        return phraseScore * 2.0 + tokenScore
    }

    private func tokens(_ text: String) -> [String] {
        text.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }

    private func stableSlug(_ text: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        let prefix = tokens(text).joined(separator: "-").prefix(32)
        return "\(prefix.isEmpty ? "memory" : String(prefix))-\(String(hash, radix: 16))"
    }

    private func displayName(_ url: URL) -> String {
        url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent
    }

    private func fileSystemError(
        _ operation: String,
        url: URL,
        code: Int32
    ) -> MarkdownMemoryStoreError {
        .fileSystemFailure(
            operation: operation,
            path: displayName(url),
            code: code
        )
    }

    private func saturatingSum(_ lhs: Int, _ rhs: Int) -> Int {
        let (sum, overflow) = lhs.addingReportingOverflow(rhs)
        return overflow ? .max : sum
    }
}
