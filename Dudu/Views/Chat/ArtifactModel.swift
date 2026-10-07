import Foundation

// MARK: - Artifact · 产物模型
//
// A self-contained renderable unit produced by the AI: an HTML page, an SVG
// graphic, a Markdown document, or a code snippet. Displayed in chat as a
// compact card; tapping it opens ArtifactPreviewView (a bottom sheet).
//
// Wiring (no fake tool involved): a future `/artifacts` tool — or any engine
// code that wants to surface an artifact — writes `envelopeString` into
// `AssistantBlock.content` (block kind stays `.text`). MessageBlockView
// detects the envelope with `Artifact(envelope:)` and renders
// ArtifactCardView instead of plain markdown. If the engine later gains a
// first-class artifact block kind, this envelope is the migration bridge:
// decode the envelope, move the Artifact over, done.
//
// The envelope marker is a first line no normal chat message ever starts
// with, so ordinary text can never be misdetected as an artifact.
struct Artifact: Identifiable, Codable, Equatable {
    var id: UUID
    var title: String
    var kind: ArtifactKind
    var content: String

    init(id: UUID = UUID(), title: String, kind: ArtifactKind, content: String) {
        self.id = id
        self.title = title
        self.kind = kind
        self.content = content
    }

    /// Sheet / card title; falls back to the kind label when empty.
    var displayTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? kind.label : title
    }
}

/// Artifact content kind. `html` and `svg` render in a WKWebView (a content
/// preview surface, not the app's UI framework — the app itself stays 100%
/// native Swift with no JS engine as its runtime); `markdown` reuses
/// DuduMarkdownView; `code` renders as selectable monospace text.
enum ArtifactKind: String, Codable, CaseIterable {
    case html
    case svg
    case markdown
    case code

    /// Human-readable kind label for the card and the sheet title area.
    var label: String {
        switch self {
        case .html: return "HTML"
        case .svg: return "SVG"
        case .markdown: return "Markdown"
        case .code: return "代码"
        }
    }

    /// SF Symbol glyph shown on the pink icon chip (定妆 row style).
    /// System symbols only — never emoji.
    var systemIcon: String {
        switch self {
        case .html: return "globe"
        case .svg: return "photo"
        case .markdown: return "doc.richtext"
        case .code: return "chevron.left.forwardslash.chevron.right"
        }
    }
}

// MARK: - Envelope transport

extension Artifact {
    /// Magic first line of the envelope. A normal message never starts here.
    static let envelopeMarker = "dudu-artifact:v1"

    /// The exact string a producer writes into `AssistantBlock.content`.
    /// First line is the marker, the rest is the JSON payload.
    var envelopeString: String {
        let payload: String
        if let data = try? JSONEncoder().encode(self),
           let json = String(data: data, encoding: .utf8) {
            payload = json
        } else {
            payload = "{}"
        }
        return Self.envelopeMarker + "\n" + payload
    }

    /// Parses an envelope back into an Artifact. Returns nil for ordinary
    /// text (the prefix check fails fast) or for malformed payloads.
    init?(envelope: String) {
        let prefix = Self.envelopeMarker + "\n"
        guard envelope.hasPrefix(prefix) else { return nil }
        let json = String(envelope.dropFirst(prefix.count))
        guard let data = json.data(using: .utf8),
              let artifact = try? JSONDecoder().decode(Artifact.self, from: data)
        else { return nil }
        self = artifact
    }
}
