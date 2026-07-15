import SwiftUI

struct ChatCommandEffortPicker: View {
    let selectedEffort: AgentReasoningEffort?
    let isDisabled: Bool
    let onSelect: (AgentReasoningEffort) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AgentReasoningEffort.commandOptions, id: \.self) { effort in
                let isSelected = selectedEffort == effort
                Button(effort.rawValue) {
                    onSelect(effort)
                }
                .font(.caption2)
                .bold(isSelected)
                .lineLimit(1)
                .foregroundStyle(isSelected ? Color.white : Color.secondary)
                .frame(maxWidth: .infinity)
                .frame(height: 18)
                .background(isSelected ? Color.accentColor : Color.clear, in: .capsule)
                .overlay {
                    Capsule()
                        .strokeBorder(
                            isSelected ? Color.primary.opacity(0.20) : Color.clear,
                            lineWidth: 0.75
                        )
                }
                .contentShape(.rect)
                .buttonStyle(.plain)
                .frame(height: AppDesign.minimumTouchTarget)
                .padding(.vertical, -(AppDesign.minimumTouchTarget - 18) / 2)
                .disabled(isDisabled)
                .accessibilityLabel("思考强度 \(effort.rawValue)")
                .accessibilityValue(isSelected ? "已选择" : "")
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(2)
        .background(Color.accentColor.opacity(0.08), in: .capsule)
        .animation(
            reduceMotion ? nil : .easeOut(duration: 0.18),
            value: selectedEffort
        )
        .accessibilityElement(children: .contain)
    }
}
