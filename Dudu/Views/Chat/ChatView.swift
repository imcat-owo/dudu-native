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
    /// Phase D4 — confirm discarding the in-memory incognito transcript.
    @State private var showExitIncognitoConfirm = false

    /// Empty only when there is genuinely nothing to render — never hide
    /// the list mid-stream.
    private var isEmpty: Bool {
        vm.messages.isEmpty && !vm.isProcessing && !vm.isLoadingSession
    }

    private var navTitle: String {
        // Phase D4 — 隐身模式下标题固定为"隐身模式"，不显示任何会话标题。
        if vm.isIncognito { return "隐身模式" }
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
            }
            // Wave 2 Item 5 — floating glass capsule input (html-2 定稿).
            // The capsule rides in the bottom safe-area inset, above the
            // floating tab bar's 69pt inset (59pt bar + 10pt margin) with an
            // 8pt gap = 77pt clearance, and the keyboard pushes it up
            // automatically (the keyboard region is part of the safe area).
            .safeAreaInset(edge: .bottom) {
                ChatInputBar()
                    // Peeking easter egg: the cat peeks over the capsule's
                    // top edge every 8-14s while the chat tab is active and
                    // no bubble cat is showing (PeekCatHost owns the timer).
                    .overlay(alignment: .topLeading) {
                        PeekCatHost(isChatActive: selection == .chat)
                            .offset(x: 14, y: -46)
                    }
                    .padding(.bottom, 8)
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
                    if vm.isIncognito {
                        // Phase D4 — 隐身指示器：图标 + "隐身模式"。
                        HStack(spacing: 4) {
                            Image(systemName: "eye.slash.fill")
                                .font(DuduTheme.captionFont())
                            Text("隐身模式")
                                .font(DuduTheme.titleFont())
                        }
                        .foregroundStyle(DuduTheme.duduText)
                        .accessibilityLabel("隐身模式：聊天记录不会被保存")
                    } else {
                        Button {
                            showDrawer = true
                        } label: {
                            Text(navTitle)
                                .font(DuduTheme.titleFont())
                                .foregroundStyle(DuduTheme.duduText)
                                .lineLimit(1)
                        }
                    }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    // Phase D4 — 隐身聊天开关。
                    Button {
                        toggleIncognito()
                    } label: {
                        Image(systemName: vm.isIncognito ? "eye.slash.fill" : "eye.slash")
                            .foregroundStyle(vm.isIncognito ? DuduTheme.pink : DuduTheme.duduText)
                    }
                    .accessibilityLabel(vm.isIncognito ? "退出隐身聊天" : "隐身聊天")
                    // [D21] Voice call: full-duplex call with barge-in.
                    Button {
                        Task { @MainActor in
                            await CallProposalCenter.shared.startOutgoingCall(
                                personaName: PersonaStore.shared.current.name,
                                entry: vm.resolveCurrentEntry(),
                                chatSessionId: vm.sessionId)
                        }
                    } label: {
                        Image(systemName: "phone")
                            .foregroundStyle(DuduTheme.duduText)
                    }
                    .accessibilityLabel("语音通话")
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
            .alert("退出隐身聊天？", isPresented: $showExitIncognitoConfirm) {
                Button("取消", role: .cancel) {}
                Button("退出并清空", role: .destructive) {
                    vm.exitIncognito(confirmed: true)
                }
            } message: {
                Text("隐身聊天的消息不会被保存，退出后将清空当前对话。")
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
    /// Phase D4: in incognito, "new chat" resets the in-memory draft and
    /// stays in incognito mode.
    private func startNewChat() {
        vm.resetViewState()
        sessionTitle = nil
        showDrawer = false
    }

    /// Phase D4 — 隐身聊天开关。进入直接切；退出时若有消息，先弹窗确认
    /// （退出即清空内存中的聊天记录）。
    private func toggleIncognito() {
        if vm.isIncognito {
            if vm.messages.isEmpty {
                vm.exitIncognito()
            } else {
                showExitIncognitoConfirm = true
            }
        } else {
            vm.enterIncognito()
            sessionTitle = nil
            showDrawer = false
        }
    }
}
