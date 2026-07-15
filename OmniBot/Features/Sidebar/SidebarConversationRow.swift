import SwiftUI

struct SidebarConversationRow: View {
    let conversation: ConversationRecord

    var body: some View {
#if os(iOS)
        HStack(alignment: .center, spacing: AppDesign.standardSpacing) {
            SidebarConversationAvatar(
                symbol: "bubble.left.fill",
                color: leadingSymbolColor,
                size: AppDesign.mobileSidebarAvatarSize
            )

            VStack(alignment: .leading, spacing: 3) {
                Text(conversation.title)
                    .font(.body)
                    .bold()
                    .lineLimit(1)

                Text(previewText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)

            if conversation.isPinned {
                Image(systemName: "pin.fill")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }

            Text(updatedDateLabel)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .frame(
            maxWidth: .infinity,
            minHeight: AppDesign.mobileSidebarAvatarSize,
            alignment: .leading
        )
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityValue(conversation.isPinned ? "已置顶" : "")
#else
        HStack(alignment: .center, spacing: AppDesign.standardSpacing) {
            SidebarConversationAvatar(
                symbol: "bubble.left.fill",
                color: leadingSymbolColor,
                size: 34
            )

            VStack(alignment: .leading, spacing: 3) {
                Text(conversation.title)
                    .font(.body)
                    .bold()
                    .lineLimit(1)

                Text(previewText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)

            if conversation.isPinned {
                Image(systemName: "pin.fill")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }

            Text(updatedDateLabel)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityValue(conversation.isPinned ? "已置顶" : "")
#endif
    }

    private var updatedDateLabel: String {
        let calendar = Calendar.autoupdatingCurrent
        let updatedAt = conversation.updatedAt

        if calendar.isDateInToday(updatedAt) {
            return "今天"
        }
        if calendar.isDateInYesterday(updatedAt) {
            return "昨天"
        }

        let month = calendar.component(.month, from: updatedAt)
        let day = calendar.component(.day, from: updatedAt)
        return "\(month)月\(day)日"
    }

    private var previewText: String {
        if conversation.status == .running {
            return statusTitle
        }

        guard let content = conversation.orderedMessages.last(where: { message in
            guard message.role != .tool, let content = message.content else { return false }
            return !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        })?.content else {
            return "等待你描述任务"
        }

        return content.replacing("\n", with: " ")
    }

    private var statusTitle: String {
        switch conversation.status {
        case .idle:
            "待处理"
        case .running:
            "运行中"
        case .completed:
            "已完成"
        case .failed:
            "失败"
        case .cancelled:
            "已取消"
        }
    }

    private var leadingSymbolColor: Color {
        conversation.messages.isEmpty
            ? .accentColor
            : SidebarConversationAvatarPalette.color(for: conversation.id)
    }
}
