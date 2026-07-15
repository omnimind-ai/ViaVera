import SwiftUI

struct IOSPermissionSettingsRow: View {
    @Bindable var permission: IOSPermissionToggleState
    let isDisabled: Bool
    let setEnabled: (Bool) -> Void

    var body: some View {
        Toggle(isOn: $permission.isEnabled) {
            Label {
                VStack(alignment: .leading, spacing: AppDesign.compactSpacing / 2) {
                    Text(permission.kind.title)
                    Text(permission.kind.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: permission.kind.systemImage)
                    .symbolRenderingMode(.hierarchical)
            }
        }
        .disabled(isDisabled)
        .onChange(of: permission.isEnabled) { oldValue, newValue in
            guard oldValue != newValue else { return }
            setEnabled(newValue)
        }
        .accessibilityHint(
            permission.isEnabled
                ? "关闭后，Agent 将无法访问\(permission.kind.title)数据。"
                : "打开后，Agent 可以访问\(permission.kind.title)数据；如有需要，系统会显示授权页面。"
        )
    }
}
