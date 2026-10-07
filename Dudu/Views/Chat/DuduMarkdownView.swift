import SwiftUI
import UIKit

// MARK: - DuduMarkdownView
//
// Fresh Dudu-styled Markdown renderer (G3 answer).
//
//   Structure : engine `MarkdownContent` (cmark-gfm block AST: BlockNode).
//   Inline    : native SwiftUI Text over an AttributedString built from
//               InlineNode (bold / italic / strikethrough / inline code /
//               links / soft+hard breaks).
//   Code      : custom DuduCodeBlockView with a real copy button.
//   Math      : LaTeX source is shown code-styled (honest — no math renderer
//               is wired in C1).
//   Images    : remote images are NOT fetched in C1; the alt text is shown
//               as a caption marker (honest).
//
// Behavior reference (segments → views mapping) was studied in
// openminis-fix/.../Views/Chat/MarkdownRenderView.swift; this file is
// written fresh for Dudu — no code copied.

struct DuduMarkdownView: View {
    let markdown: String

    var body: some View {
        let content = MarkdownContent(markdown)
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(content.blocks.enumerated()), id: \.offset) { _, block in
                DuduMarkdownBlockView(block: block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Blocks

private struct DuduMarkdownBlockView: View {
    let block: BlockNode

    var body: some View {
        switch block {
        case .paragraph(let inlines):
            DuduInlineText(inlines: inlines)
        case .heading(let level, let inlines):
            DuduInlineText(inlines: inlines, style: .heading(level: level))
                .padding(.top, level <= 2 ? 6 : 2)
        case .bulletedList(let isTight, let items):
            DuduListView(isTight: isTight, count: items.count) { _ in
                listMarkerBullet
            } content: { index in
                blockChildren(items[index].children)
            }
        case .numberedList(let isTight, let start, let items):
            DuduListView(isTight: isTight, count: items.count) { index in
                Text("\(start + index).")
                    .font(DuduTheme.bodyFont(weight: .medium))
                    .foregroundStyle(DuduTheme.duduTextDim)
            } content: { index in
                blockChildren(items[index].children)
            }
        case .taskList(let isTight, let items):
            DuduListView(isTight: isTight, count: items.count) { index in
                Image(systemName: items[index].isCompleted ? "checkmark.square.fill" : "square")
                    .font(.system(size: DuduTheme.bodySize, weight: .regular))
                    .foregroundStyle(items[index].isCompleted ? DuduTheme.pink : DuduTheme.duduTextDim)
            } content: { index in
                blockChildren(items[index].children)
            }
        case .codeBlock(let fenceInfo, let content):
            DuduCodeBlockView(language: fenceInfo, code: content)
        case .blockquote(let children):
            HStack(alignment: .top, spacing: 10) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(DuduTheme.pink)
                    .frame(width: 3)
                blockChildren(children)
            }
        case .table(let alignments, let rows):
            DuduTableView(alignments: alignments, rows: rows)
        case .thematicBreak:
            DuduTheme.duduDivider
                .frame(height: 1)
                .padding(.vertical, 4)
        case .htmlBlock(let content):
            // Honest: raw HTML is shown as code-styled text, not rendered.
            Text(content)
                .font(DuduTheme.monoFont(size: 12))
                .foregroundStyle(DuduTheme.duduTextDim)
        case .mathBlock(let content):
            // Honest: LaTeX source shown code-styled; no math renderer in C1.
            Text(content)
                .font(DuduTheme.monoFont(size: 12))
                .foregroundStyle(DuduTheme.duduText)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(DuduTheme.duduIconChip.opacity(0.5), in: RoundedRectangle(cornerRadius: DuduTheme.radiusChip, style: .continuous))
        }
    }

    @ViewBuilder
    private func blockChildren(_ children: [BlockNode]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(children.enumerated()), id: \.offset) { _, child in
                DuduMarkdownBlockView(block: child)
            }
        }
    }

    private var listMarkerBullet: some View {
        Circle()
            .fill(DuduTheme.pink)
            .frame(width: 6, height: 6)
            .padding(.top, 6)
    }
}

private struct DuduListView<Marker: View, Content: View>: View {
    let isTight: Bool
    let count: Int
    let marker: (Int) -> Marker
    let content: (Int) -> Content

    init(isTight: Bool, count: Int,
         @ViewBuilder marker: @escaping (Int) -> Marker,
         @ViewBuilder content: @escaping (Int) -> Content) {
        self.isTight = isTight
        self.count = count
        self.marker = marker
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: isTight ? 3 : 7) {
            ForEach(0..<count, id: \.self) { index in
                HStack(alignment: .top, spacing: 9) {
                    marker(index)
                    content(index)
                }
            }
        }
    }
}

// MARK: - Inline text (AttributedString)

private struct DuduInlineText: View {
    enum Style {
        case body
        case heading(level: Int)
    }

    let inlines: [InlineNode]
    var style: Style = .body

    var body: some View {
        Text(build())
            .lineSpacing(3)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func baseFont() -> Font {
        switch style {
        case .body:
            return DuduTheme.messageFont()
        case .heading(let level):
            switch level {
            case 1: return DuduTheme.headingFont(delta: 2)
            case 2: return DuduTheme.titleFont()
            case 3: return DuduTheme.bodyFont(weight: .semibold)
            default: return DuduTheme.captionFont(weight: .semibold)
            }
        }
    }

    private struct RunStyle {
        var font: Font
        var color: Color
        var background: Color?
        var underline = false
        var strikethrough = false
        var link: URL?
    }

    private func build() -> AttributedString {
        var out = AttributedString()
        let base = RunStyle(font: baseFont(), color: DuduTheme.duduText)
        append(inlines, style: base, to: &out)
        return out
    }

    private func append(_ inlines: [InlineNode], style: RunStyle, to out: inout AttributedString) {
        for node in inlines {
            switch node {
            case .text(let s):
                out.append(run(s, style: style))
            case .softBreak, .lineBreak:
                out.append(AttributedString("\n"))
            case .code(let s):
                var st = style
                st.font = DuduTheme.monoFont(size: 12)
                st.background = DuduTheme.pinkSoft
                out.append(run(s, style: st))
            case .html(let s):
                out.append(run(s, style: style))
            case .emphasis(let children):
                var st = style
                st.font = style.font.italic()
                append(children, style: st, to: &out)
            case .strong(let children):
                var st = style
                st.font = style.font.bold()
                append(children, style: st, to: &out)
            case .strikethrough(let children):
                var st = style
                st.strikethrough = true
                append(children, style: st, to: &out)
            case .link(let destination, let children):
                var st = style
                st.color = DuduTheme.accent
                st.underline = true
                st.link = URL(string: destination)
                append(children, style: st, to: &out)
            case .image(_, let children):
                // Honest: no remote image loading in C1 — show the alt text.
                let alt = plainText(children)
                var st = style
                st.font = DuduTheme.captionFont()
                st.color = DuduTheme.duduTextDim
                out.append(run(alt.isEmpty ? "[图片]" : "[图片：\(alt)]", style: st))
            case .inlineMath(let latex):
                // Honest: LaTeX source shown code-styled.
                var st = style
                st.font = DuduTheme.monoFont(size: 12)
                st.background = DuduTheme.pinkSoft
                out.append(run(latex, style: st))
            }
        }
    }

    private func run(_ string: String, style: RunStyle) -> AttributedString {
        var container = AttributeContainer()
        container.font = style.font
        container.foregroundColor = style.color
        if let background = style.background {
            container.backgroundColor = background
        }
        if style.underline {
            container.underlineStyle = Text.LineStyle.single
        }
        if style.strikethrough {
            container.strikethroughStyle = Text.LineStyle.single
        }
        if let link = style.link {
            container.link = link
        }
        return AttributedString(string, attributes: container)
    }

    private func plainText(_ inlines: [InlineNode]) -> String {
        var out = ""
        for node in inlines {
            switch node {
            case .text(let s), .code(let s), .html(let s), .inlineMath(let s):
                out += s
            case .softBreak, .lineBreak:
                out += " "
            case .emphasis(let c), .strong(let c), .strikethrough(let c),
                 .link(_, let c), .image(_, let c):
                out += plainText(c)
            }
        }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Code block (custom, with copy button)

private struct DuduCodeBlockView: View {
    let language: String?
    let code: String
    @State private var copied = false

    private var languageLabel: String {
        guard let language, !language.isEmpty else { return "代码" }
        return language
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(languageLabel)
                    .font(DuduTheme.captionFont())
                    .foregroundStyle(DuduTheme.duduTextDim)
                Spacer()
                Button {
                    UIPasteboard.general.string = code
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                        copied = false
                    }
                } label: {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: DuduTheme.captionSize, weight: .medium))
                        .foregroundStyle(copied ? DuduTheme.success : DuduTheme.duduTextDim)
                }
                .accessibilityLabel("复制代码")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            ScrollView(.horizontal, showsIndicators: false) {
                Text(code.trimmingCharacters(in: .newlines))
                    .font(DuduTheme.monoFont(size: 12))
                    .foregroundStyle(DuduTheme.duduText)
                    .textSelection(.enabled)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)
            }
        }
        .background(
            DuduTheme.color(.toolCard, scope: .chat),
            in: RoundedRectangle(cornerRadius: DuduTheme.radiusChip, style: .continuous)
        )
    }
}

// MARK: - Table

private struct DuduTableView: View {
    let alignments: [RawTableColumnAlignment]
    let rows: [RawTableRow]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, row in
                HStack(spacing: 0) {
                    ForEach(Array(row.cells.enumerated()), id: \.offset) { cellIndex, cell in
                        DuduInlineText(inlines: cell.content)
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: cellAlignment(cellIndex))
                            .background(rowIndex == 0 ? DuduTheme.duduIconChip : Color.clear)
                    }
                }
                if rowIndex < rows.count - 1 {
                    DuduTheme.duduDivider
                        .frame(maxWidth: .infinity)
                        .frame(height: 1)
                }
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: DuduTheme.radiusChip, style: .continuous)
                .stroke(DuduTheme.duduDivider, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: DuduTheme.radiusChip, style: .continuous))
    }

    private func cellAlignment(_ index: Int) -> Alignment {
        guard index < alignments.count else { return .leading }
        switch alignments[index] {
        case .left: return .leading
        case .center: return .center
        case .right: return .trailing
        case .none: return .leading
        }
    }
}
