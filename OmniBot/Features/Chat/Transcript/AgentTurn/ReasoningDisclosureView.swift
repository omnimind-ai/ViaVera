import SwiftUI

struct ReasoningDisclosureView: View {
    let text: String
    let isStreaming: Bool
    let autoCollapse: Bool
    let startedAt: Date
    let updatedAt: Date

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isExpanded: Bool
    @State private var reasoningStartedAt: Date
    @State private var completedAt: Date?

    init(
        text: String,
        isStreaming: Bool,
        autoCollapse: Bool,
        startedAt: Date,
        updatedAt: Date
    ) {
        self.text = text
        self.isStreaming = isStreaming
        self.autoCollapse = autoCollapse
        self.startedAt = startedAt
        self.updatedAt = updatedAt
        _isExpanded = State(initialValue: isStreaming && !autoCollapse)
        _reasoningStartedAt = State(initialValue: isStreaming ? .now : startedAt)
        _completedAt = State(initialValue: isStreaming && !autoCollapse ? nil : updatedAt)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                isExpanded.toggle()
            } label: {
                HStack(spacing: 6) {
                    if isThinking {
                        Image(systemName: "sparkles")
                            .symbolEffect(
                                .pulse,
                                options: .repeating,
                                isActive: !reduceMotion
                            )
                            .accessibilityHidden(true)
                    }

                    Text(isThinking ? "正在思考" : "已完成思考")
                        .font(.caption)
                        .bold()

                    elapsedLabel

                    if !isThinking {
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                            .animation(collapseAnimation, value: isExpanded)
                            .accessibilityHidden(true)
                    }

                    Spacer(minLength: AppDesign.compactSpacing)
                }
                .foregroundStyle(.secondary)
                .frame(minHeight: AppDesign.transcriptStatusMinimumHeight)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .padding(.vertical, AppDesign.transcriptStatusVerticalPadding)
            .accessibilityValue(
                isThinking ? "内容正在更新" : (isExpanded ? "已展开" : "已收起")
            )
            .accessibilityHint("双击切换思考内容")

            AgentTurnRevealLayout(progress: isExpanded ? 1 : 0) {
                PacedReasoningText(text: text, isStreaming: isStreaming)
                    .padding(.leading, AppDesign.standardSpacing)
                    .padding(.bottom, AppDesign.compactSpacing)
                    .overlay(alignment: .leading) {
                        Rectangle()
                            .fill(.tertiary)
                            .frame(width: 2)
                            .accessibilityHidden(true)
                    }
            }
            .clipped()
            .opacity(isExpanded ? 1 : 0)
            .allowsHitTesting(isExpanded)
            .accessibilityHidden(!isExpanded)
            .animation(collapseAnimation, value: isExpanded)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onChange(of: autoCollapse) { _, shouldCollapse in
            guard shouldCollapse else { return }
            isExpanded = false
            if completedAt == nil {
                completedAt = updatedAt
            }
        }
        .onChange(of: isStreaming) { _, isStreaming in
            if isStreaming {
                reasoningStartedAt = .now
                completedAt = nil
            } else {
                isExpanded = false
                if completedAt == nil {
                    completedAt = updatedAt
                }
            }
        }
    }

    @ViewBuilder
    private var elapsedLabel: some View {
        if isThinking {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(Self.elapsedText(from: reasoningStartedAt, to: context.date))
                    .font(.caption.monospacedDigit())
            }
        } else {
            Text(Self.elapsedText(from: reasoningStartedAt, to: completedAt ?? updatedAt))
                .font(.caption.monospacedDigit())
        }
    }

    private var isThinking: Bool {
        isStreaming && !autoCollapse
    }

    private var collapseAnimation: Animation? {
        reduceMotion ? nil : .easeInOut(duration: 0.22)
    }

    private static func elapsedText(from start: Date, to end: Date) -> String {
        let seconds = max(0, Int(end.timeIntervalSince(start)))
        if seconds >= 60 {
            return "\(seconds / 60)分\(seconds % 60)秒"
        }
        return "\(seconds)秒"
    }
}
