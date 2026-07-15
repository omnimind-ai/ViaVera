import SwiftUI

struct TerminalAccessoryKeyBar: View {
    let model: InteractiveTerminalModel

    private let columns = Array(
        repeating: GridItem(.flexible(minimum: AppDesign.minimumTouchTarget), spacing: 0),
        count: AppDesign.terminalAccessoryColumnCount
    )

    var body: some View {
        LazyVGrid(columns: columns, spacing: 0) {
            ForEach(TerminalAccessoryKey.layout) { item in
                TerminalAccessoryKeyButton(
                    item: item,
                    isSelected: isSelected(item),
                    action: { model.activate(item) }
                )
                .disabled(!model.state.acceptsInput)
            }
        }
        .padding(.horizontal, AppDesign.compactSpacing / 2)
        .padding(.vertical, AppDesign.compactSpacing / 2)
        .background(.bar)
        .overlay(alignment: .top) {
            Divider()
        }
    }

    private func isSelected(_ item: TerminalAccessoryKey) -> Bool {
        switch item {
        case .control:
            model.isControlLocked
        case .alternate:
            model.isAlternateLocked
        case .key:
            false
        }
    }
}
