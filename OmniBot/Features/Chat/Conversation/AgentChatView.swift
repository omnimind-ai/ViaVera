import SwiftUI
import QuickLook
import UniformTypeIdentifiers
#if os(iOS)
import PhotosUI
#endif

struct AgentChatView: View {
    @Environment(AppModel.self) private var appModel

    let conversationID: UUID
    let onOpenMainWindow: (() -> Void)?
    let onTogglePin: (() -> Void)?
    let isPinned: Bool

    @State private var composerDraft: ChatComposerDraft
    @State private var composerFocusRequestID = 0
    @State private var turnExpansion = AgentTurnExpansionState()
    @State private var isToolActivityExpanded = false
    @State private var isCommandToolbarPresented = false
    @State private var autoScrollSuppressedUntil: Date?
    /// Whether the transcript should follow the latest output. Driven by
    /// `onScrollGeometry`/`onScrollPhaseChange`: while the user is manually
    /// scrolled away from the bottom this is `false` and token-driven
    /// `scrollTo` calls are skipped, so reading earlier output during
    /// streaming stays put. Re-pinned to `true` when the user scrolls back to
    /// the bottom, submits a new message, retries, or switches conversation.
    @State private var isPinnedToBottom = true
    /// Most recent scroll phase. Used to distinguish user-driven drags from
    /// the programmatic `.animating` phase our own `scrollTo` produces.
    @State private var scrollPhase: ScrollPhase = .idle
    @State private var isUserMessageContextMenuLayoutLocked = false
    @State private var userMessageContextMenuUnlockGeneration = 0
#if os(macOS)
    @State private var isPresentingTerminal = false
#endif
    @State private var isPresentingBrowser = false
#if !os(macOS)
    @State private var settingsSheetPresentation: SettingsSheetPresentation?
#endif
    @State private var previewedResourceURL: URL?
    @State private var resourcePreviewRequestID: UUID?
    @State private var isImportingAttachments = false
#if os(iOS)
    @State private var isPresentingPhotoPicker = false
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var composerAutoFocusTask: Task<Void, Never>?
    @State private var composerAutoFocusGeneration = 0
#endif
#if os(macOS)
    @State private var isComposerFocused = false
#else
    @FocusState private var isComposerFocused: Bool
#endif
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    init(
        conversationID: UUID,
        onOpenMainWindow: (() -> Void)? = nil,
        onTogglePin: (() -> Void)? = nil,
        isPinned: Bool = false,
        composerDraft: ChatComposerDraft? = nil
    ) {
        self.conversationID = conversationID
        self.onOpenMainWindow = onOpenMainWindow
        self.onTogglePin = onTogglePin
        self.isPinned = isPinned
        _composerDraft = State(initialValue: composerDraft ?? ChatComposerDraft())
    }

    private var draft: String {
        get { composerDraft.text }
        nonmutating set { composerDraft.text = newValue }
    }

    private var editingUserMessageID: UUID? {
        get { composerDraft.editingUserMessageID }
        nonmutating set { composerDraft.editingUserMessageID = newValue }
    }

    var body: some View {
        if let conversation = appModel.conversations.conversation(id: conversationID) {
            let messages = conversation.orderedMessages
            let isRunning = appModel.chatCoordinator.isRunning(conversation)
            let isPreparingResend =
                appModel.chatCoordinator.pendingResendConversationID == conversation.id
            let isBusy = appModel.chatCoordinator.busyConversationID != nil
            let transcript = ChatTranscriptPresentation(
                messages: messages,
                runIsActive: isRunning,
                liveToolActivity: appModel.toolActivity.snapshot(for: conversation.id)
            )
            let preferredCompletedTurnID = turnExpansion.preferredCompletedTurnID(
                in: transcript.agentTurns
            )
            let toolActivityTurn = transcript.toolActivityTurn(
                preferredCompletedTurnID: preferredCompletedTurnID
            )

            VStack(spacing: 0) {
#if os(macOS)
                if let onOpenMainWindow, let onTogglePin {
                    MenuBarChatHeader(
                        title: conversation.title,
                        onNewConversation: newMenuBarConversation,
                        onOpenMainWindow: onOpenMainWindow,
                        isPinned: isPinned,
                        onTogglePin: onTogglePin
                    ) {
                        MacChatMoreMenu(
                            conversationID: conversation.id,
                            isPresentingBrowser: $isPresentingBrowser,
                            openBrowser: openBrowser,
                            openWorkspace: openWorkspace,
                            openSettings: openSettings,
                            dismissComposerFocus: dismissComposerFocus
                        )
                    }
                }
#endif
                Group {
                    if transcript.messages.isEmpty {
                        ChatEmptyStateView { prompt in
                            draft = prompt
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        // Keep programmatic scrolling one-shot. A bound ScrollPosition
                        // retains a row identity after a user gesture and reanchors the
                        // whole Agent turn when its reveal height changes.
                        ScrollViewReader { scrollProxy in
                            ScrollView(.vertical) {
                                LazyVStack(spacing: AppDesign.sectionSpacing) {
                                    ForEach(transcript.timelineEntries) { entry in
                                        ChatTimelineRow(
                                            entry: entry,
                                            latestUserMessageID: transcript.latestUserMessageID,
                                            isBusy: isBusy,
                                            isRunning: isRunning,
                                            isAgentTurnManuallyExpanded:
                                                isAgentTurnManuallyExpanded(entry),
                                            onEditUserMessage: { message in
                                                beginEditing(message)
                                            },
                                            onRetryUserMessage: { message in
                                                retryUserMessage(
                                                    message,
                                                    replacementText: nil,
                                                    conversation: conversation
                                                )
                                            },
                                            onUserMessageContextMenuInteractionChanged:
                                                updateUserMessageContextMenuInteraction,
                                            onToggleAgentTurn: { turnID in
                                                toggleAgentTurn(turnID)
                                            }
                                        )
                                    }

                                    Color.clear
                                        .frame(height: 1)
                                        .id(Self.transcriptBottomAnchor)
                                }
                                .padding(.top, AppDesign.contentPadding)
                                .padding(.bottom, AppDesign.compactSpacing)
                                .frame(maxWidth: AppDesign.chatContentMaximumWidth)
                                .frame(maxWidth: .infinity)
                            }
                            .contentMargins(
                                .horizontal,
                                AppDesign.contentPadding,
                                for: .scrollContent
                            )
#if os(macOS)
                            .scrollEdgeEffectHidden(true, for: .top)
                            .mask(alignment: .top) {
                                MacChatScrollTopFadeMask()
                            }
#endif
                            .defaultScrollAnchor(.bottom, for: .initialOffset)
#if os(iOS)
                            // The system can temporarily hide the keyboard without
                            // clearing the text field's focus while presenting a context
                            // menu. Keep the visible transcript fixed through that
                            // viewport change so it stays aligned with the menu preview.
                            .defaultScrollAnchor(
                                isUserMessageContextMenuLayoutLocked ? .top : nil,
                                for: .sizeChanges
                            )
#endif
                            .scrollDismissesKeyboard(.interactively)
                            .onScrollPhaseChange { _, phase in
                                scrollPhase = phase
                            }
                            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                                // Distance from the bottom edge of the content
                                // to the bottom edge of the viewport.
                                geometry.contentSize.height
                                    - geometry.contentOffset.y
                                    - geometry.containerSize.height
                            } action: { _, distanceToBottom in
                                // Skip the programmatic, animated scroll our own
                                // follow-the-latest logic issues; otherwise its
                                // offset changes would never un-pin the view.
                                guard scrollPhase != .animating else { return }
                                isPinnedToBottom =
                                    distanceToBottom
                                    <= Self.bottomPinTolerance
                            }
                            .onChange(
                                of: transcript.timelineEntries.map(\.id)
                            ) { _, identifiers in
                                guard !identifiers.isEmpty else { return }
                                guard isPinnedToBottom,
                                    !isAutoScrollSuppressed
                                else { return }
                                scrollToLatest(using: scrollProxy)
                            }
                            .onChange(of: messages.last?.updatedAt) { _, _ in
                                guard isPinnedToBottom,
                                    !isAutoScrollSuppressed
                                else { return }
                                if reduceMotion {
                                    scrollToLatest(using: scrollProxy)
                                } else {
                                    withAnimation(.easeOut(duration: 0.18)) {
                                        scrollToLatest(using: scrollProxy)
                                    }
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(.rect)
                .simultaneousGesture(
                    TapGesture().onEnded(dismissChatInterface)
                )
#if os(iOS)
                .simultaneousGesture(
                    DragGesture(minimumDistance: 2).onChanged { _ in
                        cancelPendingComposerAutoFocus()
                    }
                )
#endif

                VStack(spacing: 0) {
                    if !isCommandToolbarPresented,
                       let toolActivityTurn,
                       !toolActivityTurn.activityTools.isEmpty {
                        ChatToolActivityStrip(
                            conversationID: conversation.id,
                            tools: toolActivityTurn.activityTools,
                            isRunning: toolActivityTurn.isActive,
                            isExpanded: $isToolActivityExpanded,
                            onCancel: cancelCurrentTool,
                            onOpenBrowser: openBrowser
                        )
                        .simultaneousGesture(
                            TapGesture().onEnded(dismissComposerFocus)
                        )
                    }

                    if conversation.status == .failed {
                        ChatErrorBanner(
                            message: conversation.lastErrorMessage ?? "Agent 未能完成本次任务。",
                            onRetry: { appModel.chatCoordinator.retry(conversation) }
                        )
                        .padding(.vertical, AppDesign.compactSpacing)
                        .simultaneousGesture(
                            TapGesture().onEnded(dismissComposerFocus)
                        )
                    }

                    if isCommandToolbarPresented {
                        ChatCommandToolbar(
                            selectedEffort: conversation.reasoningEffort,
                            isBusy: isBusy,
                            isCompacting: appModel.chatCoordinator.isCompacting(conversation),
                            compactionMessage: compactionMessage(for: conversation),
                            compactionFailed: appModel.chatCoordinator.lastCompactionFailed,
                            onCompact: {
                                compactContext(in: conversation)
                            },
                            onSelectEffort: { effort in
                                appModel.selectReasoningEffort(effort, for: conversation)
                            }
                        )
                        .simultaneousGesture(
                            TapGesture().onEnded(dismissComposerFocus)
                        )
                        .transition(
                            reduceMotion
                                ? .opacity
                                : .move(edge: .bottom).combined(with: .opacity)
                        )
                    }

                    ChatComposerView(
                        text: $composerDraft.text,
                        conversation: conversation,
                        isBusy: isBusy,
                        isRunning: isRunning,
                        isPreparingResend: isPreparingResend,
                        isEditingUserMessage: editingUserMessageID != nil,
                        isCommandToolbarPresented: isCommandToolbarPresented,
                        isFocused: $isComposerFocused,
                        focusRequestID: composerFocusRequestID,
                        busyStatusMessage: appModel.chatCoordinator.busyConversationID
                            == conversation.id
                            ? appModel.chatCoordinator.statusMessage
                            : nil,
                        onInteraction: handleComposerInteraction,
                        onToggleCommandToolbar: toggleCommandToolbar,
                        onSend: {
                            submitDraft(in: conversation)
                        },
                        onCancel: {
                            Task {
                                await appModel.chatCoordinator.cancel()
                            }
                        },
                        onOpenTerminal: openTerminal,
                        onImportAttachments: {
                            isImportingAttachments = true
                        },
                        onAddPhotos: presentPhotoPicker
                    )

#if os(macOS)
                    if isPresentingTerminal {
                        MacInlineTerminalView(onDismiss: closeTerminal)
                            .transition(
                                reduceMotion
                                    ? .opacity
                                    : .move(edge: .bottom).combined(with: .opacity)
                            )
                    }
#endif
                }
                .padding(.top, AppDesign.compactSpacing)
            }
#if os(iOS)
            .background {
                ChatBackgroundView(settings: appModel.appearanceSettings)
                    .ignoresSafeArea()
            }
#endif
            .onChange(of: transcript.activeAgentTurn?.id) { oldTurnID, newTurnID in
                if let oldTurnID {
                    turnExpansion.collapse(oldTurnID)
                }
                if let newTurnID {
                    turnExpansion.collapse(newTurnID)
                }
            }
#if os(iOS)
            .onChange(of: isRunning) { wasRunning, isRunning in
                if isRunning {
                    cancelPendingComposerAutoFocus()
                } else if wasRunning {
                    scheduleComposerAutoFocusAfterResponse()
                }
            }
            .onChange(of: draft) { _, _ in
                cancelPendingComposerAutoFocus()
            }
            .onChange(of: isComposerFocused) { _, isFocused in
                guard isFocused else { return }
                cancelPendingComposerAutoFocus()
            }
            .onChange(of: scenePhase) { _, scenePhase in
                guard scenePhase != .active else { return }
                cancelPendingComposerAutoFocus()
            }
#endif
            .onChange(of: toolActivityTurn?.id) { _, _ in
                isToolActivityExpanded = false
            }
            .onChange(of: transcript.latestUserMessageID) { oldMessageID, newMessageID in
                guard oldMessageID != newMessageID else { return }
                turnExpansion.reset()
                isToolActivityExpanded = false
                if let editingUserMessageID, editingUserMessageID != newMessageID {
                    self.editingUserMessageID = nil
                    draft = ""
                }
            }
            .onChange(of: conversationID) { _, _ in
#if os(iOS)
                cancelPendingComposerAutoFocus()
#endif
                turnExpansion.reset()
                isToolActivityExpanded = false
                isCommandToolbarPresented = false
                autoScrollSuppressedUntil = nil
                isPinnedToBottom = true
                scrollPhase = .idle
                resetUserMessageContextMenuLayoutLock()
                editingUserMessageID = nil
                draft = ""
                cancelResourcePreview()
                isPresentingBrowser = false
#if os(macOS)
                isPresentingTerminal = false
#endif
#if !os(macOS)
                settingsSheetPresentation = nil
#endif
            }
            .environment(\.openURL, OpenURLAction { url in
                guard url.scheme?.lowercased() == AgentResourceProtocol.scheme else {
                    return .systemAction(url)
                }
                beginResourcePreview(for: url)
                return .handled
            })
            .quickLookPreview($previewedResourceURL)
            .onChange(of: previewedResourceURL) { oldValue, newValue in
                guard oldValue != newValue, let oldValue else { return }
                let resourceProtocol = appModel.resourceProtocol
                Task.detached(priority: .utility) {
                    resourceProtocol.removeQuickLookSnapshot(oldValue)
                }
            }
            .onDisappear {
#if os(iOS)
                cancelPendingComposerAutoFocus()
#endif
                cancelResourcePreview()
            }
            .fileImporter(
                isPresented: $isImportingAttachments,
                allowedContentTypes: [.item],
                allowsMultipleSelection: true
            ) { result in
                importAttachments(result)
            }
#if os(iOS)
            .photosPicker(
                isPresented: $isPresentingPhotoPicker,
                selection: $selectedPhotoItems,
                maxSelectionCount: 16,
                matching: .images,
                preferredItemEncoding: .current
            )
            .onChange(of: selectedPhotoItems) { _, items in
                guard !items.isEmpty else { return }
                selectedPhotoItems = []
                importPhotos(items)
            }
#endif
#if !os(macOS)
            .sheet(isPresented: $isPresentingBrowser) {
                BrowserCardView(conversationID: conversation.id)
            }
            .sheet(item: $settingsSheetPresentation) { presentation in
                SettingsCardView(initialDestination: presentation.initialDestination)
            }
#endif
#if os(macOS)
            .navigationTitle(conversation.title)
            .toolbar {
                if onOpenMainWindow == nil {
                    ToolbarItem(placement: .primaryAction) {
                        MacChatMoreMenu(
                            conversationID: conversation.id,
                            isPresentingBrowser: $isPresentingBrowser,
                            openBrowser: openBrowser,
                            openWorkspace: openWorkspace,
                            openSettings: openSettings,
                            dismissComposerFocus: dismissComposerFocus
                        )
                        .disabled(isSettingsPresented)
                    }
                    .sharedBackgroundVisibility(.hidden)
                }
            }
            .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
#else
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    ChatHeaderTitle(title: conversation.title)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    ChatMoreMenu(
                        openBrowser: openBrowser,
                        openWorkspace: openWorkspace,
                        openSettings: openSettings
                    )
                    .simultaneousGesture(
                        TapGesture().onEnded(dismissComposerFocus)
                    )
                }
            }
            .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
#endif
        } else {
            ContentUnavailableView {
                Label("找不到会话", systemImage: "bubble.left.and.exclamationmark.bubble.right")
            } description: {
                Text("该会话可能已被删除，请从侧边栏选择其他会话。")
            }
            .navigationTitle("会话")
        }
    }

#if os(macOS)
    private var isSettingsPresented: Bool {
        appModel.presentedSettingsDestination != nil
    }
#endif

    private func resend(
        _ message: MessageRecord,
        replacementText: String?,
        conversation: ConversationRecord
    ) async throws {
        do {
            try await appModel.chatCoordinator.resendLatestUserMessage(
                message,
                replacingWith: replacementText,
                in: conversation
            )
        } catch {
            appModel.globalErrorMessage = error.localizedDescription
            throw error
        }
    }

    private func beginEditing(_ message: MessageRecord) {
        guard let content = message.content,
              !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        draft = content
        editingUserMessageID = message.id
        composerFocusRequestID &+= 1
        collapseChatPanels()
    }

    private func submitDraft(in conversation: ConversationRecord) {
        let replacement = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !replacement.isEmpty else { return }

        guard let editingUserMessageID else {
            if let command = ChatComposerCommand.parse(replacement) {
                execute(command, in: conversation)
                return
            }
            let message = draft
            draft = ""
            isCommandToolbarPresented = false
            // The user just submitted; follow the new turn as it streams in
            // even if they had been scrolled up reading earlier output.
            isPinnedToBottom = true
            appModel.chatCoordinator.send(message, in: conversation)
            return
        }

        guard let message = conversation.orderedMessages.first(where: {
            $0.id == editingUserMessageID
        }) else {
            self.editingUserMessageID = nil
            appModel.globalErrorMessage = "无法找到要编辑的消息，请重试。"
            return
        }

        Task {
            do {
                try await resend(
                    message,
                    replacementText: replacement,
                    conversation: conversation
                )
                guard self.editingUserMessageID == editingUserMessageID else { return }
                draft = ""
                self.editingUserMessageID = nil
            } catch {
                // Keep the replacement in the composer so it can be adjusted and retried.
            }
        }
    }

    private func importAttachments(_ result: Result<[URL], any Error>) {
        Task {
            do {
                let sourceURLs = try result.get()
                let artifacts = try await appModel.attachmentImporter.importFiles(sourceURLs)
                appendAttachmentReferences(artifacts)
            } catch {
                appModel.globalErrorMessage = error.localizedDescription
            }
        }
    }

    private func appendAttachmentReferences(_ artifacts: [AgentArtifact]) {
        let references = artifacts.map { artifact in
            "附件：\(artifact.renderMarkdown)\n工作区路径：\(artifact.workspacePath)"
        }
        guard !references.isEmpty else { return }
        let block = references.joined(separator: "\n")
        draft = draft.isEmpty ? block : "\(draft)\n\(block)"
    }

    private func presentPhotoPicker() {
#if os(iOS)
        isPresentingPhotoPicker = true
#endif
    }

#if os(iOS)
    private func importPhotos(_ items: [PhotosPickerItem]) {
        Task {
            do {
                var payloads: [WorkspaceAttachmentPayload] = []
                payloads.reserveCapacity(items.count)

                for (index, item) in items.enumerated() {
                    guard let data = try await item.loadTransferable(type: Data.self) else {
                        throw ChatPhotoImportError.unavailable(index + 1)
                    }
                    let contentType = item.supportedContentTypes.first { contentType in
                        contentType.conforms(to: .image)
                    }
                    let fileExtension = contentType?.preferredFilenameExtension ?? "jpg"
                    payloads.append(
                        WorkspaceAttachmentPayload(
                            data: data,
                            preferredName: "照片-\(index + 1).\(fileExtension)"
                        )
                    )
                }

                let artifacts = try await appModel.attachmentImporter.importPayloads(payloads)
                appendAttachmentReferences(artifacts)
            } catch {
                appModel.globalErrorMessage = error.localizedDescription
            }
        }
    }
#endif

    private func beginResourcePreview(for resourceURL: URL) {
        let requestID = UUID()
        resourcePreviewRequestID = requestID
        previewedResourceURL = nil
        let resourceProtocol = appModel.resourceProtocol

        Task { @MainActor in
            do {
                let snapshotURL = try await Task.detached(priority: .userInitiated) {
                    try resourceProtocol.makeQuickLookSnapshot(for: resourceURL)
                }.value
                guard resourcePreviewRequestID == requestID else {
                    Task.detached(priority: .utility) {
                        resourceProtocol.removeQuickLookSnapshot(snapshotURL)
                    }
                    return
                }
                previewedResourceURL = snapshotURL
            } catch {
                guard resourcePreviewRequestID == requestID else { return }
                appModel.globalErrorMessage = error.localizedDescription
            }
        }
    }

    private func cancelResourcePreview() {
        resourcePreviewRequestID = nil
        previewedResourceURL = nil
    }

    private func retryUserMessage(
        _ message: MessageRecord,
        replacementText: String?,
        conversation: ConversationRecord
    ) {
        Task {
            // A retry starts a fresh streaming turn; resume auto-follow so the
            // regenerated output is visible without manual scrolling back down.
            isPinnedToBottom = true
            try? await resend(
                message,
                replacementText: replacementText,
                conversation: conversation
            )
        }
    }

    private func cancelCurrentTool(callID: String) async -> Bool {
        let didRequestStop = await appModel.chatCoordinator.cancelCurrentTool(callID: callID)
        if !didRequestStop {
            appModel.globalErrorMessage = "停止工具调用失败，请稍后重试。"
        }
        return didRequestStop
    }

    private func toggleAgentTurn(_ turnID: UUID) {
        autoScrollSuppressedUntil = Date.now.addingTimeInterval(0.42)
        // Lazy stacks normally compensate their content offset when a row or
        // the bottom safe-area inset changes size. That fights this reveal
        // animation, so keep the absolute offset for this state transaction.
        withTransaction(\.scrollContentOffsetAdjustmentBehavior, .disabled) {
            turnExpansion.toggle(turnID)
        }
    }

    private func updateUserMessageContextMenuInteraction(_ isActive: Bool) {
#if os(iOS)
        cancelPendingComposerAutoFocus()
        userMessageContextMenuUnlockGeneration &+= 1
        let generation = userMessageContextMenuUnlockGeneration

        guard !isActive else {
            isUserMessageContextMenuLayoutLocked = true
            return
        }

        // Keep the anchor until the system has finished dismissing the menu
        // and restoring any temporarily hidden keyboard.
        Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard generation == userMessageContextMenuUnlockGeneration else { return }
            isUserMessageContextMenuLayoutLocked = false
        }
#endif
    }

    private func resetUserMessageContextMenuLayoutLock() {
#if os(iOS)
        userMessageContextMenuUnlockGeneration &+= 1
        isUserMessageContextMenuLayoutLocked = false
#endif
    }

    private func scrollToLatest(using scrollProxy: ScrollViewProxy) {
        scrollProxy.scrollTo(Self.transcriptBottomAnchor, anchor: .bottom)
    }

    private func isAgentTurnManuallyExpanded(_ entry: ChatTimelineEntry) -> Bool {
        guard let turn = entry.agentTurn else { return false }
        return turnExpansion.isManuallyExpanded(turn.id)
    }

    private func collapseToolActivity() {
        isToolActivityExpanded = false
    }

    private func handleComposerInteraction() {
#if os(iOS)
        cancelPendingComposerAutoFocus()
#endif
        collapseToolActivity()
    }

    private func collapseChatPanels() {
        isToolActivityExpanded = false
        isCommandToolbarPresented = false
    }

    private func dismissChatInterface() {
        dismissComposerFocus()
        collapseChatPanels()
    }

    private func dismissComposerFocus() {
#if os(iOS)
        cancelPendingComposerAutoFocus()
#endif
        isComposerFocused = false
    }

#if os(iOS)
    private func scheduleComposerAutoFocusAfterResponse() {
        cancelPendingComposerAutoFocus()
        guard !isComposerFocused else { return }

        composerAutoFocusGeneration &+= 1
        let generation = composerAutoFocusGeneration
        composerAutoFocusTask = Task { @MainActor in
            do {
                try await Task.sleep(for: Self.responseCompletionAutoFocusDelay)
            } catch {
                return
            }

            guard generation == composerAutoFocusGeneration else { return }
            defer { composerAutoFocusTask = nil }
            guard canAutoFocusComposer else { return }
            composerFocusRequestID &+= 1
        }
    }

    private func cancelPendingComposerAutoFocus() {
        guard let composerAutoFocusTask else { return }
        composerAutoFocusGeneration &+= 1
        composerAutoFocusTask.cancel()
        self.composerAutoFocusTask = nil
    }

    private var canAutoFocusComposer: Bool {
        appModel.chatCoordinator.busyConversationID == nil
            && scenePhase == .active
            && !isComposerFocused
            && !isPresentingBrowser
            && settingsSheetPresentation == nil
            && previewedResourceURL == nil
            && !isImportingAttachments
            && !isPresentingPhotoPicker
            && !isUserMessageContextMenuLayoutLocked
    }
#endif

    private func toggleCommandToolbar() {
        collapseToolActivity()
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) {
            isCommandToolbarPresented.toggle()
        }
    }

    private func compactContext(in conversation: ConversationRecord) {
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) {
            isCommandToolbarPresented = false
        }
        Task {
            await appModel.chatCoordinator.compactContext(in: conversation)
        }
    }

    private func compactionMessage(for conversation: ConversationRecord) -> String? {
        guard appModel.chatCoordinator.lastCompactionConversationID == conversation.id else {
            return nil
        }
        return appModel.chatCoordinator.lastCompactionMessage
    }

    private func execute(
        _ command: ChatComposerCommand,
        in conversation: ConversationRecord
    ) {
        draft = ""
        switch command {
        case .compact:
            compactContext(in: conversation)
        case .showEffort:
            isCommandToolbarPresented = true
            composerFocusRequestID &+= 1
        case let .setEffort(effort):
            isCommandToolbarPresented = false
            appModel.selectReasoningEffort(effort, for: conversation)
        case .invalidEffort:
            isCommandToolbarPresented = true
            appModel.globalErrorMessage = "可用思考强度：no、low、high、xhigh、max"
        }
    }

    private func openTerminal() {
#if os(iOS)
        appModel.presentTerminal()
#else
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) {
            isPresentingTerminal.toggle()
        }
#endif
    }

    private func openBrowser() {
        collapseChatPanels()
        isPresentingBrowser = true
    }

    private func openWorkspace() {
        collapseChatPanels()
#if os(macOS)
        appModel.presentSettings(.workspace)
        onOpenMainWindow?()
#else
        settingsSheetPresentation = SettingsSheetPresentation(
            initialDestination: .workspace
        )
#endif
    }

    private func openSettings() {
        collapseChatPanels()
#if os(macOS)
        appModel.presentSettings()
        onOpenMainWindow?()
#else
        settingsSheetPresentation = SettingsSheetPresentation()
#endif
    }

#if os(macOS)
    private func newMenuBarConversation() {
        appModel.newConversation()
        isComposerFocused = true
        composerFocusRequestID &+= 1
    }

    private func closeTerminal() {
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) {
            isPresentingTerminal = false
        }
    }
#endif

    private var isAutoScrollSuppressed: Bool {
        guard let autoScrollSuppressedUntil else { return false }
        return Date.now < autoScrollSuppressedUntil
    }

    private static let transcriptBottomAnchor = "chat-transcript-bottom"
    /// Distance from the bottom edge (in points) within which the transcript
    /// is still considered "pinned to bottom" and may auto-follow streaming
    /// output. Larger than zero so a fractional drag or inset rounding does
    /// not immediately unpin.
    private static let bottomPinTolerance: CGFloat = 40
#if os(iOS)
    private static let responseCompletionAutoFocusDelay: Duration = .milliseconds(700)
#endif

}
