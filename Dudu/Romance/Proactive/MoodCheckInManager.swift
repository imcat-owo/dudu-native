//
//  D20a (2026-10-08): daily mood check-in （每日心情）.
//
//  Manual: openmuse/apps/mobile/src/manuals/moodcheck.ts
//
//  Once a day, at her hour (default 20:00 Shanghai — the hour can NEVER be
//  06:00–16:00), you gently ask how she is doing, through the normal
//  proactive path: shared daily cap, never retried.
//
//  Smart skip (automatic — don't fight it):
//  - her mood already recorded today -> no nudge
//  - she was active in the app recently -> no nudge (ask in chat instead)
//  - she ignored yesterday's check-in -> today stays quiet (one day, no nagging)
//
//  One entry per day — recording twice updates today's entry, never
//  duplicates. Entries land on her visible timeline (MoodTimelineView).
//
//  Copy rule: NEVER say 打卡 / check-in / 记录 / 问卷 / 量表 when asking.
//  One caring line, like a partner, never a form. Zero emoji.

import Foundation
import Combine

struct MoodEntry: Codable, Identifiable {
    var id: String { dateKey }
    var dateKey: String        // "yyyy-MM-dd" Shanghai
    var mood: String            // her own words, short
    var note: String = ""       // optional longer bit, her words
    var recordedAt: TimeInterval
    var source: String          // "checkin" | "chat"
}

struct MoodCheckInConfig: Codable {
    var enabled: Bool = true
    var hour: Int = 20          // Shanghai wall clock; never 6–16
}

/// Outcome of the foreground/background check-in evaluation.
struct MoodNudgeDecision {
    var fire: Bool
    var reason: String
}

@MainActor
final class MoodCheckInManager: ObservableObject {
    static let shared = MoodCheckInManager()

    private static let configKey = "moodcheck.config.v1"
    private static let entriesKey = "moodcheck.entries.v1"
    private static let nudgesKey = "moodcheck.nudges.v1"

    /// Within this window after her hour, the tick may fire (15-min grace,
    /// consistent with self-post slots).
    private static let graceSeconds: TimeInterval = 15 * 60
    /// "Recently active" threshold for the smart skip.
    private static let recentActivitySeconds: TimeInterval = 60 * 60

    private let logger = AppLogger(category: "MoodCheckIn")

    @Published private(set) var config: MoodCheckInConfig = MoodCheckInConfig()
    @Published private(set) var entries: [MoodEntry] = []

    /// dateKeys on which a check-in nudge was actually sent.
    private var nudgeDays: Set<String> = []

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.configKey),
           let decoded = try? JSONDecoder().decode(MoodCheckInConfig.self, from: data) {
            config = decoded
        }
        if let data = UserDefaults.standard.data(forKey: Self.entriesKey),
           let decoded = try? JSONDecoder().decode([MoodEntry].self, from: data) {
            entries = decoded
        }
        if let data = UserDefaults.standard.data(forKey: Self.nudgesKey),
           let decoded = try? JSONDecoder().decode([String].self, from: data) {
            nudgeDays = Set(decoded)
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(config) {
            UserDefaults.standard.set(data, forKey: Self.configKey)
        }
        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: Self.entriesKey)
        }
        if let data = try? JSONEncoder().encode(Array(nudgeDays)) {
            UserDefaults.standard.set(data, forKey: Self.nudgesKey)
        }
    }

    // MARK: config (only SHE changes these)

    /// Set her check-in hour. Refuses 06:00–16:00 (her sleep window) and
    /// returns false with an explanation for the UI/tool to surface.
    @discardableResult
    func setHour(_ hour: Int) -> Bool {
        guard hour >= 0 && hour < 24 else { return false }
        guard !(hour >= 6 && hour < 16) else {
            logger.info("[moodcheck] hour \(hour) refused: sleep window")
            return false
        }
        config.hour = hour
        persist()
        return true
    }

    func setEnabled(_ enabled: Bool) {
        config.enabled = enabled
        persist()
    }

    // MARK: entries — one per day, record twice updates

    /// Call EVERY time she tells you her mood: answering the check-in, or
    /// sharing unprompted in chat. dateKey defaults to today (Shanghai).
    func record(mood: String, note: String = "", source: String = "chat",
                dateKey: String? = nil, now: Date = Date()) -> MoodEntry {
        let key = dateKey ?? ProactiveClock.dateKey(of: now)
        let entry = MoodEntry(
            dateKey: key,
            mood: mood.trimmingCharacters(in: .whitespacesAndNewlines),
            note: note.trimmingCharacters(in: .whitespacesAndNewlines),
            recordedAt: now.timeIntervalSince1970,
            source: source
        )
        if let i = entries.firstIndex(where: { $0.dateKey == key }) {
            entries[i] = entry
            logger.info("[moodcheck] updated entry for \(key)")
        } else {
            entries.append(entry)
            logger.info("[moodcheck] recorded entry for \(key)")
        }
        persist()
        return entry
    }

    func entry(for dateKey: String) -> MoodEntry? {
        entries.first { $0.dateKey == dateKey }
    }

    func today(now: Date = Date()) -> MoodEntry? {
        entry(for: ProactiveClock.dateKey(of: now))
    }

    /// Her timeline, newest first.
    func timeline() -> [MoodEntry] {
        entries.sorted { $0.dateKey > $1.dateKey }
    }

    func delete(dateKey: String) {
        entries.removeAll { $0.dateKey == dateKey }
        persist()
    }

    // MARK: smart skip

    /// Should the check-in fire right now? Fail-closed: any doubt -> no.
    func shouldNudge(now: Date = Date()) -> MoodNudgeDecision {
        guard config.enabled else {
            return MoodNudgeDecision(fire: false, reason: "每日心情没开")
        }
        let key = ProactiveClock.dateKey(of: now)
        // Only at her hour, inside the grace window.
        guard let fireTime = ProactiveClock.date(hour: config.hour, on: key) else {
            return MoodNudgeDecision(fire: false, reason: "时间解析失败")
        }
        let elapsed = now.timeIntervalSince(fireTime)
        guard elapsed >= 0, elapsed <= Self.graceSeconds else {
            return MoodNudgeDecision(fire: false, reason: "不在她设定的时间附近")
        }
        // Smart skip 1: already recorded today — you already know.
        if today(now: now) != nil {
            return MoodNudgeDecision(fire: false, reason: "今天已经记过她的心情了，不打扰")
        }
        // Smart skip 2: she was active recently — ask in chat instead.
        if let last = ProactiveEngine.shared.lastUserActivity,
           now.timeIntervalSince(last) < Self.recentActivitySeconds {
            return MoodNudgeDecision(fire: false, reason: "她刚才还在线，聊天里问就好")
        }
        // Smart skip 3: she ignored yesterday's check-in — one quiet day.
        if let yesterday = ProactiveClock.addDays(now, -1) {
            let yKey = ProactiveClock.dateKey(of: yesterday)
            if nudgeDays.contains(yKey) && entry(for: yKey) == nil {
                return MoodNudgeDecision(fire: false, reason: "她昨天没回，今天安静一天")
            }
        }
        // Shared proactive gate last — cap, 60-min gap, sleep, incognito.
        switch ProactiveEngine.shared.gate(kind: "moodcheck", now: now) {
        case .allow:
            return MoodNudgeDecision(fire: true, reason: "可以问")
        case .veto(let reason):
            return MoodNudgeDecision(fire: false, reason: reason)
        }
    }

    /// HOOK: call when the check-in was actually asked/sent (foreground
    /// delivery or background notification scheduled). Feeds the
    /// "ignored yesterday" skip and the shared send ledger.
    func markNudged(now: Date = Date()) {
        nudgeDays.insert(ProactiveClock.dateKey(of: now))
        persist()
        ProactiveEngine.shared.recordSend(kind: "moodcheck", now: now)
    }
}
