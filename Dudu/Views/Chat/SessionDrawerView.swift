import SwiftUI

/// Phase C2 — session history drawer (presented as a sheet).
///
/// Real data from ChatStore.shared.listSessions(): tap switches the session
/// on the shared view model (sessionId swap + loadSession), swipe actions
/// pin/unpin and delete. "New chat" returns to a fresh draft — it does not
/// delete anything.
struct SessionDrawerView: View {
    @EnvironmentObject private var vm: AIChatViewModel
    @Environment(\.dismiss) private var dismiss

    /// Called by the new-chat button so the parent can reset consistently.
    var onNewChat: () -> Void = {}

    @State private var sessions: [ChatSession] = []
    @State private var loading = true

    private var pinned: [ChatSession] { sessions.filter { $0.pinnedAt != nil } }
    private var unpinned: [ChatSession] { sessions.filter { $0.pinnedAt == nil } }

    var body: some View {
        NavigationStack {
            Group {
                if loading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if sessions.isEmpty {
                    emptyState
                } else {
                    List {
                        if !pinned.isEmpty {
                            Section("已置顶") {
                                ForEach(pinned) { session in
                                    sessionRow(session)
                                }
                            }
                        }
                        Section("历史对话") {
                            ForEach(unpinned) { session in
                                sessionRow(session)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("历史对话")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭") { dismiss() }
                        .font(DuduTheme.bodyFont())
                        .foregroundStyle(DuduTheme.duduText)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        onNewChat()
                    } label: {
                        Image(systemName: "square.and.pencil")
                            .foregroundStyle(DuduTheme.duduText)
                    }
                    .accessibilityLabel("新的对话")
                }
            }
            .task { await reload() }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Rows

    private func sessionRow(_ session: ChatSession) -> some View {
        Button {
            switchToSession(session)
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(sessionTitle(for: session))
                        .font(DuduTheme.bodyFont(weight: .medium))
                        .foregroundStyle(DuduTheme.duduText)
                        .lineLimit(1)
                    if let preview = session.lastMessage, !preview.isEmpty {
                        Text(preview)
                            .font(DuduTheme.captionFont())
                            .foregroundStyle(DuduTheme.duduTextDim)
                            .lineLimit(1)
                    }
                }
                Spacer()
                if session.id == vm.sessionId {
                    Image(systemName: "checkmark")
                        .font(DuduTheme.captionFont(weight: .semibold))
                        .foregroundStyle(DuduTheme.pink)
                }
            }
            .padding(.vertical, 4)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                deleteSession(session)
            } label: {
                Label("删除", systemImage: "trash")
            }
            Button {
                togglePin(session)
            } label: {
                Label(
                    session.pinnedAt == nil ? "置顶" : "取消置顶",
                    systemImage: session.pinnedAt == nil ? "pin" : "pin.slash"
                )
            }
            .tint(DuduTheme.pink)
        }
    }

    private func sessionTitle(for session: ChatSession) -> String {
        if let t = session.title, !t.isEmpty { return t }
        return "新的对话"
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(DuduTheme.titleFont())
                .foregroundStyle(DuduTheme.duduTextDim)
            Text("还没有历史对话")
                .font(DuduTheme.bodyFont())
                .foregroundStyle(DuduTheme.duduTextDim)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Actions

    private func reload() async {
        loading = true
        sessions = await ChatStore.shared.listSessions()
        loading = false
    }

    /// Switch recipe for the shared view model: point it at the new session
    /// and reload from the database. clearChat() is NOT used here — it wipes
    /// the current session's rows, which is the opposite of switching.
    private func switchToSession(_ session: ChatSession) {
        guard session.id != vm.sessionId else {
            dismiss()
            return
        }
        vm.sessionId = session.id
        vm.messages.removeAll()
        vm.errorMessage = nil
        vm.inputText = ""
        vm.attachments.removeAll()
        dismiss()
        Task { await vm.loadSession() }
    }

    private func togglePin(_ session: ChatSession) {
        Task {
            await ChatStore.shared.setSessionPinnedAt(
                session.pinnedAt == nil ? Date() : nil,
                forSession: session.id
            )
            await reload()
        }
    }

    private func deleteSession(_ session: ChatSession) {
        Task {
            await ChatStore.shared.deleteSession(session.id)
            if session.id == vm.sessionId {
                onNewChat()
            } else {
                await reload()
            }
        }
    }
}
