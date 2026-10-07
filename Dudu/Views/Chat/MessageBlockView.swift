import SwiftUI
import UIKit

/// Phase C2 — renders one AssistantBlock inside an assistant bubble.
/// The block is @ObservedObject so streaming deltas re-render only this view.
///
/// - .text     → DuduMarkdownView (C1)
/// - .thinking → ThinkingIndicatorSlot + collapsible thinking text
/// - tool kinds → folded tool card (tap to expand)
/// - imageFilePath set → thumbnail (only when the file is on disk)
/// - .info     → small dim caption
struct MessageBlockView: View {
    @ObservedObject var block: AssistantBlock
    /// True when this block is the tail of the live, still-streaming turn.
    let isLiveBlock: Bool

    var body: some View {
        if block.imageFilePath != nil {
            imageBlock
        } else {
            switch block.kind {
            case .text:
                DuduMarkdownView(markdown: block.content)
            case .thinking:
                ThinkingBlockView(block: block, isLiveBlock: isLiveBlock)
            case .info:
                Text(block.content)
                    .font(DuduTheme.captionFont())
                    .foregroundStyle(DuduTheme.duduTextDim)
            default:
                // Any tool kind on its own (runs of >2 were folded by
                // BlockGroup before reaching here).
                ToolCardView(blocks: [block])
            }
        }
    }

    // MARK: - Image block

    @ViewBuilder
    private var imageBlock: some View {
        if let path = block.imageFilePath,
           FileManager.default.fileExists(atPath: path),
           let uiImage = UIImage(contentsOfFile: path) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFit()
                .frame(maxHeight: 180)
                .clipShape(RoundedRectangle(cornerRadius: DuduTheme.radiusChip, style: .continuous))
        }
        // A declared image with no file on disk renders nothing —
        // never a fake thumbnail.
    }
}

// MARK: - Thinking block

/// Collapsible thinking text. While the thinking is still streaming, the
/// thinking-indicator slot sits in the header (scaled to header size);
/// once streaming ends it becomes a plain tappable header.
struct ThinkingBlockView: View {
    @ObservedObject var block: AssistantBlock
    let isLiveBlock: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                block.isThinkingExpanded.toggle()
                block.thinkingUserToggled = true
            } label: {
                HStack(spacing: 6) {
                    if isLiveBlock {
                        ThinkingIndicatorSlot(phase: .streaming)
                            .scaleEffect(0.45)
                            .frame(width: 20, height: 20)
                    }
                    Text("思考过程")
                        .font(DuduTheme.captionFont(weight: .medium))
                        .foregroundStyle(DuduTheme.duduTextDim)
                    Image(systemName: block.isThinkingExpanded ? "chevron.up" : "chevron.down")
                        .font(DuduTheme.captionFont())
                        .foregroundStyle(DuduTheme.duduTextDim)
                }
            }
            .buttonStyle(.plain)

            if block.isThinkingExpanded, !block.content.isEmpty {
                Text(block.content)
                    .font(DuduTheme.captionFont())
                    .foregroundStyle(DuduTheme.duduTextDim)
                    .textSelection(.enabled)
            }
        }
    }
}

// MARK: - Tool card

/// Kelivo-style collapsible tool-call card: one line (status dot + tool
/// name + chevron), tap to expand the full output.
struct ToolCardView: View {
    let blocks: [AssistantBlock]
    @State private var expanded = false

    private var title: String {
        if blocks.count > 1 { return "\(blocks.count) 个工具调用" }
        let desc = blocks[0].toolDescription
        return desc.isEmpty ? toolKindLabel(blocks[0].kind) : desc
    }

    private var aggregateStatus: ToolBlockStatus {
        // Running beats everything; then failure; then cancellation.
        let statuses = blocks.compactMap(\.toolStatus)
        if statuses.contains(where: { $0 == .running || isStreamingStatus($0) }) { return .running }
        if let failed = statuses.first(where: isFailedStatus) { return failed }
        if statuses.contains(.cancelled) { return .cancelled }
        return .success
    }

    private func isStreamingStatus(_ status: ToolBlockStatus) -> Bool {
        if case .streaming = status { return true }
        return false
    }

    private func isFailedStatus(_ status: ToolBlockStatus) -> Bool {
        if case .failed = status { return true }
        return false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeOut(duration: 0.2)) { expanded.toggle() }
            } label: {
                HStack(spacing: 8) {
                    statusDot
                    Image(systemName: toolIcon(blocks[0].kind))
                        .font(DuduTheme.captionFont())
                        .foregroundStyle(DuduTheme.duduTextDim)
                    Text(title)
                        .font(DuduTheme.captionFont(weight: .medium))
                        .foregroundStyle(DuduTheme.duduText)
                        .lineLimit(1)
                    Spacer()
                    Text(statusText)
                        .font(DuduTheme.captionFont())
                        .foregroundStyle(DuduTheme.duduTextDim)
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(DuduTheme.captionFont())
                        .foregroundStyle(DuduTheme.duduTextDim)
                }
                .padding(10)
            }
            .buttonStyle(.plain)

            if expanded {
                Divider()
                    .background(DuduTheme.duduDivider)
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(blocks) { block in
                        toolDetail(block)
                    }
                }
                .padding(10)
            }
        }
        .background(
            DuduTheme.duduIconChip.opacity(0.45),
            in: RoundedRectangle(cornerRadius: DuduTheme.radiusChip, style: .continuous)
        )
    }

    private func toolDetail(_ block: AssistantBlock) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if blocks.count > 1, !block.toolDescription.isEmpty {
                Text(block.toolDescription)
                    .font(DuduTheme.captionFont(weight: .semibold))
                    .foregroundStyle(DuduTheme.duduText)
                    .lineLimit(1)
            }
            if !block.content.isEmpty {
                Text(block.content)
                    .font(DuduTheme.monoFont(size: 11))
                    .foregroundStyle(DuduTheme.duduTextDim)
                    .lineLimit(24)
                    .textSelection(.enabled)
            }
        }
    }

    // MARK: Status presentation (text labels carry state; color is secondary)

    @ViewBuilder
    private var statusDot: some View {
        switch aggregateStatus {
        case .running, .streaming:
            Circle()
                .fill(DuduTheme.pink)
                .frame(width: 8, height: 8)
        case .failed:
            Circle()
                .fill(DuduTheme.duduText)
                .frame(width: 8, height: 8)
        default:
            Circle()
                .fill(DuduTheme.duduTextDim.opacity(0.5))
                .frame(width: 8, height: 8)
        }
    }

    private var statusText: String {
        switch aggregateStatus {
        case .running, .streaming: return "运行中"
        case .failed: return "失败"
        case .cancelled: return "已取消"
        default: return "完成"
        }
    }

    private func toolIcon(_ kind: AssistantBlockKind) -> String {
        switch kind {
        case .shellTool: return "terminal"
        case .fileReadTool: return "doc.text"
        case .fileWriteTool: return "doc.badge.plus"
        case .fileEditTool: return "pencil"
        case .browserTool: return "globe"
        case .readImageTool: return "photo"
        case .memoryTool: return "brain"
        case .askUserTool: return "questionmark.circle"
        case .text, .thinking, .info: return "ellipsis"
        }
    }

    private func toolKindLabel(_ kind: AssistantBlockKind) -> String {
        switch kind {
        case .shellTool: return "终端命令"
        case .fileReadTool: return "读取文件"
        case .fileWriteTool: return "写入文件"
        case .fileEditTool: return "编辑文件"
        case .browserTool: return "浏览器操作"
        case .readImageTool: return "读取图片"
        case .memoryTool: return "记忆操作"
        case .askUserTool: return "向用户提问"
        case .text, .thinking, .info: return "工具调用"
        }
    }
}
