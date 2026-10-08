import SwiftUI
import UIKit

// MARK: - ThinkingDrawerView (Phase D2)
//
// The FULL thinking text of one assistant thinking block, shown inside
// ThinkingDrawerOverlay (the custom bottom drawer — Wave 2 Item 9).
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
    /// Called by the close button (the overlay owns dismissal).
    let onClose: () -> Void

    /// Content this long (chars) AND with multiple paragraphs gets sectioned.
    private static let sectionThreshold = 1_200
    /// A single paragraph longer than this is hard-chunked for sectioning.
    private static let maxParagraphLength = 2_000

    @State private var expandedSections: Set<Int> = [0]
    @State private var followLive = true

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
                onClose()
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

// MARK: - ThinkingDrawerOverlay (Wave 2 Item 9)
//
// Custom bottom drawer chrome for the thinking drawer, replacing the system
// .sheet (html-2 定稿): dimmed scrim with tap-to-dismiss, 22pt top corner
// radius, 60%-of-screen-height card, spring present/dismiss, drag-down to
// dismiss. Rendered as an .overlay at the presentation site — the drawer
// feels like part of Dudu, not iOS system UI.
//
// Screen anchoring: the presentation sites are small hosts deep in the chat
// (a 44pt slot, a header button, the peek-cat host). A GeometryReader reads
// the host's global frame and positions a screen-sized container so the
// drawer lands on the real screen bottom. The anchor recomputes live on
// every layout pass so message-list scrolling can't move the drawer
// mid-presentation.

struct ThinkingDrawerOverlay: View {
    let block: AssistantBlock
    let isLive: Bool
    /// Called after the exit animation lands; the site removes the overlay.
    let onDismiss: () -> Void

    /// Drawer height = 60% of screen (html-2 定稿 tuned value).
    private static let heightFraction: CGFloat = 0.6
    /// Top corner radius (html-2 定稿).
    private static let cornerRadius: CGFloat = 22
    /// Dragging the card this far down (or flinging it) dismisses.
    private static let dismissThreshold: CGFloat = 120

    @State private var shown = false
    @State private var dragY: CGFloat = 0
    @State private var dismissing = false

    private var spring: Animation {
        .spring(response: 0.38, dampingFraction: 0.88)
    }

    /// Home-indicator clearance from the key window.
    private var bottomSafeInset: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first?.safeAreaInsets.bottom ?? 0
    }

    var body: some View {
        GeometryReader { geo in
            let host = geo.frame(in: .global)
            let screen = UIScreen.main.bounds
            let cardHeight = screen.height * Self.heightFraction + bottomSafeInset
            ZStack(alignment: .bottom) {
                // Scrim — tap anywhere outside the card to dismiss.
                DuduTheme.kitty
                    .opacity(scrimOpacity(cardHeight: cardHeight))
                    .onTapGesture { dismiss() }
                    .accessibilityLabel("关闭思考过程")
                    .accessibilityAddTraits(.isButton)
                // Drawer card.
                VStack(spacing: 0) {
                    grabber
                    ThinkingDrawerView(block: block, isLive: isLive, onClose: dismiss)
                        .padding(.bottom, bottomSafeInset)
                }
                .frame(height: cardHeight)
                .frame(maxWidth: .infinity)
                .background(DuduTheme.duduBackground)
                .clipShape(UnevenRoundedRectangle(
                    topLeadingRadius: Self.cornerRadius,
                    bottomLeadingRadius: 0,
                    bottomTrailingRadius: 0,
                    topTrailingRadius: Self.cornerRadius,
                    style: .continuous))
                .offset(y: cardOffset(cardHeight: cardHeight))
                .gesture(dragGesture(cardHeight: cardHeight))
                .accessibilityElement(children: .contain)
            }
            .frame(width: screen.width, height: screen.height, alignment: .bottom)
            .position(anchorPoint(host: host, screen: screen))
            .onAppear {
                withAnimation(spring) { shown = true }
            }
        }
    }

    // MARK: - Chrome pieces

    private var grabber: some View {
        Capsule()
            .fill(DuduTheme.duduTextDim.opacity(0.4))
            .frame(width: 36, height: 5)
            .padding(.top, 10)
            .padding(.bottom, 6)
            .accessibilityHidden(true)
    }

    private func anchorPoint(host: CGRect, screen: CGRect) -> CGPoint {
        // Overlay-local origin is the host frame's top-left; the screen-sized
        // container must be centered on the real screen center. Recomputed
        // live so scrolling the host list keeps the drawer screen-anchored.
        return CGPoint(x: screen.midX - host.minX, y: screen.midY - host.minY)
    }

    private func cardOffset(cardHeight: CGFloat) -> CGFloat {
        // Hidden: parked fully below the screen. Shown: follows the finger.
        shown ? dragY : cardHeight
    }

    private func scrimOpacity(cardHeight: CGFloat) -> Double {
        guard shown else { return 0 }
        let dragProgress = min(max(dragY / cardHeight, 0), 1)
        return 0.45 * (1 - dragProgress)
    }

    private func dragGesture(cardHeight: CGFloat) -> some Gesture {
        DragGesture()
            .onChanged { value in
                guard shown, !dismissing else { return }
                // Downward only — the card never stretches upward.
                dragY = max(0, value.translation.height)
            }
            .onEnded { value in
                guard shown, !dismissing else { return }
                let flung = value.predictedEndTranslation.height > cardHeight * 0.5
                if value.translation.height > Self.dismissThreshold || flung {
                    dismiss()
                } else {
                    withAnimation(spring) { dragY = 0 }
                }
            }
    }

    // MARK: - Dismiss

    private func dismiss() {
        guard !dismissing else { return }
        dismissing = true
        withAnimation(spring) {
            shown = false
            dragY = 0
        }
        // Let the exit animation land before the site removes the overlay.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            onDismiss()
        }
    }
}
