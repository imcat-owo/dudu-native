import SwiftUI

/// Phase C2 — the chat screen. Binds to the shared AIChatViewModel
/// (@EnvironmentObject, injected by DuduTabView).
///
/// Layout: nav bar (drawer button, session title, model picker, new chat) +
/// message list (or ChatEmptyStateView when there is nothing to show) +
/// ChatInputBar. The input is NEVER locked while the AI is busy — she can
/// send follow-ups at any time; they queue on the engine side (post-turn
/// drain auto-sends them), with a queued-count badge in the input bar and a
/// "排队中" tag on each queued bubble.
struct ChatView: View {
    @EnvironmentObject private var vm: AIChatViewModel
    @EnvironmentObject private var providers: ProviderConfigStore

    @Binding var selection: DuduTab

    @State private var showDrawer = false
    @State private var showModelPicker = false
    @State private var sessionTitle: String?

    /// Empty only when there is genuinely nothing to render — never hide
    /// the list mid-stream.
    private var isEmpty: Bool {
        vm.messages.isEmpty && !vm.isProcessing && !vm.isLoadingSession
    }

    private var navTitle: String {
        if let t = sessionTitle, !t.isEmpty { return t }
        return "新的对话"
    }

    /// The model the current turn will actually use, for the nav-bar label.
    /// Reads through the injected store so the label re-renders when the
    /// provider config changes.
    private var currentModelName: String {
        if let sid = vm.sessionId,
           let binding = providers.binding(for: sid),
           case .directEntry(let entryId, _) = binding.primarySource,
           let entry = providers.entry(for: entryId) {
            return entry.model.displayName
        }
        if !vm.cachedSessionModelId.isEmpty,
           let entry = providers.config.modelEntries.first(where: { $0.model.id == vm.cachedSessionModelId }) {
            return entry.model.displayName
        }
        return vm.selectedModel.displayName
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let error = vm.errorMessage, !error.isEmpty {
                    errorBanner(error)
                }

                if isEmpty {
                    ChatEmptyStateView(selection: $selection)
                } else {
                    MessageListView()
                }

                ChatInputBar()
            }
            .background(DuduTheme.duduBackground)
            .navigationTitle(navTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showDrawer = true
                    } label: {
                        Image(systemName: "line.3.horizontal")
                            .foregroundStyle(DuduTheme.duduText)
                    }
                    .accessibilityLabel("历史对话")
                }
                ToolbarItem(placement: .principal) {
                    Button {
                        showDrawer = true
                    } label: {
                        Text(navTitle)
                            .font(DuduTheme.titleFont())
                            .foregroundStyle(DuduTheme.duduText)
                            .lineLimit(1)
                    }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        showModelPicker = true
                    } label: {
                        HStack(spacing: 3) {
                            Text(currentModelName)
                                .font(DuduTheme.captionFont())
                                .foregroundStyle(DuduTheme.duduTextDim)
                                .lineLimit(1)
                            Image(systemName: "chevron.down")
                                .font(DuduTheme.captionFont())
                                .foregroundStyle(DuduTheme.duduTextDim)
                        }
                    }
                    .accessibilityLabel("选择模型")

                    Button {
                        startNewChat()
                    } label: {
                        Image(systemName: "square.and.pencil")
                            .foregroundStyle(DuduTheme.duduText)
                    }
                    .accessibilityLabel("新的对话")
                }
            }
            .sheet(isPresented: $showDrawer) {
                SessionDrawerView(onNewChat: startNewChat)
            }
            .sheet(isPresented: $showModelPicker) {
                ModelPickerView()
            }
            .task(id: vm.sessionId) {
                await refreshSessionTitle()
            }
        }
    }

    // MARK: - Error banner

    private func errorBanner(_ error: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(DuduTheme.captionFont())
                .foregroundStyle(DuduTheme.duduTextDim)
            Text(error)
                .font(DuduTheme.captionFont())
                .foregroundStyle(DuduTheme.duduText)
                .lineLimit(2)
            Spacer()
            Button {
                vm.errorMessage = nil
            } label: {
                Image(systemName: "xmark")
                    .font(DuduTheme.captionFont())
                    .foregroundStyle(DuduTheme.duduTextDim)
            }
            .accessibilityLabel("关闭错误提示")
        }
        .padding(.horizontal, DuduTheme.pagePadding)
        .padding(.vertical, 8)
        .background(DuduTheme.pinkSoft)
    }

    // MARK: - Session helpers

    private func refreshSessionTitle() async {
        guard let sid = vm.sessionId else {
            sessionTitle = nil
            return
        }
        sessionTitle = await ChatStore.shared.getSession(sid)?.title
    }

    /// Back to a fresh draft. Does NOT touch the database: the previous
    /// session's rows stay intact (unlike vm.clearChat(), which wipes the
    /// current session's messages — that is for explicit deletion flows).
    private func startNewChat() {
        vm.sessionId = nil
        vm.messages.removeAll()
        vm.errorMessage = nil
        vm.transientNotice = nil
        vm.inputText = ""
        vm.attachments.removeAll()
        sessionTitle = nil
        showDrawer = false
    }
}
