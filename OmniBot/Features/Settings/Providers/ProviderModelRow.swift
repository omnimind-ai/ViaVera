import SwiftUI

struct ProviderModelRow: View {
    let model: ModelOption
    let open: () -> Void
    let toggleVisibility: () -> Void
    let delete: () -> Void

    var body: some View {
        HStack(spacing: AppDesign.compactSpacing) {
            Button(action: open) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.displayName)
                        .foregroundStyle(.primary)
                    Text(model.id)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)

            HStack(spacing: 0) {
                Button(
                    model.isHidden ? "显示模型" : "隐藏模型",
                    systemImage: model.isHidden ? "eye.slash" : "eye",
                    action: toggleVisibility
                )
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .font(.footnote)
                .frame(minWidth: 44, minHeight: 44)

                Button(
                    "删除模型",
                    systemImage: "trash",
                    role: .destructive,
                    action: delete
                )
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .font(.footnote)
                .frame(minWidth: 44, minHeight: 44)
            }

            Image(systemName: "chevron.right")
                .font(.footnote)
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
#if os(iOS)
        .listRowInsets(
            EdgeInsets(
                top: AppDesign.compactSpacing,
                leading: AppDesign.settingsInputHorizontalPadding,
                bottom: AppDesign.compactSpacing,
                trailing: AppDesign.settingsInputHorizontalPadding
            )
        )
#endif
    }
}
