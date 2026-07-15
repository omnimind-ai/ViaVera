import SwiftUI

struct AlpineEnvironmentPackageRow: View {
    let definition: AlpineEnvironmentPackageDefinition
    let inventoryItem: AlpineEnvironmentInventoryItem?
    let isSelected: Bool
    let isDetecting: Bool
    let isDisabled: Bool
    let toggleSelection: () -> Void

    var body: some View {
        Button(action: toggleSelection) {
            HStack(spacing: AppDesign.standardSpacing) {
                leadingIndicator

                Text(definition.title)
                    .font(.body)
                    .foregroundStyle(.primary)

                Spacer(minLength: AppDesign.standardSpacing)

                trailingStatus
            }
            .frame(minHeight: rowMinimumHeight)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .environment(\.defaultMinListRowHeight, rowMinimumHeight)
        .disabled(isDisabled || isReady)
        .accessibilityLabel("\(definition.title)，\(definition.detail)")
        .accessibilityValue(accessibilityStatus)
    }

    @ViewBuilder
    private var leadingIndicator: some View {
        if isDetecting, inventoryItem == nil {
            ProgressView()
                .controlSize(.small)
        } else if isReady {
            Image(systemName: "checkmark.square.fill")
                .foregroundStyle(.green)
        } else {
            Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
        }
    }

    @ViewBuilder
    private var trailingStatus: some View {
        if !isDetecting || inventoryItem != nil {
            if usesCompactLayout {
                HStack(spacing: AppDesign.compactSpacing / 2) {
                    Text(isReady ? "已就绪" : "未安装")
                        .font(.caption)
                        .foregroundStyle(isReady ? .green : .secondary)

                    if let version = inventoryItem?.version {
                        Text(version)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
            } else {
                VStack(alignment: .trailing, spacing: AppDesign.compactSpacing) {
                    Text(isReady ? "已就绪" : "未安装")
                        .font(.caption)
                        .foregroundStyle(isReady ? .green : .secondary)

                    if let version = inventoryItem?.version {
                        Text(version)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .lineLimit(2)
                            .multilineTextAlignment(.trailing)
                    }
                }
            }
        }
    }

    private var isReady: Bool {
        inventoryItem?.isReady == true
    }

    private var rowMinimumHeight: Double {
        usesCompactLayout
            ? AppDesign.alpinePackageRowMinimumHeight
            : AppDesign.minimumTouchTarget
    }

    private var usesCompactLayout: Bool {
        definition.groupTitle == "开发环境" || definition.groupTitle == "SSH"
    }

    private var accessibilityStatus: String {
        if isDetecting, inventoryItem == nil {
            "正在检测"
        } else if isReady {
            inventoryItem?.version.map { "已就绪，\($0)" } ?? "已就绪"
        } else {
            isSelected ? "未安装，已选择" : "未安装，未选择"
        }
    }
}
