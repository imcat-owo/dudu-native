import SwiftUI

// MARK: - ThinkingDrawerView (Phase D2)
//
// Bottom-sheet drawer that shows the FULL thinking text of one assistant
// thinking block.
//
// Trigger: tapping the "思考过程" header in ThinkingBlockView (the header
// carries the ThinkingIndicatorSlot while the thinking is still streaming,
// and a plain tappable affordance afterwards). Tapping the slot itself is
// the same button as the header — one affordance, no second hidden control.
//
// Layout:
//   - Header: slot/dot + "思考过程" + char count, close button on the right.
//     While live streaming, a "跟随" toggle keeps the scroll pinned to the tail.
//   - Short thinking (< sectionThreshold chars, or few paragraphs): full text.
//   - Long thinking: split into collapsible per-paragraph sections; the first
//     section starts expanded; an "全部展开 / 全部收起" row toggles them all.
//     While live, newly appeared sections auto-expand when "跟随" is on —
//     mirroring the engine's auto-expand-on-stream-start rule.
//
// Engine binding: @ObservedObject AssistantBlock.kind == .thinking, text in
// block.content (flushed periodically by flushThinkingBuffer() during stream).
// Never shows placeholder content: empty content renders the "正在思考…"
// waiting state, not fake text.
//
// Styling: DuduTheme only, small/narrow/pink. No emoji, no hardcoded colors.

struct ThinkingDrawerView: View {
    @ObservedObject var block: AssistantBlock
    /// True while this block belongs to the live, still-streaming turn.
    let isLive: Bool

    /// Content this long (chars) AND with multiple paragraphs gets sectioned.
    private static let sectionThreshold = 1_200
    /// A single paragraph longer than this is hard-chunked for sectioning.
    private static let maxParagraphLength = 2_000

    @State private var expandedSections: Set<Int> = [0]
    @State private var followLive = true
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
                .background(DuduTheme.duduDivider)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        if sections.isEmpty {
                            emptyState
                        } else if useSectionedLayout {
                            expandAllRow
                            ForEach(Array(sections.enumerated()), id: \.offset) { index, text in
                                sectionView(index: index, text: text)
                            }
                        } else {
                            Text(block.content)
                                .font(DuduTheme.bodyFont())
                                .foregroundStyle(DuduTheme.duduText)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        }
                        Color.clear
                            .frame(height: 1)
                            .id("tail")
                    }
                    .padding(.horizontal, DuduTheme.pagePadding)
                    .padding(.vertical, 12)
                }
                .onAppear {
                    // Pin to the tail once laid out (live case).
                    DispatchQueue.main.async {
                        if followLive {
                            proxy.scrollTo("tail", anchor: .bottom)
                        }
                    }
                }
                .onChange(of: block.content) { _, _ in
                    onContentChanged(proxy: proxy)
                }
            }
        }
        .background(DuduTheme.duduBackground)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            if isLive {
                ThinkingIndicatorSlot(phase: .streaming)
                    .scaleEffect(0.5)
                    .frame(width: 24, height: 24)
            } else {
                Circle()
                    .fill(DuduTheme.kitty)
                    .frame(width: 12, height: 12)
            }
            Text("思考过程")
                .font(DuduTheme.titleFont())
                .foregroundStyle(DuduTheme.duduText)
            Text("\(block.content.count) 字")
                .font(DuduTheme.captionFont())
                .foregroundStyle(DuduTheme.duduTextDim)
            Spacer()
            if isLive {
                Text("跟随")
                    .font(DuduTheme.captionFont())
                    .foregroundStyle(DuduTheme.duduTextDim)
                Toggle("", isOn: $followLive)
                    .labelsHidden()
                    .accessibilityLabel("跟随实时思考内容")
                    .tint(DuduTheme.pink)
            }
            Button {
                dismiss()
            } label: {
                DuduIcon(systemName: "xmark")
                    .font(DuduTheme.captionFont(weight: .semibold))
                    .foregroundStyle(DuduTheme.duduTextDim)
                    .frame(width: 28, height: 28)
                    .background(DuduTheme.duduIconChip, in: Circle())
            }
            .accessibilityLabel("关闭思考过程")
        }
        .padding(.horizontal, DuduTheme.pagePadding)
        .padding(.vertical, 10)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        HStack(spacing: 8) {
            if isLive {
                ThinkingIndicatorSlot(phase: .waiting)
                    .scaleEffect(0.5)
                    .frame(width: 24, height: 24)
                Text("正在思考…")
            } else {
                Text("暂无思考内容")
            }
        }
        .font(DuduTheme.captionFont())
        .foregroundStyle(DuduTheme.duduTextDim)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
        .accessibilityLabel(isLive ? "正在思考" : "暂无思考内容")
    }

    // MARK: - Sections

    /// Blank-line-split paragraphs; single over-long paragraphs are
    /// hard-chunked so the sectioned layout always has reasonable sizes.
    private var sections: [String] {
        let raw = block.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return [] }
        var parts = raw.components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if parts.count == 1, parts[0].count > Self.maxParagraphLength {
            parts = chunk(parts[0], length: Self.maxParagraphLength)
        }
        return parts
    }

    private var useSectionedLayout: Bool {
        block.content.count >= Self.sectionThreshold && sections.count > 1
    }

    private func chunk(_ text: String, length: Int) -> [String] {
        var out: [String] = []
        var start = text.startIndex
        while start < text.endIndex {
            let end = text.index(start, offsetBy: length, limitedBy: text.endIndex) ?? text.endIndex
            let piece = String(text[start..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !piece.isEmpty { out.append(piece) }
            start = end
        }
        return out
    }

    private var expandAllRow: some View {
        HStack {
            Spacer()
            Button(allExpanded ? "全部收起" : "全部展开") {
                withAnimation(.easeOut(duration: 0.2)) {
                    if allExpanded {
                        expandedSections = []
                    } else {
                        expandedSections = Set(sections.indices)
                    }
                }
            }
            .font(DuduTheme.captionFont(weight: .medium))
            .foregroundStyle(DuduTheme.duduTextDim)
        }
    }

    private var allExpanded: Bool {
        !sections.isEmpty && expandedSections.count == sections.count
    }

    private func sectionView(index: Int, text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.easeOut(duration: 0.2)) {
                    if expandedSections.contains(index) {
                        expandedSections.remove(index)
                    } else {
                        expandedSections.insert(index)
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Text("第 \(index + 1) 段")
                        .font(DuduTheme.captionFont(weight: .medium))
                        .foregroundStyle(DuduTheme.duduText)
                    Text("\(text.count) 字")
                        .font(DuduTheme.captionFont())
                        .foregroundStyle(DuduTheme.duduTextDim)
                    Spacer()
                    DuduIcon(systemName: expandedSections.contains(index) ? "chevron.up" : "chevron.down")
                        .font(DuduTheme.captionFont())
                        .foregroundStyle(DuduTheme.duduTextDim)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(expandedSections.contains(index) ? "收起第 \(index + 1) 段" : "展开第 \(index + 1) 段")

            if expandedSections.contains(index) {
                Text(text)
                    .font(DuduTheme.bodyFont())
                    .foregroundStyle(DuduTheme.duduText)
                    .textSelection(.enabled)
            }
        }
        .padding(10)
        .background(
            DuduTheme.duduCard,
            in: RoundedRectangle(cornerRadius: DuduTheme.radiusChip, style: .continuous)
        )
    }

    // MARK: - Live follow

    private func onContentChanged(proxy: ScrollViewProxy) {
        guard followLive else { return }
        let count = sections.count
        if count > 0, !expandedSections.contains(count - 1) {
            expandedSections.insert(count - 1)
        }
        withAnimation(.easeOut(duration: 0.2)) {
            proxy.scrollTo("tail", anchor: .bottom)
        }
    }
}
