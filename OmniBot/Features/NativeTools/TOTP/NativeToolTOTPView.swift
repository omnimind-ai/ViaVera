import SwiftUI

struct NativeToolTOTPView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var model: TOTPManagerModel
    @State private var isAdding = false
    @State private var isBackingUp = false
    @State private var search = ""
    @State private var deleting: TOTPAccount?
    @State private var isDeleting = false
    let title: String

    init(toolID: UUID, title: String) {
        self.title = title
        _model = State(initialValue: TOTPManagerModel(toolID: toolID))
    }

    var body: some View {
        @Bindable var model = model
        GroupBox {
            VStack(alignment: .leading, spacing: 16) {
                if model.isUnlocked {
                    HStack {
                        Button("添加账户", systemImage: "plus") { isAdding = true }
                        Spacer()
                        Menu("账户操作", systemImage: "ellipsis.circle") {
                            Button("备份与恢复", systemImage: "externaldrive") { isBackingUp = true }
                            Button("锁定", systemImage: "lock", action: model.lock)
                        }
                    }
                    TextField("搜索账户", text: $search).textFieldStyle(.roundedBorder)
                    if model.accounts.isEmpty {
                        Text("添加账户后，在这里查看和复制验证码。")
                            .foregroundStyle(.secondary).padding(.vertical)
                    }
                    LazyVStack(spacing: 16) {
                        ForEach(filteredAccounts) { account in
                            TOTPAccountRowView(account: account, isCopied: model.copiedAccountID == account.id, onCopy: { model.copy(account) })
                                .contextMenu {
                                    Button("删除账户", systemImage: "trash", role: .destructive) {
                                        deleting = account
                                        isDeleting = true
                                    }
                                }
                        }
                    }
                } else {
                    Label("身份验证后查看本机账户", systemImage: "lock.shield")
                        .foregroundStyle(.secondary)
                    Button(model.isUnlocking ? "正在解锁…" : "解锁验证码", systemImage: "lock.open") {
                        Task { await model.unlock() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.isUnlocking)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 8)
        } label: { Label(title, systemImage: "lock.shield") }
        .privacySensitive()
        .sheet(isPresented: $isAdding) { TOTPImportView(model: model) }
        .sheet(isPresented: $isBackingUp) { TOTPBackupView(model: model) }
        .confirmationDialog("删除认证账户？", isPresented: $isDeleting, titleVisibility: .visible) {
            Button("删除", role: .destructive) {
                if let deleting { model.remove(deleting) }
                deleting = nil
            }
        } message: { Text("请确认已保存备份或该服务的恢复码，避免无法登录。") }
        .alert(item: $model.alert) { alert in
            Alert(title: Text("两步认证"), message: Text(alert.message), dismissButton: .default(Text("好")))
        }
        .task(id: model.isUnlocked) { await model.expireSession(model.sessionID) }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background || (phase == .inactive && !model.isUnlocking) { model.lock() }
        }
        .onChange(of: model.isUnlocked) { _, unlocked in
            if !unlocked { isAdding = false; isBackingUp = false; deleting = nil; search = "" }
        }
        .onDisappear { model.lock() }
    }

    private var filteredAccounts: [TOTPAccount] {
        model.accounts.filter { search.isEmpty || $0.name.localizedStandardContains(search) || $0.issuer.localizedStandardContains(search) }
    }
}
