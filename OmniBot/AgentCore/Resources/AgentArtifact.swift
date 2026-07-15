import Foundation

nonisolated public struct AgentArtifact: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let uri: String
    public let title: String
    public let fileName: String
    public let mimeType: String
    public let size: Int64
    public let sourceTool: String
    public let workspacePath: String
    public let hostPath: String
    public let previewKind: String
    public let actions: [AgentArtifactAction]

    public init(
        id: String,
        uri: String,
        title: String,
        fileName: String,
        mimeType: String,
        size: Int64,
        sourceTool: String,
        workspacePath: String,
        hostPath: String,
        previewKind: String,
        actions: [AgentArtifactAction] = []
    ) {
        self.id = id
        self.uri = uri
        self.title = title
        self.fileName = fileName
        self.mimeType = mimeType
        self.size = size
        self.sourceTool = sourceTool
        self.workspacePath = workspacePath
        self.hostPath = hostPath
        self.previewKind = previewKind
        self.actions = actions
    }

    /// `hostPath` is process-local backing state and is never part of a wire
    /// payload. Keeping it out of Codable prevents an accidental direct encode
    /// of AgentToolExecutionResult from disclosing Application Support paths.
    private enum CodingKeys: String, CodingKey {
        case id
        case uri
        case title
        case fileName
        case mimeType
        case size
        case sourceTool
        case workspacePath
        case previewKind
        case actions
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        uri = try container.decode(String.self, forKey: .uri)
        title = try container.decode(String.self, forKey: .title)
        fileName = try container.decode(String.self, forKey: .fileName)
        mimeType = try container.decode(String.self, forKey: .mimeType)
        size = try container.decode(Int64.self, forKey: .size)
        sourceTool = try container.decode(String.self, forKey: .sourceTool)
        workspacePath = try container.decode(String.self, forKey: .workspacePath)
        previewKind = try container.decode(String.self, forKey: .previewKind)
        actions = try container.decodeIfPresent(
            [AgentArtifactAction].self,
            forKey: .actions
        ) ?? []
        hostPath = ""
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(uri, forKey: .uri)
        try container.encode(title, forKey: .title)
        try container.encode(fileName, forKey: .fileName)
        try container.encode(mimeType, forKey: .mimeType)
        try container.encode(size, forKey: .size)
        try container.encode(sourceTool, forKey: .sourceTool)
        try container.encode(workspacePath, forKey: .workspacePath)
        try container.encode(previewKind, forKey: .previewKind)
        try container.encode(actions, forKey: .actions)
    }

    public var embedKind: String {
        switch previewKind {
        case "image": "image"
        case "audio": "audio"
        case "video": "video"
        case "pdf": "pdf"
        case "html": "html"
        case "office_word", "office_sheet", "office_slide": "office"
        default: "link"
        }
    }

    public var inlineRenderable: Bool {
        embedKind != "link"
    }

    public var renderMarkdown: String {
        let normalizedTitle = title
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
        let safeTitle = String(normalizedTitle.prefix(256))
            .replacing("\\", with: "\\\\")
            .replacing("[", with: "\\[")
            .replacing("]", with: "\\]")
        if embedKind == "image" {
            return "![\(safeTitle)](\(uri))"
        }
        return "[\(safeTitle)](\(uri))"
    }

    public var agentValue: AgentValue {
        .object([
            "id": .string(id),
            "uri": .string(uri),
            "title": .string(title),
            "fileName": .string(fileName),
            "mimeType": .string(mimeType),
            "size": .number(Double(size)),
            "sourceTool": .string(sourceTool),
            "workspacePath": .string(workspacePath),
            "previewKind": .string(previewKind),
            "embedKind": .string(embedKind),
            "inlineRenderable": .bool(inlineRenderable),
            "renderMarkdown": .string(renderMarkdown),
            "actions": .array(actions.map(\.agentValue)),
        ])
    }
}
