import SwiftUI
import UIKit

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

    /// Retry/delete are hidden for the message currently being generated.
    private var isActionable: Bool { !isLive }

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
                            in: RoundedRectangle(cornerRadius: DuduTheme.radiusCard, style: .continuous)
                        )
                }
                // [C2-followup-queue] A follow-up sent while the AI was busy
                // waits its turn — the bubble is already in the list with a
                // "排队中" tag so she sees it was never lost. The tag clears
                // when the post-turn drain picks the prompt up.
                if message.isQueued {
                    Text("排队中")
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
                        Image(systemName: "doc")
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
                    if let phase = ThinkingIndicatorSlot.phase(for: message) {
                        ThinkingIndicatorSlot(phase: phase)
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
                        in: RoundedRectangle(cornerRadius: DuduTheme.radiusCard, style: .continuous)
                    )
                    .overlay(alignment: .topLeading) {
                        // The slot straddles the bubble's top edge (contract:
                        // 44pt box, parent offsets by -22pt).
                        if let phase = ThinkingIndicatorSlot.phase(for: message) {
                            ThinkingIndicatorSlot(phase: phase)
                                .offset(x: -12, y: -22)
                        }
                    }
                }
                if let error = message.error, !error.isEmpty {
                    assistantErrorRow(error)
                }
            }
            Spacer(minLength: 44)
        }
        .contextMenu { messageMenu }
    }

    private func assistantErrorRow(_ error: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.circle")
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

    // MARK: - Divider / system info

    private var compactDividerRow: some View {
        HStack(spacing: 8) {
            DuduTheme.duduDivider.frame(height: 1)
            Text("上下文已压缩")
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
                SoulIconView(icon: appearance.userAvatar, size: 28)
            } else {
                ZStack {
                    Circle()
                        .fill(DuduTheme.duduIconChip)
                    Image(systemName: isUser ? "person.fill" : "sparkles")
                        .font(DuduTheme.captionFont(weight: .medium))
                        .foregroundStyle(DuduTheme.pink)
                }
            }
        }
        .frame(width: 28, height: 28)
        .clipShape(Circle())
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
