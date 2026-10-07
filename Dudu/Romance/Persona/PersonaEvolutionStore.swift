import Foundation
import SwiftUI

// MARK: - PersonaEvolutionStore · 性格进化（成长记录）
//
// Ported from openmuse/apps/mobile/src/manuals/evolution.ts (D20c).
// The rules are the original's, unchanged:
//   - ONE pattern per note, one crisp sentence, ≤200 characters.
//   - At most ONE new note per calendar day, only when something genuinely new emerged.
//   - source is REQUIRED: sourceKind ("chat" or "manual"), sourceDateMs, and sourceRef.
//     No source, no note. Never claim a false memory.
//   - She owns every note: read/edit/delete happen in the UI below (Our Space).
//   - evolution notes ride the system prompt via promptSection(for:) — read at
//     prompt-build time, so the AI behaves differently from the next turn.
//   - Disabled toggle: no new notes, nothing extra in the prompt; the list stays readable.
//
// SAFETY LINE (from the original, non-negotiable): evolution adapts the AI to
// her — tone, pacing, what delights her. It never steers her emotions, creates
// dependency, or keeps her hooked.

/// Where the pattern was observed. "manual" = she wrote it down herself.
enum EvolutionSourceKind: String, Codable, CaseIterable {
    case chat
    case manual

    var label: String {
        switch self {
        case .chat: return "聊天"
        case .manual: return "她记的"
        }
    }
}

/// One observed pattern. Add-only history: notes are never silently overwritten.
struct EvolutionNote: Codable, Identifiable, Equatable {
    var id: String
    /// The pattern, one crisp sentence, ≤200 chars.
    var text: String
    var sourceKind: EvolutionSourceKind
    /// When the source was observed (ms since epoch).
    var sourceDateMs: Int64
    /// Which conversation / where (dialog name, date). Never empty.
    var sourceRef: String
    var createdAt: Date
}

/// Envelope on disk: notes + the enabled toggle, per persona.
struct EvolutionEnvelope: Codable {
    var enabled: Bool
    var notes: [EvolutionNote]

    static let empty = EvolutionEnvelope(enabled: true, notes: [])
}

enum EvolutionStoreError: Error, LocalizedError {
    case emptyText
    case tooLong(max: Int)
    case missingSource
    case onePerDay

    var errorDescription: String? {
        switch self {
        case .emptyText: return "先写一句话，再记下来。"
        case .tooLong(let max): return "一句话就好，最多\(max)个字。"
        case .missingSource: return "来源必填：在哪看到的、哪天的、哪次对话。"
        case .onePerDay: return "今天已经记过一条了，新的感悟明天再记。"
        }
    }
}

/// Per-persona evolution notes. UI layer uses the shared @MainActor singleton;
/// prompt assembly uses the nonisolated static promptSection(for:) helper,
/// which reads the envelope file directly (never touches @MainActor state).
@MainActor
final class PersonaEvolutionStore: ObservableObject {

    static let shared = PersonaEvolutionStore()

    static let maxNoteChars = 200

    @Published private(set) var notes: [EvolutionNote] = []
    @Published private(set) var isEnabled = true
    @Published private(set) var personaID: String = PersonaStore.defaultPersonaID

    private init() {}

    // MARK: - Open / persist

    /// Switch to another persona's note list. Called by the view on appear.
    func open(personaID: String) {
        guard personaID != self.personaID else { return }
        self.personaID = personaID
        reload()
    }

    /// Reload from disk for the current persona.
    func reload() {
        let env = Self.readEnvelope(for: personaID)
        self.notes = env.notes.sorted { $0.createdAt > $1.createdAt }
        self.isEnabled = env.enabled
    }

    private func persist() {
        let env = EvolutionEnvelope(enabled: isEnabled, notes: notes)
        Self.writeEnvelope(env, for: personaID)
    }

    // MARK: - Disk

    private static func envelopeURL(for personaID: String) -> URL {
        DuduPaths.duduConfigRoot
            .appendingPathComponent("evolution", isDirectory: true)
            .appendingPathComponent("evolution_\(personaID).json")
    }

    nonisolated static func readEnvelope(for personaID: String) -> EvolutionEnvelope {
        let url = envelopeURL(for: personaID)
        guard let data = try? Data(contentsOf: url),
              let env = try? JSONDecoder().decode(EvolutionEnvelope.self, from: data) else {
            return .empty
        }
        return env
    }

    nonisolated private static func writeEnvelope(_ env: EvolutionEnvelope, for personaID: String) {
        let url = envelopeURL(for: personaID)
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(env) {
            try? data.write(to: url, options: .atomic)
        }
    }

    // MARK: - Rules

    /// True when a new note may be added right now (max 1 per calendar day).
    var canAddToday: Bool {
        let today = Calendar.current.startOfDay(for: Date())
        return !notes.contains { Calendar.current.startOfDay(for: $0.createdAt) == today }
    }

    /// Add a note. Throws when the rules are violated: empty/too-long text,
    /// missing source, or the one-per-day cap.
    func addNote(text: String,
                 sourceKind: EvolutionSourceKind,
                 sourceDate: Date,
                 sourceRef: String) throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw EvolutionStoreError.emptyText }
        guard trimmed.count <= Self.maxNoteChars else {
            throw EvolutionStoreError.tooLong(max: Self.maxNoteChars)
        }
        let ref = sourceRef.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !ref.isEmpty else { throw EvolutionStoreError.missingSource }
        guard canAddToday else { throw EvolutionStoreError.onePerDay }

        let note = EvolutionNote(
            id: UUID().uuidString,
            text: trimmed,
            sourceKind: sourceKind,
            sourceDateMs: Int64(sourceDate.timeIntervalSince1970 * 1000),
            sourceRef: ref,
            createdAt: Date())
        notes.insert(note, at: 0)
        persist()
    }

    /// Edit a note she owns. Keeps the source honest: the source fields are
    /// preserved (or corrected by her explicitly), never silently dropped.
    func editNote(id: String,
                  text: String,
                  sourceKind: EvolutionSourceKind,
                  sourceDate: Date,
                  sourceRef: String) throws {
        guard let idx = notes.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw EvolutionStoreError.emptyText }
        guard trimmed.count <= Self.maxNoteChars else {
            throw EvolutionStoreError.tooLong(max: Self.maxNoteChars)
        }
        let ref = sourceRef.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !ref.isEmpty else { throw EvolutionStoreError.missingSource }
        notes[idx].text = trimmed
        notes[idx].sourceKind = sourceKind
        notes[idx].sourceDateMs = Int64(sourceDate.timeIntervalSince1970 * 1000)
        notes[idx].sourceRef = ref
        persist()
    }

    /// Delete a note. Only at her explicit request (the UI confirms).
    func deleteNote(id: String) {
        notes.removeAll { $0.id == id }
        persist()
    }

    /// Master toggle (evolution_set_enabled). Off = no new notes, nothing in
    /// the prompt; the list stays readable.
    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        persist()
    }

    // MARK: - Prompt injection (nonisolated)

    /// Compact section for the system prompt. Empty when disabled or when
    /// there are no notes. Newest first. Reads the envelope file directly so
    /// prompt assembly never touches @MainActor state.
    ///
    /// The section carries the precedence rule itself: dials beat notes.
    nonisolated static func promptSection(for personaID: String) -> String {
        let env = readEnvelope(for: personaID)
        guard env.enabled, !env.notes.isEmpty else { return "" }
        var lines: [String] = [
            "Personality evolution notes （性格进化记录） — patterns you observed across days, not single events:",
        ]
        for n in env.notes.sorted(by: { $0.createdAt > $1.createdAt }) {
            let src: String = n.sourceKind == .chat ? "聊天" : "她记的"
            lines.append("- \(n.text)（来源：\(src)，\(n.sourceRef)）")
        }
        lines.append("These are your guesses; her persona dials are her explicit settings — on conflict, the dial wins.")
        return lines.joined(separator: "\n")
    }
}
