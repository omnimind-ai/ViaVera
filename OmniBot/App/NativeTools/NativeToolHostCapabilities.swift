import AVFoundation
import Foundation
import Observation
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// Per-tool implementation of the public capability catalog. No package/UI identity checks.
@MainActor @Observable
final class NativeToolHostCapabilities: NativeToolHostCalling {
    let presentation = NativeToolSystemPresentation()
    private let permissions: [String]
    private let otp: NativeToolOTPService
    private var pendingAccounts: [TOTPAccount] = []
    private var pendingSessionID: UUID?
    private var files: [String: Data] = [:]
    private var generation = UUID()
    private var isRequestingCameraPermission = false
    var isAuthorizing: Bool { otp.isUnlocking || isRequestingCameraPermission }
    var sessionID: UUID { otp.sessionID }
    var isCredentialSessionUnlocked: Bool { otp.isUnlocked }

    init(toolID: UUID, permissions: [String]) {
        self.permissions = permissions
        otp = NativeToolOTPService(toolID: toolID)
    }

    func authorizeCamera() async -> Bool {
        let token = generation
        if AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined {
            isRequestingCameraPermission = true
            defer { isRequestingCameraPermission = false }
            let allowed = await AVCaptureDevice.requestAccess(for: .video)
            return allowed && generation == token
        }
        return AVCaptureDevice.authorizationStatus(for: .video) == .authorized
    }

    func invoke(_ operation: String, arguments: [String: AgentValue]) async throws -> AgentValue {
        let entry = try NativeToolCapabilityRegistry.resolve(operation, declared: permissions)
        try NativeToolCapabilityRegistry.validate(arguments, for: entry, evaluated: true)
        let token = generation
        func text(_ key: String) -> String { arguments[key]?.stringValue ?? "" }
        func object(_ values: [String: AgentValue] = [:]) -> AgentValue { .object(values) }
        switch operation {
        case "camera.scanQRCode", "photos.scanQRCode":
            let result = try await presentation.present(operation.hasPrefix("camera") ? .camera : .photo)
            guard generation == token, case let .text(value) = result else { throw CancellationError() }
            return object(["text": .string(value)])
        case "files.openText", "files.openData":
            let result = try await presentation.present(operation == "files.openText" ? .openText : .openData)
            guard generation == token, case let .data(data) = result else { throw CancellationError() }
            return try handle(data)
        case "files.readText":
            let value = try NativeToolTextCodec.decode(data(for: text("handle")))
            guard value.utf8.count <= 32_768 else { throw NativeToolError("可读文本超过 32 KB；大文件请使用支持文件句柄的能力。") }
            return object(["text": .string(value)])
        case "files.save":
            _ = try await presentation.present(.save(data(for: text("handle")), String(text("name").prefix(100))))
            guard generation == token else { throw CancellationError() }
            return object(["saved": .bool(true)])
        case "dialog.confirm":
            let result = try await presentation.present(.confirm(String(text("title").prefix(200)), String(text("message").prefix(1_000))))
            guard generation == token, case let .confirmed(value) = result else { throw CancellationError() }
            return object(["confirmed": .bool(value)])
        case "clipboard.copy":
            let value = text("text")
#if os(iOS)
            UIPasteboard.general.setItems([["public.utf8-plain-text": value]], options: [.localOnly: true, .expirationDate: Date.now.addingTimeInterval(30)])
#else
            let clipboard = NSPasteboard.general
            clipboard.clearContents()
            clipboard.setString(value, forType: .string)
            let change = clipboard.changeCount
            Task {
                try? await Task.sleep(for: .seconds(30))
                if clipboard.changeCount == change { clipboard.clearContents() }
            }
#endif
            return object(["copied": .bool(true)])
        case "otp.unlock":
            await otp.unlock()
            guard generation == token else { throw CancellationError() }
            guard otp.isUnlocked else { throw NativeToolError("未能解锁认证账户，请重试。") }
            Task { await otp.expireSession(otp.sessionID) }
            return snapshot()
        case "otp.lock":
            otp.lock()
            pendingAccounts = []; pendingSessionID = nil; files = [:]
            return snapshot()
        case "otp.snapshot": return snapshot()
        case "otp.previewImport":
            _ = try otp.currentAccounts()
            let additions: [TOTPAccount]
            if arguments["handle"] != nil {
                additions = try TOTPTextImport.parse(data(for: text("handle")))
            } else {
                guard let algorithm = TOTPAlgorithm(rawValue: text("algorithm").isEmpty ? "SHA1" : text("algorithm")),
                      let digits = Int(exactly: arguments["digits"]?.numberValue ?? 6),
                      let period = Int(exactly: arguments["period"]?.numberValue ?? 30) else { throw NativeToolError("认证参数无效。") }
                additions = [try TOTPAccount.parse(text("text"), name: text("name"), issuer: text("issuer"), algorithm: algorithm, digits: digits, period: period)]
            }
            return try stage(additions)
        case "otp.commitImport":
            guard pendingSessionID == otp.sessionID, !pendingAccounts.isEmpty else { throw NativeToolError("没有待导入账户，请重新读取。") }
            _ = try otp.importAccounts(pendingAccounts)
            pendingAccounts = []; pendingSessionID = nil
            return snapshot()
        case "otp.discardImport": pendingAccounts = []; pendingSessionID = nil; return object()
        case "otp.delete":
            guard let id = UUID(uuidString: text("id")) else { throw NativeToolError("账户 ID 无效。") }
            try otp.deleteAccount(id)
            return snapshot()
        case "otp.encryptBackup":
            let data = try await otp.export(password: text("password"))
            guard generation == token else { throw CancellationError() }
            return try handle(data)
        case "otp.previewBackup":
            _ = try otp.currentAccounts()
            let session = otp.sessionID
            let data = try data(for: text("handle"))
            let password = text("password")
            let accounts = try await Task.detached(priority: .userInitiated) { try TOTPBackup.decrypt(data, password: password) }.value
            guard generation == token, otp.sessionID == session else { throw CancellationError() }
            return try stage(accounts)
        default: throw NativeToolError("不支持的能力操作。")
        }
    }

    func suspend() {
        generation = UUID()
        presentation.cancel()
        otp.lock()
        pendingAccounts = []; pendingSessionID = nil; files = [:]
    }

    private func stage(_ additions: [TOTPAccount]) throws -> AgentValue {
        let existing = try otp.currentAccounts()
        let result = try TOTPAccountImport.merging(additions, into: existing)
        pendingAccounts = additions
        pendingSessionID = otp.sessionID
        return .object([
            "message": .string("预计新增 \(result.importedCount) 个账户，跳过 \(result.duplicateCount) 个重复账户。"),
            "accounts": .array(result.accounts.dropFirst(existing.count).map { .object(["id": .string($0.id.uuidString), "name": .string($0.name), "issuer": .string($0.issuer)]) }),
        ])
    }

    private func snapshot() -> AgentValue {
        let accounts = otp.isUnlocked ? ((try? otp.currentAccounts()) ?? []) : []
        if !otp.isUnlocked { pendingAccounts = []; pendingSessionID = nil }
        let now = Date.now.timeIntervalSince1970
        return .object([
            "unlocked": .bool(otp.isUnlocked), "message": .string(otp.importMessage ?? ""),
            "accounts": .array(accounts.map { account in
                .object([
                    "id": .string(account.id.uuidString), "name": .string(account.name), "issuer": .string(account.issuer),
                    "code": .string((try? account.algorithm.code(secret: account.secret, time: now, digits: account.digits, period: account.period)) ?? ""),
                    "progress": .number(1 - now.truncatingRemainder(dividingBy: Double(account.period)) / Double(account.period)),
                ])
            }),
        ])
    }

    private func handle(_ data: Data) throws -> AgentValue {
        guard files.count < 16, data.count <= 1_024 * 1_024,
              files.values.reduce(data.count, { $0 + $1.count }) <= 8 * 1_024 * 1_024 else { throw NativeToolError("临时文件超过上限，请重新打开工具。") }
        let id = UUID().uuidString
        files[id] = data
        return .object(["handle": .string(id)])
    }

    private func data(for handle: String) throws -> Data {
        guard let data = files[handle] else { throw NativeToolError("文件句柄已失效，请重新选择文件。") }
        return data
    }
}
