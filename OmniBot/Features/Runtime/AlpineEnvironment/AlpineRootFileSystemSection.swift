import SwiftUI

struct AlpineRootFileSystemSection: View {
    let manager: AlpineRootFileSystemManager

    @State private var isConfirmingReset = false

    var body: some View {
        Section {
            LabeledContent("占用空间") {
                if manager.isRefreshingSize {
                    ProgressView()
                        .controlSize(.small)
                } else if let sizeInBytes = manager.sizeInBytes {
                    Text(sizeInBytes, format: .byteCount(style: .file))
                } else {
                    Text("未知")
                        .foregroundStyle(.secondary)
                }
            }

            Button(
                manager.isResetScheduled ? "Rootfs 已等待重置" : "重置 Rootfs",
                systemImage: "arrow.counterclockwise",
                role: .destructive,
                action: requestReset
            )
            .disabled(manager.isResetScheduled || manager.isSchedulingReset)

            if manager.isResetScheduled {
                Label(
                    "请重新启动应用，Rootfs 将恢复为内置状态。",
                    systemImage: "checkmark.circle.fill"
                )
                .foregroundStyle(.secondary)
            }

            if let errorMessage = manager.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            }
        } header: {
            Text("Rootfs 管理")
        } footer: {
            Text("重置会移除 Alpine Linux 中安装的软件包和系统配置，但不会删除工作区文件。")
        }
        .confirmationDialog(
            "重置 Rootfs 系统？",
            isPresented: $isConfirmingReset,
            titleVisibility: .visible
        ) {
            Button("重置 Rootfs", role: .destructive, action: scheduleReset)
            Button("取消", role: .cancel) { }
        } message: {
            Text("重置将在下次启动应用时生效，并恢复为应用内置的 Alpine Linux 系统。工作区文件会被保留。")
        }
    }

    private func requestReset() {
        isConfirmingReset = true
    }

    private func scheduleReset() {
        Task {
            await manager.scheduleReset()
        }
    }
}
