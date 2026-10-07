import SwiftUI
import UIKit
import WebKit

// MARK: - ArtifactCardView
//
// Compact chat card for an artifact block: pink icon chip + title + kind
// caption, Q萌圆润 per the 定妆 (small, card radius 16, theme colors only).
// Tapping opens the preview sheet. The card is only ever constructed from a
// successfully parsed Artifact — no artifact, no card, no dead UI.
struct ArtifactCardView: View {
    let artifact: Artifact
    @State private var showPreview = false

    var body: some View {
        Button {
            showPreview = true
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: DuduTheme.radiusChip, style: .continuous)
                        .fill(DuduTheme.duduIconChip)
                        .frame(width: 36, height: 36)
                    Image(systemName: artifact.kind.systemIcon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(DuduTheme.pink)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(artifact.displayTitle)
                        .font(DuduTheme.bodyFont(weight: .semibold))
                        .foregroundStyle(DuduTheme.duduText)
                        .lineLimit(1)
                    Text("\(artifact.kind.label) · 点击预览")
                        .font(DuduTheme.captionFont())
                        .foregroundStyle(DuduTheme.duduTextDim)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(DuduTheme.captionFont(weight: .semibold))
                    .foregroundStyle(DuduTheme.duduTextDim)
            }
            .padding(10)
        }
        .buttonStyle(.plain)
        .background(
            DuduTheme.duduIconChip.opacity(0.45),
            in: RoundedRectangle(cornerRadius: DuduTheme.radiusCard, style: .continuous)
        )
        .accessibilityLabel("预览\(artifact.kind.label)：\(artifact.displayTitle)")
        .accessibilityHint("打开预览窗口")
        .sheet(isPresented: $showPreview) {
            ArtifactPreviewView(artifact: artifact)
        }
    }
}

// MARK: - ArtifactPreviewView
//
// Bottom-sheet preview window. Renders the real artifact content: HTML/SVG in
// a WKWebView, Markdown via DuduMarkdownView, code as selectable monospace
// text. The copy button copies the real content; empty content shows an
// honest empty state instead of a placeholder.
struct ArtifactPreviewView: View {
    let artifact: Artifact
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    /// True when there is no meaningful content to render or copy.
    private var isContentEmpty: Bool {
        artifact.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Group {
                if isContentEmpty {
                    emptyState
                } else {
                    switch artifact.kind {
                    case .html:
                        ArtifactWebView(html: artifact.content)
                    case .svg:
                        ArtifactWebView(html: Self.svgDocument(artifact.content))
                    case .markdown:
                        ScrollView {
                            DuduMarkdownView(markdown: artifact.content)
                                .padding(.horizontal, DuduTheme.pagePadding)
                                .padding(.vertical, 12)
                        }
                    case .code:
                        ScrollView([.vertical, .horizontal]) {
                            Text(artifact.content)
                                .font(DuduTheme.monoFont(size: 12))
                                .foregroundStyle(DuduTheme.duduText)
                                .textSelection(.enabled)
                                .padding(12)
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        }
                        .background(
                            DuduTheme.duduIconChip.opacity(0.35),
                            in: RoundedRectangle(cornerRadius: DuduTheme.radiusCard, style: .continuous)
                        )
                        .padding(DuduTheme.pagePadding)
                    }
                }
            }
            .navigationTitle(artifact.displayTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        copyContent()
                    } label: {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    }
                    .accessibilityLabel("复制内容")
                    .disabled(isContentEmpty)
                }
            }
        }
        .presentationDragIndicator(.visible)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: artifact.kind.systemIcon)
                .font(.system(size: 28, weight: .regular))
                .foregroundStyle(DuduTheme.pink)
            Text("这里还没有内容")
                .font(DuduTheme.bodyFont())
                .foregroundStyle(DuduTheme.duduTextDim)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Actions

    private func copyContent() {
        UIPasteboard.general.string = artifact.content
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            copied = false
        }
    }

    /// Wraps raw SVG in a minimal HTML document so it renders centered and
    /// scales to the sheet width. No background color is set anywhere: the
    /// web view is transparent and the sheet's own theme background shows
    /// through, so dark mode stays honest.
    private static func svgDocument(_ svg: String) -> String {
        """
        <!DOCTYPE html>
        <html>
        <head><meta name="viewport" content="width=device-width,initial-scale=1"></head>
        <body style="margin:0;padding:24px;display:flex;justify-content:center;align-items:center;min-height:100vh;box-sizing:border-box;">
        \(svg)
        <style>svg{max-width:100%;height:auto;}</style>
        </body>
        </html>
        """
    }
}

// MARK: - ArtifactWebView
//
// Thin WKWebView wrapper for artifact HTML/SVG. This is a content preview
// surface (like LobeChat's artifact preview) — not the app's UI framework,
// which stays 100% native Swift with no JS engine as its runtime.
struct ArtifactWebView: UIViewRepresentable {
    let html: String

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        // Load exactly once per web view lifetime: reloading on every
        // SwiftUI update would reset scroll position and re-run scripts.
        guard !context.coordinator.didLoad else { return }
        context.coordinator.didLoad = true
        webView.loadHTMLString(html, baseURL: nil)
    }

    final class Coordinator {
        var didLoad = false
    }
}
