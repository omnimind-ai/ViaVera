import Foundation
import UniformTypeIdentifiers
import WebKit

extension AppleBrowserSession {
    static let maximumFetchArtifactBytes = 24 * 1_024 * 1_024
    static let maximumFetchPreviewBytes = 64 * 1_024

    func fetch(
        _ arguments: OmniToolArguments,
        in tab: AppleBrowserTab,
        context: AgentToolExecutionContext,
        resourceProtocol: AgentResourceProtocol
    ) async throws -> AppleBrowserOperationOutput {
        let rawURL = try arguments.requiredString("url", maximumLength: 4_096)
        let url = try normalizedWebURL(rawURL)
        let timeout = try navigationTimeout(arguments)
        let rawResult = try await tab.page.callJavaScript(
            Self.boundedFetchScript,
            arguments: [
                "url": url.absoluteString,
                "timeout": timeout,
                "maximumBytes": Self.maximumFetchArtifactBytes,
            ]
        )
        let response = try decodeFetchedResponse(
            rawResult,
            requestedURL: url.absoluteString
        )
        let mimeType = normalizedMIMEType(response.contentType)
        let suggestedName = suggestedFetchFileName(
            contentDisposition: response.contentDisposition,
            finalURL: response.finalURL
        )
        let artifact = try persistFetchedResponse(
            data: response.data,
            suggestedFileName: suggestedName,
            mimeType: mimeType,
            context: context,
            resourceProtocol: resourceProtocol
        )
        let preview = textPreview(for: response.data, mimeType: mimeType)
        var payload: [String: AgentValue] = [
            "requestedUrl": .string(String(response.requestedURL.prefix(4_096))),
            "finalUrl": .string(String(response.finalURL.prefix(4_096))),
            "status": .number(Double(response.statusCode)),
            "ok": .bool(response.isSuccessfulHTTPResponse),
            "redirected": .bool(response.wasRedirected),
            "mimeType": .string(mimeType),
            "size": .number(Double(response.data.count)),
            "fileName": .string(artifact.fileName),
            "artifactUri": .string(artifact.uri),
            "renderMarkdown": .string(artifact.renderMarkdown),
        ]
        if let preview {
            payload["textPreview"] = .string(preview.text)
            payload["previewTruncated"] = .bool(preview.truncated)
        }

        return AppleBrowserOperationOutput(
            summary: "Fetched \(response.data.count) byte(s) through the current WebKit page and cookie context, then saved the bounded response as a workspace artifact.",
            payload: .object(payload),
            metadata: [
                "interactionMode": .string("page_fetch"),
                "cookieValuesReturned": .bool(false),
                "requestedScheme": .string(url.scheme?.lowercased() ?? ""),
                "maximumArtifactBytes": .number(Double(Self.maximumFetchArtifactBytes)),
                "responseSavedAsArtifact": .bool(true),
            ],
            artifacts: [artifact]
        )
    }

    func decodeFetchedResponse(
        _ rawValue: Any?,
        requestedURL: String
    ) throws -> AppleBrowserFetchedResponse {
        guard let values = rawValue as? [String: Any] else {
            throw AppleBrowserError.invalidFetchResponse
        }
        if values["error"] as? String == "body_too_large" {
            let actualBytes = (values["actualBytes"] as? NSNumber)?.int64Value
                ?? (values["declaredBytes"] as? NSNumber)?.int64Value
            throw AppleBrowserError.fetchBodyTooLarge(
                actualBytes: actualBytes,
                maximumBytes: Self.maximumFetchArtifactBytes
            )
        }
        guard let encodedBody = values["base64"] as? String,
              let statusNumber = values["status"] as? NSNumber else {
            throw AppleBrowserError.invalidFetchResponse
        }
        let maximumEncodedLength = ((Self.maximumFetchArtifactBytes + 2) / 3) * 4
        guard encodedBody.utf8.count <= maximumEncodedLength,
              let data = Data(base64Encoded: encodedBody),
              data.count <= Self.maximumFetchArtifactBytes else {
            throw AppleBrowserError.invalidFetchBodyEncoding
        }
        if let reportedSize = (values["size"] as? NSNumber)?.intValue,
           reportedSize != data.count {
            throw AppleBrowserError.invalidFetchBodyEncoding
        }
        return AppleBrowserFetchedResponse(
            requestedURL: (values["requestedUrl"] as? String) ?? requestedURL,
            finalURL: (values["finalUrl"] as? String) ?? requestedURL,
            statusCode: statusNumber.intValue,
            isSuccessfulHTTPResponse: (values["ok"] as? Bool) ?? false,
            wasRedirected: (values["redirected"] as? Bool) ?? false,
            contentType: values["contentType"] as? String,
            contentDisposition: values["contentDisposition"] as? String,
            data: data
        )
    }

    func persistFetchedResponse(
        data: Data,
        suggestedFileName: String?,
        mimeType: String,
        context: AgentToolExecutionContext,
        resourceProtocol: AgentResourceProtocol
    ) throws -> AgentArtifact {
        guard data.count <= Self.maximumFetchArtifactBytes else {
            throw AppleBrowserError.fetchBodyTooLarge(
                actualBytes: Int64(data.count),
                maximumBytes: Self.maximumFetchArtifactBytes
            )
        }
        let safeName = safeFetchFileName(
            suggestedFileName,
            mimeType: mimeType
        )
        let uniquePrefix = UUID().uuidString.prefix(8).lowercased()
        return try persistBrowserArtifact(
            data,
            preferredName: "fetch-\(uniquePrefix)-\(safeName)",
            title: safeName,
            context: context,
            resourceProtocol: resourceProtocol,
            maximumBytes: Self.maximumFetchArtifactBytes
        )
    }

    func normalizedMIMEType(_ rawValue: String?) -> String {
        guard let rawValue else { return "application/octet-stream" }
        let value = rawValue
            .split(separator: ";", maxSplits: 1)
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
        let parts = value.split(separator: "/", omittingEmptySubsequences: false)
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789!#$&^_.+-")
        guard parts.count == 2,
              parts.allSatisfy({ part in
                  !part.isEmpty && part.unicodeScalars.allSatisfy(allowed.contains)
              }) else {
            return "application/octet-stream"
        }
        return value
    }

    func suggestedFetchFileName(
        contentDisposition: String?,
        finalURL: String
    ) -> String? {
        if let contentDisposition {
            let parameters = contentDispositionParameters(contentDisposition)
            if let encoded = dispositionParameter(named: "filename*", in: parameters) {
                let value = encoded
                    .split(separator: "'", maxSplits: 2, omittingEmptySubsequences: false)
                    .last
                    .map(String.init) ?? encoded
                if let decoded = value.removingPercentEncoding, !decoded.isEmpty {
                    return decoded
                }
            }
            if let plain = dispositionParameter(named: "filename", in: parameters),
               !plain.isEmpty {
                return plain
            }
        }
        guard let url = URL(string: finalURL), !url.lastPathComponent.isEmpty else {
            return nil
        }
        return url.lastPathComponent.removingPercentEncoding ?? url.lastPathComponent
    }

    func safeFetchFileName(
        _ suggestedName: String?,
        mimeType: String
    ) -> String {
        let rawName = (suggestedName?.isEmpty == false ? suggestedName : "download") ?? "download"
        let leafName = rawName
            .replacing("\\", with: "/")
            .split(separator: "/", omittingEmptySubsequences: true)
            .last
            .map(String.init) ?? "download"
        let forbidden = CharacterSet.controlCharacters
            .union(.illegalCharacters)
            .union(CharacterSet(charactersIn: "/\\:<>\"|?*"))
        let cleanedScalars = leafName.unicodeScalars.map { scalar in
            let isBidirectionalControl = (0x202A ... 0x202E).contains(scalar.value)
                || (0x2066 ... 0x2069).contains(scalar.value)
            return forbidden.contains(scalar) || isBidirectionalControl
                ? "_"
                : String(scalar)
        }
        var cleaned = cleanedScalars
            .joined()
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ".")))
        if cleaned.isEmpty || cleaned == "." || cleaned == ".." {
            cleaned = "download"
        }
        cleaned = String(cleaned.prefix(120))

        let normalizedType = normalizedMIMEType(mimeType)
        guard normalizedType != "application/octet-stream",
              let type = UTType(mimeType: normalizedType),
              let preferredExtension = type.preferredFilenameExtension?
                .lowercased()
                .filter({ $0.isASCII && ($0.isLetter || $0.isNumber) }),
              !preferredExtension.isEmpty,
              preferredExtension.count <= 12 else {
            return cleaned
        }
        let currentExtension = URL(fileURLWithPath: cleaned).pathExtension.lowercased()
        if let currentType = UTType(filenameExtension: currentExtension),
           currentType.conforms(to: type) || type.conforms(to: currentType) {
            return cleaned
        }
        let baseName = URL(fileURLWithPath: cleaned)
            .deletingPathExtension()
            .lastPathComponent
        let boundedBase = String((baseName.isEmpty ? "download" : baseName).prefix(100))
        return "\(boundedBase).\(preferredExtension)"
    }

    func textPreview(
        for data: Data,
        mimeType: String
    ) -> (text: String, truncated: Bool)? {
        let isTextual = mimeType.hasPrefix("text/")
            || mimeType.contains("json")
            || mimeType.contains("xml")
            || mimeType.contains("javascript")
            || mimeType == "application/x-www-form-urlencoded"
        guard isTextual else { return nil }
        let prefix = data.prefix(Self.maximumFetchPreviewBytes)
        return (
            String(decoding: prefix, as: UTF8.self),
            data.count > prefix.count
        )
    }
}

private extension AppleBrowserSession {
    func dispositionParameter(
        named name: String,
        in parameters: [String]
    ) -> String? {
        for parameter in parameters.dropFirst() {
            let pair = parameter.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard pair.count == 2,
                  pair[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == name else {
                continue
            }
            var value = pair[1].trimmingCharacters(in: .whitespacesAndNewlines)
            if value.count >= 2, value.first == "\"", value.last == "\"" {
                value.removeFirst()
                value.removeLast()
            }
            return value.replacing("\\\"", with: "\"")
        }
        return nil
    }

    func contentDispositionParameters(_ value: String) -> [String] {
        var parameters: [String] = []
        var current = ""
        var isQuoted = false
        var isEscaped = false
        for character in value {
            if isEscaped {
                current.append(character)
                isEscaped = false
                continue
            }
            if character == "\\", isQuoted {
                current.append(character)
                isEscaped = true
                continue
            }
            if character == "\"" {
                isQuoted.toggle()
                current.append(character)
                continue
            }
            if character == ";", !isQuoted {
                parameters.append(current)
                current = ""
            } else {
                current.append(character)
            }
        }
        parameters.append(current)
        return parameters
    }

    static let boundedFetchScript = #"""
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), Number(timeout));
    try {
        const response = await fetch(url, {
            credentials: "include",
            redirect: "follow",
            signal: controller.signal
        });
        const declaredHeader = response.headers.get("content-length");
        const declaredBytes = declaredHeader === null ? null : Number(declaredHeader);
        if (Number.isFinite(declaredBytes) && declaredBytes > Number(maximumBytes)) {
            if (response.body) await response.body.cancel("OmniBot fetch artifact size limit");
            return {error: "body_too_large", declaredBytes};
        }

        const base64Parts = [];
        let carry = new Uint8Array(0);
        let size = 0;
        function appendBase64(bytes) {
            const combined = new Uint8Array(carry.byteLength + bytes.byteLength);
            combined.set(carry, 0);
            combined.set(bytes, carry.byteLength);
            const encodableLength = combined.byteLength - (combined.byteLength % 3);
            for (let index = 0; index < encodableLength; index += 24576) {
                const end = Math.min(index + 24576, encodableLength);
                base64Parts.push(btoa(String.fromCharCode(...combined.subarray(index, end))));
            }
            carry = combined.slice(encodableLength);
        }
        if (response.body) {
            const reader = response.body.getReader();
            while (true) {
                const result = await reader.read();
                if (result.done) break;
                size += result.value.byteLength;
                if (size > Number(maximumBytes)) {
                    await reader.cancel("OmniBot fetch artifact size limit");
                    return {error: "body_too_large", actualBytes: size};
                }
                appendBase64(result.value);
            }
        } else {
            const bytes = new Uint8Array(await response.arrayBuffer());
            size = bytes.byteLength;
            if (size > Number(maximumBytes)) {
                return {error: "body_too_large", actualBytes: size};
            }
            appendBase64(bytes);
        }
        if (carry.byteLength > 0) {
            base64Parts.push(btoa(String.fromCharCode(...carry)));
        }
        const base64 = base64Parts.join("");
        return {
            requestedUrl: url.slice(0, 4096),
            finalUrl: response.url.slice(0, 4096),
            status: response.status,
            ok: response.ok,
            redirected: response.redirected,
            contentType: response.headers.get("content-type"),
            contentDisposition: response.headers.get("content-disposition"),
            size,
            base64
        };
    } finally {
        clearTimeout(timer);
    }
    """#
}
