import Foundation
import SwiftUI

// MARK: - IntimacyManager · 亲密度（轻游戏化，克制版）
//
// Faithful port of openmuse/apps/mobile/src/romance/intimacy.ts and
// milestones.ts (D20c).
//
// What this IS: a quiet, honest "phase" derived from real data only —
// days together. Nothing is fabricated: when there is no together-since
// date, there is no line.
//
// The restraint bar (from the romance manual, kept verbatim in behavior):
//   no streaks, no decay, no energy/currency, no punishment for missing days,
//   no manipulative pings, no leaderboard, no pay-to-win.
//   The milestone list is fixed and short on purpose: 7 / 30 / 100 / 365 days.
//   Each milestone celebrates once (persisted guard), never replays.
//
// OPEN QUESTION: the old app fired celebrations through its initiative
// engine (milestone-sweeper scheduling a 20:00 Shanghai message). This repo
// has no initiative engine yet, so there is no auto-scheduler — newly
// reached milestones surface in IntimacyView for her to acknowledge.
// When an initiative engine lands, wire IntimacyManager.sweep(now:) there.

/// Growth phase, quiet by design. Same thresholds as intimacy.ts.
enum IntimacyPhase: String, CaseIterable {
    case budding
    case warming
    case steady
    case deep

    var label: String {
        switch self {
        case .budding: return "萌芽期"
        case .warming: return "升温期"
        case .steady: return "稳定期"
        case .deep: return "深厚期"
        }
    }

    var line: String {
        switch self {
        case .budding: return "刚在一起不久，什么都新鲜"
        case .warming: return "越来越熟，开始有默契"
        case .steady: return "细水长流的踏实"
        case .deep: return "一年以上，是老夫老妻了"
        }
    }

    /// Same thresholds as intimacyPhase() in intimacy.ts.
    /// nil (unknown start date) → nil: no line rather than an invented one.
    static func phase(forDays days: Int?) -> IntimacyPhase? {
        guard let days, days >= 0 else { return nil }
        if days < 30 { return .budding }
        if days < 100 { return .warming }
        if days < 365 { return .steady }
        return .deep
    }
}

/// Persisted ledger: which milestones were celebrated or skipped.
/// Celebrated once each — restarts never replay (intimacy.ts guard).
private struct IntimacyLedger: Codable {
    var celebrated: [String]
    var skipped: [String]

    static let empty = IntimacyLedger(celebrated: [], skipped: [])
}

/// Honest, restrained affinity tracking. The relationship (not the persona)
/// owns this — it is global, not per-persona.
@MainActor
final class IntimacyManager: ObservableObject {

    static let shared = IntimacyManager()

    /// Fixed, short milestone list — days together. Deliberately not extendable.
    static let milestoneDays: [Int] = [7, 30, 100, 365]

    @Published var togetherSince: Date? {
        didSet { persistDate() }
    }
    /// Master toggle. Absent key = enabled (on unless she turns it off).
    @Published var celebrationsEnabled: Bool = true {
        didSet { persistEnabled() }
    }
    @Published private(set) var celebratedIDs: [String] = []
    @Published private(set) var skippedIDs: [String] = []

    private init() {
        if let ms = UserDefaults.standard.object(forKey: Self.dateKey) as? Double {
            togetherSince = Date(timeIntervalSince1970: ms / 1000)
        }
        if UserDefaults.standard.object(forKey: Self.enabledKey) != nil {
            celebrationsEnabled = UserDefaults.standard.string(forKey: Self.enabledKey) != "0"
        }
        let ledger = Self.readLedger()
        celebratedIDs = ledger.celebrated
        skippedIDs = ledger.skipped
    }

    // MARK: - Keys

    private static let dateKey = "dudu.romance.togetherSince.v1"
    private static let enabledKey = "dudu.romance.milestoneCelebrationsEnabled.v1"
    private static let ledgerKey = "dudu.romance.milestoneLedger.v1"

    private static func milestoneID(days: Int) -> String {
        "together-days-\(days)"
    }

    // MARK: - Derived, honest

    /// Days together, or nil when no together-since date is set.
    var daysTogether: Int? {
        guard let since = togetherSince else { return nil }
        let days = Calendar.current.dateComponents([.day], from: since, to: Date()).day ?? 0
        return max(0, days)
    }

    var phase: IntimacyPhase? {
        IntimacyPhase.phase(forDays: daysTogether)
    }

    /// Milestones reached but neither celebrated nor skipped.
    /// Pure detection, same rule as detectNewMilestones() in milestones.ts.
    func newlyReachedMilestones() -> [Int] {
        guard let days = daysTogether else { return [] }
        let done = Set(celebratedIDs + skippedIDs)
        return Self.milestoneDays.filter { d in
            days >= d && !done.contains(Self.milestoneID(days: d))
        }
    }

    /// State of one milestone for the UI.
    func state(of days: Int) -> MilestoneState {
        let id = Self.milestoneID(days: days)
        if celebratedIDs.contains(id) { return .celebrated }
        if skippedIDs.contains(id) { return .skipped }
        if let d = daysTogether, d >= days { return .reached }
        return .upcoming
    }

    enum MilestoneState {
        case upcoming
        case reached
        case celebrated
        case skipped
    }

    // MARK: - Her actions

    /// She sets (or clears) the together-since date.
    func setTogetherSince(_ date: Date?) {
        togetherSince = date
    }

    /// A reached milestone was celebrated — fire once, never again.
    func markCelebrated(days: Int) {
        let id = Self.milestoneID(days: days)
        guard !celebratedIDs.contains(id) else { return }
        celebratedIDs.append(id)
        persistLedger()
    }

    /// She cancels a pending celebration — it never comes back.
    func skipMilestone(days: Int) {
        let id = Self.milestoneID(days: days)
        if !skippedIDs.contains(id) && !celebratedIDs.contains(id) {
            skippedIDs.append(id)
            persistLedger()
        }
    }

    // MARK: - Persistence

    private func persistDate() {
        if let since = togetherSince {
            UserDefaults.standard.set(since.timeIntervalSince1970 * 1000, forKey: Self.dateKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.dateKey)
        }
    }

    private func persistEnabled() {
        UserDefaults.standard.set(celebrationsEnabled ? "1" : "0", forKey: Self.enabledKey)
    }

    nonisolated private static func readLedger() -> IntimacyLedger {
        guard let data = UserDefaults.standard.data(forKey: ledgerKey),
              let l = try? JSONDecoder().decode(IntimacyLedger.self, from: data) else {
            return .empty
        }
        return l
    }

    private func persistLedger() {
        let l = IntimacyLedger(celebrated: celebratedIDs, skipped: skippedIDs)
        if let data = try? JSONEncoder().encode(l) {
            UserDefaults.standard.set(data, forKey: Self.ledgerKey)
        }
    }

    // MARK: - Prompt injection (nonisolated, read-only)

    /// Quiet line for the system prompt. When there is no together-since
    /// date, returns "" — no line rather than an invented one.
    nonisolated static func promptSection() -> String {
        guard let ms = UserDefaults.standard.object(forKey: dateKey) as? Double else { return "" }
        let since = Date(timeIntervalSince1970: ms / 1000)
        let days = max(0, Calendar.current.dateComponents([.day], from: since, to: Date()).day ?? 0)
        guard let phase = IntimacyPhase.phase(forDays: days) else { return "" }
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return "Together since \(f.string(from: since)) — \(days) days together (\(phase.label))."
    }
}
