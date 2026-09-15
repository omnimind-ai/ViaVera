import SwiftUI

struct ChatComposerSkillCapsule: View {
    let reference: ChatComposerSkillReference
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkles")
                .accessibilityHidden(true)
            Text(reference.id)
                .lineLimit(1)
            Button("移除 \(reference.id) Skill", systemImage: "xmark", action: onRemove)
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .padding(4)
        }
        .font(.subheadline.weight(.medium))
        .foregroundStyle(.blue)
        .padding(.leading, 12)
        .padding(.trailing, 6)
        .padding(.vertical, 5)
        .background(.blue.opacity(0.12), in: .capsule)
        .overlay { Capsule().strokeBorder(.blue.opacity(0.18), lineWidth: 1) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("引用的 Skill")
    }
}
