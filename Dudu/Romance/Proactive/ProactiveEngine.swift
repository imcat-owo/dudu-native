//
//  D20a (2026-10-08): proactive engine — AI self-posts + next-day follow-up
//  + daily mood check-in share one gate, one clock, one cap.
//
//  Source manuals (read before coding, no impressions):
//    openmuse/apps/mobile/src/manuals/selfpost.ts   — 自发帖
//    openmuse/apps/mobile/src/manuals/moodcheck.ts  — 每日心情
//    openmuse/apps/mobile/src/manuals/initiative.ts — 主动约定 (+次日跟进)
//    openmuse/apps/mobile/src/manuals/outreach.ts   — 主动触达
//
//  This file is the shared core. Feature managers live in sibling files:
//  SelfPostManager, FollowUpManager, MoodCheckInManager,
//  ProactiveNotificationScheduler, ProactiveTools, ProactiveViews.
//
//  Fail-closed: any gate veto -> silent skip + logged reason. Never a ping
//  out of nowhere. Never in her sleep window. Never in incognito.

import Foundation
import Combine

// MARK: - Shanghai wall clock

/// HER clock — always Asia/Shanghai, regardless of the device timezone.
enum ProactiveClock {
    static let shanghai: TimeZone =
        TimeZone(identifier: "Asia/Shanghai") ?? TimeZone.current

    static func hour(of date: Date = Date()) -> Int {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = shanghai
        return cal.component(.hour, from: date)
    }

    static func dateKey(of date: Date = Date()) -> String {
        let f = DateFormatter()
        f.timeZone = shanghai
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    static func hourMinute(of date: Date) -> String {
        let f = DateFormatter()
        f.timeZone = shanghai
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }

    /// Her sleep window: 06:00–16:00 Shanghai (she is nocturnal, sleeps days).
    /// No proactive send is ever scheduled or fired inside it.
    static func isSleepWindow(_ date: Date = Date()) -> Bool {
        let h = hour(of: date)
        return h >= 6 && h < 16
    }

    /// Date for hour h on the given "yyyy-MM-dd" key, in Shanghai.
    static func date(hour h: Int, on dateKey: String) -> Date? {
        let f = DateFormatter()
        f.timeZone = shanghai
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        guard let day = f.date(from: dateKey) else { return nil }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = shanghai
        return cal.date(bySettingHour: h, minute: 0, second: 0, of: day)
    }

    static func addDays(_ date: Date, _ days: Int) -> Date? {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = shanghai
        return cal.date(byAdding: .day, value: days, to: date)
    }
}

// MARK: - Gate outcome

/// Ordered deterministic gate, evaluated BEFORE any model call.
/// Fail-closed: a veto is silent (no UI, no ping) and logged with its reason.
enum ProactiveGateOutcome {
    case allow
    case veto(reason: String)
}

struct ProactiveSendRecord: Codable {
    var at: TimeInterval
    var kind: String   // "selfpost" | "followup" | "moodcheck"
}

extension Notification.Name {
    /// Posted (main thread) when the foreground tick finds due proactive
    /// actions. userInfo["actions"]: [[String: String]] with kind + payload.
    /// The chat engine observes this and surfaces ONE quiet line in the AI's
    /// context — never a system announcement, never a ping.
    static let proactiveDueActions = Notification.Name("dudu.proactive.dueActions")
}

// MARK: - Engine

/// Shared proactive infrastructure: caps, slots, quiet hours, sleep window,
/// send ledger, incognito flag, foreground/background hooks.
///
/// - Note: DuduTheme is @MainActor. This class is @MainActor too, but it
///   never touches colors — only SwiftUI views do, and only inside bodies.
@MainActor
final class ProactiveEngine: ObservableObject {
    static let shared = ProactiveEngine()

    // MARK: persisted state keys
    private static let sendsKey = "proactive.sends.v1"
    private static let capKey = "proactive.sharedDailyCap.v1"
    private static let lastActivityKey = "proactive.lastActivity.v1"

    private let logger = AppLogger(category: "ProactiveEngine")

    /// Set by the chat engine when incognito toggles. While true, every
    /// proactive gate vetoes and every write tool refuses.
    @Published var incognito: Bool = false

    private var sends: [ProactiveSendRecord] = []

    /// Shared per-persona daily cap (selfpost + followup + moodcheck share it).
    /// Default 3. Only SHE changes this (Our Space -> settings section).
    var sharedDailyCap: Int {
        get {
            let v = UserDefaults.standard.integer(forKey: Self.capKey)
            return v == 0 ? 3 : v
        }
        set {
            UserDefaults.standard.set(max(0, newValue), forKey: Self.capKey)
        }
    }

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.sendsKey),
           let decoded = try? JSONDecoder().decode([ProactiveSendRecord].self, from: data) {
            sends = decoded
        }
    }

    private func persistSends() {
        if let data = try? JSONEncoder().encode(sends) {
            UserDefaults.standard.set(data, forKey: Self.sendsKey)
        }
    }

    // MARK: ledger

    func sendsToday(now: Date = Date()) -> [ProactiveSendRecord] {
        let key = ProactiveClock.dateKey(of: now)
        return sends.filter { ProactiveClock.dateKey(of: Date(timeIntervalSince1970: $0.at)) == key }
    }

    private var lastSendDate: Date? {
        sends.map { Date(timeIntervalSince1970: $0.at) }.max()
    }

    /// Record a proactive send. Call exactly once per actual send.
    func recordSend(kind: String, now: Date = Date()) {
        sends.append(ProactiveSendRecord(at: now.timeIntervalSince1970, kind: kind))
        // Prune entries older than 48h — the ledger only answers "today"
        // and "last 60 minutes" questions.
        let cutoff = now.addingTimeInterval(-48 * 3600).timeIntervalSince1970
        sends.removeAll { $0.at < cutoff }
        persistSends()
    }

    // MARK: the ordered gate

    /// Deterministic gate, in order. Vetoes are silent + logged.
    func gate(kind: String, now: Date = Date()) -> ProactiveGateOutcome {
        if incognito {
            return veto(kind: kind, reason: "incognito 模式：不做任何主动打扰")
        }
        if ProactiveClock.isSleepWindow(now) {
            return veto(kind: kind, reason: "她在睡觉（06:00–16:00 上海时间），不打扰")
        }
        if sendsToday(now: now).count >= sharedDailyCap {
            return veto(kind: kind, reason: "今日主动次数已达上限（\(sharedDailyCap) 次）")
        }
        if let last = lastSendDate, now.timeIntervalSince(last) < 3600 {
            return veto(kind: kind, reason: "距上次主动发送不足 60 分钟")
        }
        return .allow
    }

    private func veto(kind: String, reason: String) -> ProactiveGateOutcome {
        logger.info("[gate] \(kind) vetoed: \(reason)")
        return .veto(reason: reason)
    }

    // MARK: user activity

    /// Call when she sends a message or opens the app. Drives the moodcheck
    /// smart skip ("she was active recently -> no nudge") and the 60-minute
    /// collision rule's recency sense.
    func recordUserActivity(now: Date = Date()) {
        UserDefaults.standard.set(now.timeIntervalSince1970, forKey: Self.lastActivityKey)
    }

    var lastUserActivity: Date? {
        let t = UserDefaults.standard.double(forKey: Self.lastActivityKey)
        return t > 0 ? Date(timeIntervalSince1970: t) : nil
    }

    // MARK: foreground / background hooks

    /// HOOK: call on app foreground (scenePhase .active).
    /// Cancels stale proactive notifications, records activity, runs the
    /// foreground tick (15-minute grace for slots — expired slots are
    /// consumed silently, never delivered, never backfilled).
    func appDidBecomeActive() {
        recordUserActivity()
        ProactiveNotificationScheduler.shared.cancelAll()
        Task { await evaluateForeground() }
    }

    /// HOOK: call when the app resigns active (backgrounding).
    /// Evaluates triggers once, at background time, and schedules AT MOST
    /// ONE local notification (template copy — iOS cannot wake the AI to
    /// compose while suspended). Self-post is excluded by her rule: no
    /// notification ping for it, she finds posts when she opens Our Space.
    func appWillResignActive() {
        Task { await evaluateBackground() }
    }

    // MARK: evaluation

    private func evaluateForeground() async {
        var actions: [[String: String]] = []
        if let slot = SelfPostManager.shared.evaluateDue() {
            actions.append(["kind": "selfpost", "slot": "\(slot)"])
        }
        for item in FollowUpManager.shared.attemptDueFires() {
            actions.append(["kind": "followup", "id": item.id, "text": item.text])
        }
        if MoodCheckInManager.shared.shouldNudge().fire {
            actions.append(["kind": "moodcheck"])
        }
        guard !actions.isEmpty else { return }
        logger.info("[tick] foreground due: \(actions.map { $0["kind"] ?? "?" }.joined(separator: ","))")
        NotificationCenter.default.post(
            name: .proactiveDueActions,
            object: nil,
            userInfo: ["actions": actions]
        )
    }

    private func evaluateBackground() async {
        let now = Date()
        // Never schedule while she sleeps — unless nothing is due anyway.
        guard !ProactiveClock.isSleepWindow(now) else { return }
        // Priority: follow-up first, then mood check-in. Self-post never
        // schedules a notification (her rule).
        if let item = FollowUpManager.shared.peekBackgroundDue() {
            FollowUpManager.shared.consume(item.id)
            // The shared gate applies on the background path too: incognito,
            // sleep window, daily cap, 60-min collision. Veto = silent.
            switch ProactiveEngine.shared.gate(kind: "followup", now: now) {
            case .allow:
                ProactiveEngine.shared.recordSend(kind: "followup", now: now)
                await ProactiveNotificationScheduler.shared.scheduleAtMostOne(
                    id: "followup-\(item.id)",
                    title: "嘟嘟记着一件事",
                    body: "\(item.text)，后来怎么样了？",
                    afterSeconds: 2 * 3600,
                    userInfo: ["kind": "followup", "id": item.id]
                )
            case .veto(let reason):
                logger.info("[followup] background vetoed (consumed): \(reason)")
            }
            return
        }
        let mood = MoodCheckInManager.shared.shouldNudge()
        if mood.fire {
            MoodCheckInManager.shared.markNudged()
            await ProactiveNotificationScheduler.shared.scheduleAtMostOne(
                id: "moodcheck-\(ProactiveClock.dateKey())",
                title: "想你了",
                body: "忙完了吗？想问问你今天过得怎么样。",
                afterSeconds: 2 * 3600,
                userInfo: ["kind": "moodcheck"]
            )
        }
    }
}
