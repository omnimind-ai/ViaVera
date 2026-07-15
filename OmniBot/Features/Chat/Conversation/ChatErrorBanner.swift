import SwiftUI

struct ChatErrorBanner: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text("运行失败")
                    .font(.callout)
                    .bold()
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            Spacer(minLength: 8)

            Button("重试", systemImage: "arrow.clockwise", action: onRetry)
                .buttonStyle(.bordered)
                .frame(minHeight: 44)
                .accessibilityHint("使用最后一条用户消息重新运行")
        }
        .frame(maxWidth: AppDesign.composerMaximumWidth, minHeight: 44, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(.thinMaterial, in: .rect(cornerRadius: AppDesign.mediumCornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: AppDesign.mediumCornerRadius)
                .strokeBorder(Color.red.opacity(0.18), lineWidth: 1)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, AppDesign.contentPadding)
    }
}
