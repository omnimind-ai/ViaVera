import SwiftUI

struct CloudSyncSettingsView: View {
    @Environment(AppModel.self) private var appModel
    @State private var backupToRestore: CloudSyncBackup?
    @State private var visibleBackupCount = 20

    var body: some View {
        @Bindable var sync = appModel.cloudSync
        @Bindable var background = BackgroundExecutionController.shared
        SettingsPageLayout(title: String(localized: "备份与后台执行")) {
#if os(iOS)
            Section {
                Toggle("后台继续执行任务", isOn: $background.isEnabled)
                if background.isKeepingAlive {
                    Label("正在保持后台任务运行", systemImage: "waveform")
                }
                if let error = background.errorMessage {
                    Text(error).foregroundStyle(.secondary)
                }
            } header: {
                Text("后台执行")
            } footer: {
                Text("任务执行期间通过静音音频会话延长后台运行时间，完成后自动释放。系统强制退出或资源限制仍可能中断任务，已保存的进度可以在返回后重试。")
            }
#endif
            Section {
                Toggle("iCloud 备份与同步", isOn: $sync.isEnabled)
                Text(sync.statusMessage).foregroundStyle(.secondary)
                if let date = sync.lastSyncDate {
                    LabeledContent("上次完成") {
                        Text(date, format: .dateTime.month().day().hour().minute())
                    }
                }
                Button {
                    Task { await sync.synchronize() }
                } label: {
                    Label(sync.isSyncing ? String(localized: "正在同步…") : String(localized: "立即同步并备份"), systemImage: "arrow.triangle.2.circlepath.icloud")
                }
                .disabled(!sync.isEnabled || sync.isSyncing)
                if let error = sync.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }
            } header: {
                Text("iCloud")
            } footer: {
                Text("在使用同一 Apple 账户的 iPhone、iPad 和 Mac 间同步聊天、附件、模型服务配置及 API Key、默认模型、Soul、Memory、Skills 和外观。API Key 恢复到设备钥匙串，本地备份缓存加密保存。设备权限和 Alpine 环境保留在各设备。任务或设置编辑完成后再同步。")
            }
            Section {
                LabeledContent("保留规则", value: String(localized: "最近 30 天，最多 50 份"))
                if sync.backups.isEmpty {
                    Text("首次同步后显示可恢复的备份。").foregroundStyle(.secondary)
                }
                ForEach(sync.backups.prefix(visibleBackupCount)) { backup in
                    Button {
                        backupToRestore = backup
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(backup.date, format: .dateTime.year().month().day().hour().minute().second())
                            Text(backup.deviceName).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .disabled(sync.isSyncing || !sync.isEnabled)
                }
                if sync.backups.count > visibleBackupCount {
                    Button("显示更多备份") { visibleBackupCount += 20 }
                }
            } header: {
                Text("历史备份")
            } footer: {
                Text("同步成功后自动清理超过 30 天或最近 50 份以外的备份，至少保留最新一份。当前数据、删除标记及保留备份引用的内容不会被清理。恢复前先保存当前版本；恢复不会删除后来新增的其他内容。")
            }
        }
        .alert("恢复此备份？", isPresented: isRestorePresented, presenting: backupToRestore) { backup in
            Button("恢复备份", role: .destructive) {
                Task { await sync.restore(backup) }
                backupToRestore = nil
            }
            Button("取消", role: .cancel) { backupToRestore = nil }
        } message: { _ in
            Text("备份中的聊天、配置及已备份的 API Key 将恢复到当时的版本。当前版本会先保留在历史备份中。")
        }
    }

    private var isRestorePresented: Binding<Bool> {
        Binding(get: { backupToRestore != nil }, set: { if !$0 { backupToRestore = nil } })
    }
}
