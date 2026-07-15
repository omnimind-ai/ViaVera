import SwiftUI
import WebKit

struct BrowserCardView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss

    let conversationID: UUID

    @State private var snapshot = AppleBrowserPresentationSnapshot.empty
    @State private var addressText = ""
    @State private var isPerformingOperation = false
    @State private var presentedError: BrowserPresentationAlert?
    @FocusState private var isAddressFieldFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                browserChrome

                if snapshot.riskChallengeDetected {
                    Label(
                        "检测到验证页面，请在这里手动完成后再让 Agent 继续。",
                        systemImage: "hand.raised.fill"
                    )
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.orange.opacity(0.09))
                }

                Divider()

                browserContent
            }
            .background(.background)
            .navigationTitle(snapshot.title.isEmpty ? "浏览器" : snapshot.title)
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭", systemImage: "xmark") {
                        dismiss()
                    }
                }
            }
            .task(id: conversationID) {
                await runPresentationLoop()
            }
            .alert(item: $presentedError) { error in
                Alert(
                    title: Text("浏览器操作失败"),
                    message: Text(error.message),
                    dismissButton: .default(Text("好"))
                )
            }
        }
#if os(macOS)
        .frame(
            width: AppDesign.browserPopoverWidth,
            height: AppDesign.browserPopoverHeight
        )
#else
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
#endif
    }

    private var browserChrome: some View {
        HStack(spacing: 4) {
            browserControl(
                "后退",
                systemImage: "chevron.left",
                isEnabled: snapshot.canGoBack
            ) {
                perform { session in
                    try await session.goBackFromPresentation(
                        conversationID: conversationID
                    )
                }
            }

            browserControl(
                "前进",
                systemImage: "chevron.right",
                isEnabled: snapshot.canGoForward
            ) {
                perform { session in
                    try await session.goForwardFromPresentation(
                        conversationID: conversationID
                    )
                }
            }

            HStack(spacing: 7) {
                Image(systemName: securePageSymbol)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)

                TextField("输入网址", text: $addressText)
                    .textFieldStyle(.plain)
                    .focused($isAddressFieldFocused)
                    .submitLabel(.go)
                    .onSubmit(navigateToAddress)

                if isPerformingOperation || snapshot.isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("网页正在载入")
                }
            }
            .padding(.horizontal, 10)
            .frame(minHeight: 36)
            .background(.quaternary, in: .rect(cornerRadius: 10))

            browserControl(
                snapshot.isLoading ? "停止载入" : "重新载入",
                systemImage: snapshot.isLoading ? "xmark" : "arrow.clockwise",
                isEnabled: snapshot.activeTab != nil
            ) {
                if snapshot.isLoading {
                    appModel.browserSession.stopLoadingFromPresentation(
                        conversationID: conversationID
                    )
                    synchronizeSnapshot()
                } else {
                    perform { session in
                        try await session.reloadFromPresentation(
                            conversationID: conversationID
                        )
                    }
                }
            }

            tabMenu
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
    }

    @ViewBuilder
    private var browserContent: some View {
        if let tab = snapshot.activeTab {
            WebView(tab.page)
                .id(tab.id)
                .accessibilityLabel("浏览器网页内容")
        } else {
            ContentUnavailableView {
                Label("没有打开的网页", systemImage: "safari")
            } description: {
                Text("新建标签页后，可以输入网址并直接操作网页。")
            } actions: {
                Button("新建标签页", systemImage: "plus") {
                    createTab()
                }
            }
        }
    }

    private var tabMenu: some View {
        Menu {
            Button("新建标签页", systemImage: "plus") {
                createTab()
            }
            .disabled(snapshot.tabs.count >= AppleBrowserSession.maximumSimultaneousTabs)

            if snapshot.activeTabID != nil {
                Button("关闭当前标签页", systemImage: "xmark.square") {
                    appModel.browserSession.closeActiveTabFromPresentation(
                        conversationID: conversationID
                    )
                    synchronizeSnapshot()
                }
            }

            if !snapshot.tabs.isEmpty {
                Divider()
                ForEach(snapshot.tabs) { tab in
                    Button {
                        selectTab(tab.id)
                    } label: {
                        Label(
                            tab.title.isEmpty ? tab.url : tab.title,
                            systemImage: tab.isActive ? "checkmark" : "globe"
                        )
                    }
                }
            }
        } label: {
            Label(
                "标签页（\(snapshot.tabs.count)）",
                systemImage: "square.on.square"
            )
            .labelStyle(.iconOnly)
            .frame(
                minWidth: AppDesign.minimumTouchTarget,
                minHeight: AppDesign.minimumTouchTarget
            )
        }
        .menuIndicator(.hidden)
        .accessibilityLabel("管理标签页，共 \(snapshot.tabs.count) 个")
    }

    private var securePageSymbol: String {
        snapshot.url.lowercased().hasPrefix("https://") ? "lock.fill" : "globe"
    }

    private func browserControl(
        _ title: String,
        systemImage: String,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .labelStyle(.iconOnly)
                .frame(
                    minWidth: AppDesign.minimumTouchTarget,
                    minHeight: AppDesign.minimumTouchTarget
                )
        }
        .buttonStyle(.plain)
        .foregroundStyle(isEnabled ? Color.primary : Color.secondary.opacity(0.45))
        .disabled(!isEnabled)
        .accessibilityLabel(title)
    }

    @MainActor
    private func runPresentationLoop() async {
        do {
            _ = try appModel.browserSession.prepareForPresentation(
                conversationID: conversationID
            )
            synchronizeSnapshot()
        } catch {
            present(error)
        }

        var refreshCount = 0
        while !Task.isCancelled {
            do {
                try await Task.sleep(for: .milliseconds(300))
            } catch {
                return
            }
            refreshCount &+= 1
            if refreshCount.isMultiple(of: 4) {
                await appModel.browserSession.refreshRiskFromPresentation(
                    conversationID: conversationID
                )
            }
            synchronizeSnapshot()
        }
    }

    private func synchronizeSnapshot() {
        let updated = appModel.browserSession.presentationSnapshot(
            for: conversationID
        )
        snapshot = updated
        guard !isAddressFieldFocused else { return }
        let displayedURL = updated.url == "about:blank" ? "" : updated.url
        if addressText != displayedURL {
            addressText = displayedURL
        }
    }

    private func navigateToAddress() {
        let target = addressText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !target.isEmpty else { return }
        isAddressFieldFocused = false
        perform { session in
            try await session.navigateFromPresentation(
                to: target,
                conversationID: conversationID
            )
        }
    }

    private func createTab() {
        perform { session in
            _ = try session.createTabFromPresentation(
                conversationID: conversationID
            )
        }
    }

    private func selectTab(_ tabID: Int) {
        perform { session in
            try session.selectTabFromPresentation(
                tabID,
                conversationID: conversationID
            )
        }
    }

    private func perform(
        _ operation: @escaping @MainActor (AppleBrowserSession) async throws -> Void
    ) {
        guard !isPerformingOperation else { return }
        isPerformingOperation = true
        let session = appModel.browserSession
        Task { @MainActor in
            defer {
                isPerformingOperation = false
                synchronizeSnapshot()
            }
            do {
                try await operation(session)
            } catch {
                present(error)
            }
        }
    }

    private func present(_ error: any Error) {
        presentedError = BrowserPresentationAlert(message: error.localizedDescription)
    }
}

private struct BrowserPresentationAlert: Identifiable {
    let id = UUID()
    let message: String
}
