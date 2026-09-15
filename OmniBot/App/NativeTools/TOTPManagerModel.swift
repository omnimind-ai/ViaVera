import Foundation
import LocalAuthentication
import Observation
#if os(iOS)
import UIKit
#else
import AppKit
#endif

@MainActor
@Observable
final class TOTPManagerModel {
    private(set) var accounts: [TOTPAccount] = []
    private(set) var isUnlocked = false
    private(set) var isUnlocking = false
    private(set) var sessionID = UUID()
    private(set) var copiedAccountID: UUID?
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
        copiedAccountID = nil
        expiresAt = .distantPast
        sessionID = UUID()
    }

    func add(_ account: TOTPAccount) throws {
        accounts = try vault.add([account], context: authorizedContext())
    }

    func remove(_ account: TOTPAccount) {
        do { accounts = try vault.remove(account.id, context: authorizedContext()) }
        catch { alert = NativeToolAlert(error.localizedDescription) }
    }

    func copy(_ account: TOTPAccount) {
        do {
            _ = try authorizedContext()
            let code = try account.algorithm.code(secret: account.secret, time: Date.now.timeIntervalSince1970, digits: account.digits, period: account.period)
#if os(iOS)
            UIPasteboard.general.setItems([["public.utf8-plain-text": code]], options: [.localOnly: true, .expirationDate: Date.now.addingTimeInterval(30)])
#else
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(code, forType: .string)
            let changeCount = pasteboard.changeCount
            Task {
                try? await Task.sleep(for: .seconds(30))
                if pasteboard.changeCount == changeCount { pasteboard.clearContents() }
            }
#endif
            copiedAccountID = account.id
        } catch { alert = NativeToolAlert(error.localizedDescription) }
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

    func restore(_ data: Data, password: String) async throws {
        _ = try authorizedContext()
        let session = sessionID
        let restored = try await Task.detached(priority: .userInitiated) { try TOTPBackup.decrypt(data, password: password) }.value
        guard session == sessionID else { throw NativeToolError("账户已锁定，请重新解锁后恢复。") }
        accounts = try vault.add(restored, context: authorizedContext())
    }

    private func authorizedContext() throws -> LAContext {
        guard isUnlocked, expiresAt > .now, let context else {
            lock()
            throw NativeToolError("账户已锁定，请重新解锁。")
        }
        return context
    }
}
