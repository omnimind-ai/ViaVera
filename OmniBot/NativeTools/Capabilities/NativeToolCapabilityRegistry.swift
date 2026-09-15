import Foundation

/// One catalog drives Agent discovery, package validation and runtime dispatch authorization.
nonisolated enum NativeToolCapabilityRegistry {
    static let entries: [NativeToolCapability] = [
        .init(operation: "camera.scanQRCode", parameters: [:], required: [], result: "{text: string}; user opens camera, any QR text"),
        .init(operation: "photos.scanQRCode", parameters: [:], required: [], result: "{text: string}; user selects a QR image"),
        .init(operation: "files.openText", parameters: [:], required: [], result: "{handle: string}; chosen text file, up to 1 MB"),
        .init(operation: "files.openData", parameters: [:], required: [], result: "{handle: string}; chosen file, up to 1 MB"),
        .init(operation: "files.readText", parameters: ["handle": "string"], required: ["handle"], result: "{text: string}; UTF-8/UTF-16, up to 32 KB"),
        .init(operation: "files.save", parameters: ["handle": "string", "name": "string"], required: ["handle", "name"], result: "{saved: bool}; user chooses destination"),
        .init(operation: "clipboard.copy", parameters: ["text": "string"], required: ["text"], result: "{copied: bool}; local clipboard, expires after 30 seconds"),
        .init(operation: "dialog.confirm", parameters: ["title": "string", "message": "string"], required: ["title", "message"], result: "{confirmed: bool}"),
        .init(operation: "otp.unlock", parameters: [:], required: [], result: "{unlocked, accounts, message}; device authentication"),
        .init(operation: "otp.lock", parameters: [:], required: [], result: "{unlocked: false, accounts: [], message}"),
        .init(operation: "otp.snapshot", parameters: [:], required: [], result: "{unlocked, accounts: [{id,name,issuer,code,progress}], message}; never contains secrets", passive: true),
        .init(operation: "otp.previewImport", parameters: ["text": "string", "handle": "string", "name": "string", "issuer": "string", "algorithm": "string", "digits": "number", "period": "number"], required: [], result: "{accounts: [{id,name,issuer}], message}; parse URI, raw secret or TXT; stage in host memory"),
        .init(operation: "otp.commitImport", parameters: [:], required: [], result: "{unlocked, accounts, message}; save staged accounts to this tool's Keychain vault"),
        .init(operation: "otp.discardImport", parameters: [:], required: [], result: "{}; clear staged accounts"),
        .init(operation: "otp.delete", parameters: ["id": "string"], required: ["id"], result: "{unlocked, accounts, message}"),
        .init(operation: "otp.encryptBackup", parameters: ["password": "string"], required: ["password"], result: "{handle: string}; encrypted backup in host memory"),
        .init(operation: "otp.previewBackup", parameters: ["handle": "string", "password": "string"], required: ["handle", "password"], result: "{accounts: [{id,name,issuer}], message}; decrypted accounts staged for otp.commitImport"),
    ]

    static var permissions: Set<String> { Set(entries.map(\.permission)) }

    static func resolve(_ operation: String, declared: [String]) throws -> NativeToolCapability {
        guard let entry = entries.first(where: { $0.operation == operation }), declared.contains(entry.permission) else {
            throw NativeToolError("能力未声明或操作不受支持：\(operation)")
        }
        return entry
    }

    static func validate(_ arguments: [String: AgentValue], for entry: NativeToolCapability, evaluated: Bool) throws {
        guard Set(arguments.keys).isSubset(of: Set(entry.parameters.keys)), entry.required.isSubset(of: Set(arguments.keys)) else {
            throw NativeToolError("能力 \(entry.operation) 的参数缺失或不受支持。")
        }
        guard evaluated else { return }
        for (name, value) in arguments {
            let valid = entry.parameters[name] == "number" ? value.numberValue != nil : value.stringValue != nil
            guard valid else { throw NativeToolError("能力参数 \(name) 的类型错误。") }
        }
    }
}
