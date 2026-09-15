import Foundation
import LocalAuthentication
import Observation

@MainActor
@Observable
final class NativeToolOTPService {
    private(set) var accounts: [TOTPAccount] = []
    private(set) var isUnlocked = false
    private(set) var isUnlocking = false
    private(set) var sessionID = UUID()
    private(set) var importMessage: String?
    var alert: NativeToolAlert?
    private let vault: TOTPKeychainVault
    private var context: LAContext?
    private var expiresAt = Date.distantPast

    init(toolID: UUID) { vault = TOTPKeychainVault(toolID: toolID) }

    func unlock() async {
        guard !isUnlocking else { return }
        let id = UUID()
        sessionID = id
        isUnlocking = true
        let authentication = LAContext()
        context = authentication
        defer { if sessionID == id { isUnlocking = false } }
        do {
            var error: NSError?
            guard authentication.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
                throw NativeToolError("请先为设备设置解锁密码，再使用两步认证。")
            }
            let success = try await authentication.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "解锁本工具的两步认证账户")
            guard success, sessionID == id else { return }
            accounts = try vault.load(context: authentication)
            expiresAt = .now.addingTimeInterval(120)
            isUnlocked = true
        } catch {
            guard sessionID == id else { return }
            lock()
            alert = NativeToolAlert("未能解锁验证码账户。请重试或检查设备的身份验证设置。")
        }
    }

    func lock() {
        context?.invalidate()
        context = nil
        accounts = []
        isUnlocked = false
        isUnlocking = false
        importMessage = nil
        expiresAt = .distantPast
        sessionID = UUID()
    }

    func currentAccounts() throws -> [TOTPAccount] {
        _ = try authorizedContext()
        return accounts
    }

    func deleteAccount(_ id: UUID) throws {
        accounts = try vault.remove(id, context: authorizedContext())
    }

    func importAccounts(_ additions: [TOTPAccount]) throws -> TOTPAccountImportResult {
        let result = try vault.importAccounts(additions, context: authorizedContext())
        accounts = result.accounts
        importMessage = result.summary
        return result
    }

    func expireSession(_ id: UUID) async {
        guard isUnlocked else { return }
        let delay = max(0, expiresAt.timeIntervalSinceNow)
        do { try await Task.sleep(for: .seconds(delay)) } catch { return }
        if sessionID == id { lock() }
    }

    func export(password: String) async throws -> Data {
        let accounts = try vault.load(context: authorizedContext())
        return try await Task.detached(priority: .userInitiated) { try TOTPBackup.encrypt(accounts, password: password) }.value
    }

    private func authorizedContext() throws -> LAContext {
        guard isUnlocked, expiresAt > .now, let context else {
            lock()
            throw NativeToolError("账户已锁定，请重新解锁。")
        }
        return context
    }
}
