import Foundation
import SwiftUI

// MARK: - PersonaDialsStore · 人格维度滑杆
//
// Ported from openmuse/apps/mobile/src/manuals/dials.ts (D20c).
// Five dials, 0–100 each, per persona:
//   粘人度 (clingy) · 活泼度 (playful) · 浪漫度 (romantic) ·
//   主动度 (proactive) · 幽默度 (humor)
//
// IRON RULE: only SHE moves the dials. She drags them in this UI; changes
// apply immediately (persisted on every change, published live — no restart).
// There is NO tool for the AI to set them — deliberately. No such tool is
// created anywhere in this file.
//
// PRECEDENCE: dials are her explicit settings; evolution notes are the AI's
// guesses. On conflict, the DIAL wins — the prompt section below says so.

/// The five dial dimensions. Faithful port of dials.ts.
enum PersonaDial: String, CaseIterable, Codable {
    case clingy
    case playful
    case romantic
    case proactive
    case humor

    var title: String {
        switch self {
        case .clingy: return "粘人度"
        case .playful: return "活泼度"
        case .romantic: return "浪漫度"
        case .proactive: return "主动度"
        case .humor: return "幽默度"
        }
    }

    var systemImage: String {
        switch self {
        case .clingy: return "heart.fill"
        case .playful: return "hare.fill"
        case .romantic: return "moon.stars.fill"
        case .proactive: return "paperplane.fill"
        case .humor: return "face.smiling.fill"
        }
    }

    /// What the number means, in her words — helps her decide where to drag.
    var hint: String {
        switch self {
        case .clingy: return "低一点他更独立，高一点他更爱黏着你"
        case .playful: return "低一点他更沉稳，高一点他更爱玩闹"
        case .romantic: return "低一点他更实在，高一点他更会制造小浪漫"
        case .proactive: return "低一点他多等你开口，高一点他更主动找话题"
        case .humor: return "低一点他更正经，高一点他更爱抖机灵"
        }
    }
}

/// Per-persona dial values. UI layer uses the shared @MainActor singleton;
/// prompt assembly uses the nonisolated static promptSection(for:) helper.
@MainActor
final class PersonaDialsStore: ObservableObject {

    static let shared = PersonaDialsStore()

    /// Neutral midpoint. The original dials.ts sets no defaults; 50 keeps
    /// every dimension balanced until she drags one.
    static let defaultValue: Double = 50

    @Published private(set) var values: [PersonaDial: Double] = [:]
    @Published private(set) var personaID: String = PersonaStore.defaultPersonaID

    private init() {}

    // MARK: - Open / persist

    func open(personaID: String) {
        guard personaID != self.personaID else { return }
        self.personaID = personaID
        reload()
    }

    func reload() {
        values = Self.readValues(for: personaID)
    }

    // MARK: - Her controls (UI only — no AI tool writes these)

    func value(for dial: PersonaDial) -> Double {
        values[dial] ?? Self.defaultValue
    }

    /// She drags; it takes effect immediately. Clamped to 0–100.
    func setDial(_ dial: PersonaDial, value: Double) {
        let clamped = min(100, max(0, value))
        values[dial] = clamped
        persist()
    }

    /// Back to the neutral midpoint on all five dials.
    func resetAll() {
        values = [:]
        persist()
        NotificationCenter.default.post(name: .personaDidChange, object: nil)
    }

    // MARK: - Disk (UserDefaults; small, fast, immediate)

    nonisolated private static func key(for personaID: String) -> String {
        "dudu.personaDials.\(personaID).v1"
    }

    nonisolated static func readValues(for personaID: String) -> [PersonaDial: Double] {
        let raw = UserDefaults.standard.dictionary(forKey: key(for: personaID)) as? [String: Double] ?? [:]
        var out: [PersonaDial: Double] = [:]
        for d in PersonaDial.allCases {
            out[d] = raw[d.rawValue] ?? defaultValue
        }
        return out
    }

    nonisolated private static func writeValues(_ values: [PersonaDial: Double], for personaID: String) {
        var raw: [String: Double] = [:]
        for (d, v) in values { raw[d.rawValue] = v }
        UserDefaults.standard.set(raw, forKey: key(for: personaID))
    }

    private func persist() {
        Self.writeValues(values, for: personaID)
        NotificationCenter.default.post(name: .personaDidChange, object: nil)
    }

    // MARK: - Prompt injection (nonisolated)

    /// Compact section for the system prompt. Always present (dials are
    /// explicit settings, not guesses) — the IRON RULE and the precedence
    /// rule ride along so the model can never misread them.
    nonisolated static func promptSection(for personaID: String) -> String {
        let v = readValues(for: personaID)
        func n(_ d: PersonaDial) -> String {
            String(Int((v[d] ?? defaultValue).rounded()))
        }
        return """
            Personality dials （人格维度） — set ONLY by her, in the persona settings UI. \
            You have NO tool to change them; you may only suggest in chat, and a suggestion \
            never takes effect by itself. These are her explicit settings; evolution notes \
            are your guesses — on conflict, the DIAL wins.
            粘人度(clingy): \(n(.clingy))/100 · 活泼度(playful): \(n(.playful))/100 · \
            浪漫度(romantic): \(n(.romantic))/100 · 主动度(proactive): \(n(.proactive))/100 · \
            幽默度(humor): \(n(.humor))/100
            """
    }
}
