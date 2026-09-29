import SwiftUI

struct SidebarHeaderView: View {
    @Environment(AppModel.self) private var appModel
    @FocusState private var isSearchFocused: Bool
    @Binding var searchText: String

    var body: some View {
        HStack(spacing: AppDesign.compactSpacing) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            TextField("搜索会话", text: $searchText)
                .textFieldStyle(.plain)
                .focused($isSearchFocused)

            if !searchText.isEmpty {
                Button("清除搜索", systemImage: "xmark.circle.fill", action: clearSearch)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("清除搜索")
            }
        }
        .padding(.horizontal, 10)
        .frame(minHeight: 32)
        .background(.quaternary, in: .rect(cornerRadius: AppDesign.compactCornerRadius))
        .padding(.horizontal, AppDesign.sidebarHorizontalInset)
        .padding(.top, AppDesign.compactSpacing)
        .padding(.bottom, AppDesign.compactSpacing)
#if os(macOS)
        .task(id: appModel.sidebarSearchRequestID) {
            if appModel.sidebarSearchRequestID > 0 { isSearchFocused = true }
        }
#endif
    }

    private func clearSearch() {
        searchText = ""
    }
}
