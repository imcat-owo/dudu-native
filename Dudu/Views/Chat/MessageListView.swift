import SwiftUI

/// Phase C2 — the scrolling message list. Each row owns its ChatMessage as
/// @ObservedObject (ChatMessage is a class), so token streaming re-renders
/// only the active row.
///
/// - Internal bridge messages (role-alternation scaffolding) never render.
/// - Auto-scrolls to the bottom on new content, but only while the user is
///   already near the bottom — reading history never gets yanked.
/// - A "jump to latest" pill appears when scrolled up.
struct MessageListView: View {
    @EnvironmentObject private var vm: AIChatViewModel

    @State private var isNearBottom = true

    private let bottomAnchorID = "message-list-bottom"

    private var rendered: [ChatMessage] {
        vm.messages.filter { !$0.isInternalBridge }
    }

    /// Changes whenever new content lands: new message, new block, or
    /// streamed text growth on the last message.
    private var scrollSignature: String {
        guard let last = rendered.last else { return "empty" }
        let tailContent = last.blocks.last?.content.count ?? last.content.count
        return "\(last.id.uuidString)-\(rendered.count)-\(last.blocks.count)-\(tailContent)"
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(rendered) { message in
                        MessageRowView(message: message)
                            .id(message.id)
                    }
                    // Bottom anchor: appear = near bottom, disappear = scrolled up.
                    // (iOS 17-safe; onScrollGeometryChange needs iOS 18.)
                    Color.clear
                        .frame(height: 1)
                        .id(bottomAnchorID)
                        .onAppear { isNearBottom = true }
                        .onDisappear { isNearBottom = false }
                }
                .padding(.horizontal, DuduTheme.pagePadding)
                .padding(.vertical, 12)
            }
            .defaultScrollAnchor(.bottom)
            .onChange(of: scrollSignature) { _, _ in
                guard isNearBottom, let last = rendered.last else { return }
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
            .overlay(alignment: .bottom) {
                if !isNearBottom, let last = rendered.last {
                    Button {
                        withAnimation(.easeOut(duration: 0.25)) {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    } label: {
                        HStack(spacing: 4) {
                            DuduIcon(systemName: "arrow.down")
                            Text("最新消息")
                        }
                        .font(DuduTheme.captionFont(weight: .medium))
                        .foregroundStyle(DuduTheme.duduText)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(DuduTheme.pinkSoft, in: Capsule())
                    }
                    .padding(.bottom, 12)
                }
            }
        }
    }
}
