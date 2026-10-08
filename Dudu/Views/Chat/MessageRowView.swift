import SwiftUI
import UIKit

// MARK: - Chat bubble shape (Wave 2 item 4)

/// Asymmetric chat-bubble corners per html-2 定稿: three corners 17pt, one
/// 6pt "tail" corner nearest the speaker's avatar — the handmade feel.
struct BubbleShape: Shape {
    /// Which side the tail sits on.
    enum TailSide {
        /// AI bubbles: avatar sits left, tail tightens bottom-leading.
        case avatarLeading
        /// User bubbles: avatar sits right, tail tightens bottom-trailing.
        case avatarTrailing
    }

    let tailSide: TailSide
    private static let round: CGFloat = DuduTheme.radiusChip // 17pt per html-2
    private static let tail: CGFloat = 6

    private var cornerRadii: RectangleCornerRadii {
        switch tailSide {
        case .avatarLeading:
            RectangleCornerRadii(topLeading: Self.round, bottomLeading: Self.tail,
                                 bottomTrailing: Self.round, topTrailing: Self.round)
        case .avatarTrailing:
            RectangleCornerRadii(topLeading: Self.round, bottomLeading: Self.round,
                                 bottomTrailing: Self.tail, topTrailing: Self.round)
        }
    }

    func path(in rect: CGRect) -> Path {
        UnevenRoundedRectangle(cornerRadii: cornerRadii, style: .continuous).path(in: rect)
    }
}

// MARK: - Message row

/// Phase C2 — one message row. Holds its ChatMessage as @ObservedObject so
/// streaming updates re-render only this row.
///
/// Layout (plan §7): user rows right-aligned (pink-soft bubble + avatar on
/// the right), assistant rows left-aligned (card bubble + avatar on the left).
/// Bubbles are small and narrow; text is never pure black/white.
struct MessageRowView: View {
    @ObservedObject var message: ChatMessage
    @EnvironmentObject private var vm: AIChatViewModel
    @EnvironmentObject private var appearance: AppearanceStudio

    /// Consecutive tool blocks (>2) fold into one Kelivo-style card.
    private var groups: [BlockGroup] {
        BlockGroup.grouped(from: message.blocks)
    }

    /// True while this message is the live, still-streaming turn.
    private var isLive: Bool {
        vm.isProcessing && message.id == vm.messages.last?.id
    }

    /// Retry/delete/read-aloud are hidden for the message currently being generated.
    private var isActionable: Bool { !isLive }

    /// Finished-animation bookkeeping: the stretch-squash plays once when
    /// the turn ends, but only if the cat was actually visible during it.
    @State private var catWasVisible = false
    @State private var finishedNonce = 0

    /// Engine-driven phase (thinking/tool); nil when the cat must hide.
    private var enginePhase: ThinkingIndicatorSlot.Phase? {
        ThinkingIndicatorSlot.phase(for: message)
    }

    /// Display phase: the finished one-shot takes over briefly after the
    /// turn ends, then the cat hides.
    private var displayPhase: ThinkingIndicatorSlot.Phase? {
        finishedNonce > 0 ? .finished : enginePhase
    }

    /// The message's thinking block, for the cat's tap-to-open drawer.
    private var thinkingBlock: AssistantBlock? {
        message.blocks.first { $0.kind == .thinking }
    }

    /// Speaker button state: true from the local tap until playback actually
    /// stops (either the local stop tap or the engine settling isReadingAloud).
    @State private var readingAloud = false

    var body: some View {
        switch message.role {
        case .compactDivider:
            compactDividerRow
        case .systemInfo:
            systemInfoRow
        case .user:
            userRow
        case .assistant:
            assistantRow
        }
    }

    // MARK: - User

    private var userRow: some View {
        HStack(alignment: .top, spacing: 8) {
            Spacer(minLength: 44)
            VStack(alignment: .trailing, spacing: 8) {
                if !message.attachments.isEmpty {
                    userAttachmentStrip
                }
                if !message.content.isEmpty {
                    Text(message.content)
                        .font(DuduTheme.messageFont())
                        .foregroundStyle(DuduTheme.duduText)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(
                            DuduTheme.pinkSoft,
                            in: BubbleShape(tailSide: .avatarTrailing)
                        )
                }
                // [C2-followup-queue] A follow-up sent while the AI was busy
                // waits its turn — the bubble is already in the list with a
                // "排队中" tag so she sees it was never lost. The tag clears
                // when the post-turn drain picks the prompt up.
                if message.isQueued {
                    Text(L10n.string("agent.status.queued"))
                        .font(DuduTheme.captionFont())
                        .foregroundStyle(DuduTheme.duduTextDim)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(DuduTheme.duduIconChip, in: Capsule())
                }
            }
            avatar(isUser: true)
        }
        .contextMenu { messageMenu }
    }

    /// Image thumbnails for attachments whose file is on disk; a filename
    /// chip otherwise. Missing files render nothing — never a fake image.
    private var userAttachmentStrip: some View {
        HStack(spacing: 8) {
            ForEach(message.attachments) { attachment in
                if attachment.isImage,
                   FileManager.default.fileExists(atPath: attachment.path),
                   let uiImage = UIImage(contentsOfFile: attachment.path) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 120, height: 120)
                        .clipShape(RoundedRectangle(cornerRadius: DuduTheme.radiusChip, style: .continuous))
                } else {
                    HStack(spacing: 4) {
                        DuduIcon(systemName: "doc")
                            .font(DuduTheme.captionFont())
                        Text(attachment.fileName)
                            .font(DuduTheme.captionFont())
                            .lineLimit(1)
                    }
                    .foregroundStyle(DuduTheme.duduTextDim)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(DuduTheme.duduIconChip, in: Capsule())
                }
            }
        }
    }

    // MARK: - Assistant

    private var assistantRow: some View {
        HStack(alignment: .top, spacing: 8) {
            avatar(isUser: false)
            VStack(alignment: .leading, spacing: 6) {
                if groups.isEmpty {
                    // Opening wait: no blocks yet — just the thinking slot,
                    // never an empty bubble.
                    if let phase = displayPhase {
                        ThinkingIndicatorSlot(phase: phase, thinkingBlock: thinkingBlock, isLiveBlock: isLive)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(groups) { group in
                            MessageBlockGroupView(
                                group: group,
                                isLiveBlock: isLive && group.lastBlockId == message.blocks.last?.id
                            )
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        DuduTheme.duduCard,
                        in: BubbleShape(tailSide: .avatarLeading)
                    )
                    .overlay(alignment: .topLeading) {
                        // Approved design spec: the 44pt slot's left edge
                        // sits 8pt inside the bubble's left edge; its bottom
                        // (paws) sits 4pt below the bubble's top edge.
                        if let phase = displayPhase {
                            ThinkingIndicatorSlot(phase: phase, thinkingBlock: thinkingBlock, isLiveBlock: isLive)
                                .offset(x: 8, y: -40)
                        }
                    }
                    // 29pt top margin reserved while the cat shows: the
                    // overlay takes no layout space and the slot extends
                    // 40pt above the bubble, so without this it would
                    // collide with the previous row (rows are 6pt apart).
                    // Applied after .overlay so the slot's alignment frame
                    // stays the bubble's own top edge.
                    .padding(.top, displayPhase != nil ? 29 : 0)
                }
                if let error = message.error, !error.isEmpty {
                    assistantErrorRow(error)
                }
                if isActionable {
                    readAloudFooter
                }
            }
            Spacer(minLength: 44)
        }
        .contextMenu { messageMenu }
        .onAppear {
            // A row created mid-turn (e.g. list rebuild) still counts as
            // having shown the cat for the finished one-shot.
            if enginePhase != nil { catWasVisible = true }
        }
        .onChange(of: enginePhase != nil) { _, visible in
            if visible { catWasVisible = true }
        }
        .onChange(of: isLive) { _, live in
            if live {
                // New turn: reset the finished one-shot bookkeeping.
                catWasVisible = false
                finishedNonce = 0
            } else if catWasVisible {
                // The turn just ended after showing the cat: play the
                // finished stretch-squash once, then hide (1.9s program).
                catWasVisible = false
                finishedNonce += 1
                let n = finishedNonce
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.95) {
                    if finishedNonce == n { finishedNonce = 0 }
                }
            }
        }
    }

    private func assistantErrorRow(_ error: String) -> some View {
        HStack(spacing: 6) {
            DuduIcon(systemName: "exclamationmark.circle")
                .font(DuduTheme.captionFont())
            Text(error)
                .font(DuduTheme.captionFont())
                .lineLimit(2)
            if isActionable {
                Button("重试") {
                    vm.regenerateAssistantMessage(message.id)
                }
                .font(DuduTheme.captionFont(weight: .semibold))
            }
        }
        .foregroundStyle(DuduTheme.duduTextDim)
        .padding(.top, 2)
    }

    // MARK: - Read aloud (Phase D1)

    /// Speaker button under the assistant bubble. Tap → the engine reads the
    /// message from the start (AVSpeechSynthesizer / configured TTS service /
    /// voice group — whichever the resolution chain picks); tap again → stop.
    private var readAloudFooter: some View {
        HStack {
            Spacer(minLength: 0)
            Button {
                toggleReadAloud()
            } label: {
                HStack(spacing: 4) {
                    DuduIcon(systemName: isThisReading ? "stop.fill" : "speaker.wave.2.fill")
                        .font(DuduTheme.captionFont())
                    Text(isThisReading ? "停止" : "朗读")
                        .font(DuduTheme.captionFont())
                }
                .foregroundStyle(DuduTheme.duduTextDim)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(DuduTheme.duduIconChip, in: Capsule())
            }
            .accessibilityLabel(isThisReading ? "停止朗读" : "朗读这条消息")
        }
        .onChange(of: vm.isReadingAloud) { _, reading in
            if !reading { readingAloud = false }
        }
    }

    /// True only while THIS message's playback is running.
    private var isThisReading: Bool {
        readingAloud && vm.isReadingAloud
    }

    private func toggleReadAloud() {
        if isThisReading {
            vm.stopSpeech()
            readingAloud = false
        } else {
            readingAloud = true
            vm.readReplyFromStart(message)
        }
    }

    // MARK: - Divider / system info

    private var compactDividerRow: some View {
        HStack(spacing: 8) {
            DuduTheme.duduDivider.frame(height: 1)
            Text(L10n.string("chat.message.contextCompressed"))
                .font(DuduTheme.captionFont())
                .foregroundStyle(DuduTheme.duduTextDim)
            DuduTheme.duduDivider.frame(height: 1)
        }
        .padding(.vertical, 4)
    }

    private var systemInfoRow: some View {
        Text(message.content)
            .font(DuduTheme.captionFont())
            .foregroundStyle(DuduTheme.duduTextDim)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
    }

    // MARK: - Avatar

    private func avatar(isUser: Bool) -> some View {
        Group {
            if isUser, SoulIconImage.isDataURI(appearance.userAvatar) {
                SoulIconView(icon: appearance.userAvatar, size: 34)
            } else if isUser {
                ZStack {
                    Circle()
                        .fill(DuduTheme.duduIconChip)
                    DuduIcon(systemName: "person.fill")
                        .font(DuduTheme.captionFont(weight: .medium))
                        .foregroundStyle(DuduTheme.pink)
                }
            } else {
                // [D18-avatar] AI avatar: animated emotion state machine.
                // Falls back to the static avatar (then the old sparkles
                // chip) when a state's clip is missing — never blank.
                AvatarView(size: 34)
            }
        }
        .frame(width: 34, height: 34)
        .clipShape(Circle())
        // html-2 定稿: 34px avatar with 2px white ring.
        .overlay(Circle().stroke(Color.white, lineWidth: 2))
    }

    // MARK: - Long-press menu

    @ViewBuilder
    private var messageMenu: some View {
        Button {
            UIPasteboard.general.string = message.plainTextForCopy
        } label: {
            Label("复制", systemImage: "doc.on.doc")
        }
        if message.role == .assistant, isActionable {
            Button {
                vm.regenerateAssistantMessage(message.id)
            } label: {
                Label("重新生成", systemImage: "arrow.clockwise")
            }
        }
        if isActionable {
            Button(role: .destructive) {
                deleteMessage()
            } label: {
                Label("删除", systemImage: "trash")
            }
        }
    }

    private func deleteMessage() {
        if let rowId = message.dbRowId, let sid = vm.sessionId {
            Task { await ChatStore.shared.deleteMessagesByIds(sessionId: sid, ids: [rowId]) }
        }
        vm.messages.removeAll { $0.id == message.id }
    }
}

// MARK: - Block grouping

/// Consecutive tool-kind blocks fold into one card when there are more than
/// two in a run (Kelivo-style); text / thinking / info always stay solo.
enum BlockGroup: Identifiable {
    case single(AssistantBlock)
    case toolRun([AssistantBlock])

    var id: String {
        switch self {
        case .single(let block): return block.id.uuidString
        case .toolRun(let blocks): return blocks.map(\.id.uuidString).joined(separator: "+")
        }
    }

    /// The id of the last block in this group, for live-streaming detection.
    var lastBlockId: UUID {
        switch self {
        case .single(let block): return block.id
        case .toolRun(let blocks): return blocks.last?.id ?? UUID()
        }
    }

    static func grouped(from blocks: [AssistantBlock]) -> [BlockGroup] {
        var result: [BlockGroup] = []
        var run: [AssistantBlock] = []
        func flushRun() {
            guard !run.isEmpty else { return }
            if run.count > 2 {
                result.append(.toolRun(run))
            } else {
                result.append(contentsOf: run.map(BlockGroup.single))
            }
            run.removeAll()
        }
        for block in blocks {
            if block.kind.isToolKind {
                run.append(block)
            } else {
                flushRun()
                result.append(.single(block))
            }
        }
        flushRun()
        return result
    }
}

struct MessageBlockGroupView: View {
    let group: BlockGroup
    let isLiveBlock: Bool

    var body: some View {
        switch group {
        case .single(let block):
            MessageBlockView(block: block, isLiveBlock: isLiveBlock)
                .id(block.id)
        case .toolRun(let blocks):
            ToolCardView(blocks: blocks)
        }
    }
}

// MARK: - Copy text

private extension ChatMessage {
    /// Plain text for the copy action: user content, or the assistant's
    /// text blocks joined (thinking and tool output excluded).
    var plainTextForCopy: String {
        if role == .user { return content }
        let texts = blocks.compactMap { block -> String? in
            guard case .text = block.kind, !block.content.isEmpty else { return nil }
            return block.content
        }
        return texts.isEmpty ? content : texts.joined(separator: "\n\n")
    }
}
