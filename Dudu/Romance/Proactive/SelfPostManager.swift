//
//  D20a (2026-10-08): AI self-post manager （自发帖）.
//
//  Manual: openmuse/apps/mobile/src/manuals/selfpost.ts
//
//  A few quiet slots each day (default 3, on HER clock — never while she
//  sleeps). At each slot the deterministic gate runs FIRST; only on pass
//  does the model get asked once: post or SKIP. Skip is silent and logged.
//
//  Hard constraints (never soften):
//  - Default 1 post/day, 3 slots. Only SHE changes config (settings UI or
//    the selfpost_config tool WITH her explicit confirmation).
//  - The AI NEVER enables it, raises the cap, or adds slots unprompted.
//  - Fired slots never refire. Expired slots are consumed silently.
//  - Never in incognito. Write tools refuse there.
//  - No notification ping for self-posts — she finds them in Our Space.

import Foundation
import Combine

// MARK: - Config

struct SelfPostConfig: Codable {
    /// Master toggle. Default OFF: the AI never enables it unprompted —
    /// she turns it on explicitly.
    var enabled: Bool = false
    /// Quiet slot hours (Shanghai), 1–5 entries. Default [17, 20, 23].
    var slotHours: [Int] = [17, 20, 23]
    /// Posts per day, 0–3. Default 1. (0 = enabled but no posting.)
    var dailyCap: Int = 1
}

// MARK: - Decision log ("AI 今天想发没发")

struct SelfPostDecision: Codable, Identifiable {
    var id: String = UUID().uuidString
    var at: TimeInterval
    var kind: String   // "post" | "skip" | "veto" | "config" | "expired"
    var text: String
}

// MARK: - Feed sink

/// Honest boundary: this feature does not own the feed pipeline.
/// The coordinator wires the real Our Space feed writer here; until then,
/// SelfPostManager refuses to pretend a post was published.
protocol SelfPostFeedSink {
    func publishSelfPost(text: String) async throws
}

struct SelfPostGapError: Error, LocalizedError {
    var errorDescription: String? {
        "Our Space 动态流还没接进来：selfpost_publish 拒绝假装发布。让 coordinator 把 SelfPostManager.shared.feedSink 接到真正的 feed_post 管道再发。"
    }
}

/// Default sink: refuses. The post is NOT faked — the failure is loud.
struct RefusingSelfPostSink: SelfPostFeedSink {
    func publishSelfPost(text: String) async throws {
        throw SelfPostGapError()
    }
}

// MARK: - Manager

@MainActor
final class SelfPostManager: ObservableObject {
    static let shared = SelfPostManager()

    private static let configKey = "selfpost.config.v1"
    private static let firedKey = "selfpost.fired.v1"
    private static let decisionsKey = "selfpost.decisions.v1"
    private static let postsKey = "selfpost.posts.v1"

    private let logger = AppLogger(category: "SelfPost")

    /// Set by the coordinator to the real Our Space feed pipeline.
    /// Default refuses — never fake a publish.
    var feedSink: any SelfPostFeedSink = RefusingSelfPostSink()

    @Published private(set) var config: SelfPostConfig = SelfPostConfig()
    @Published private(set) var decisions: [SelfPostDecision] = []

    /// Fired slot keys "yyyy-MM-dd-HH" — fired slots never refire.
    private var firedSlots: Set<String> = []
    /// "yyyy-MM-dd" -> posts published today.
    private var postsToday: [String: Int] = [:]

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.configKey),
           let decoded = try? JSONDecoder().decode(SelfPostConfig.self, from: data) {
            config = decoded
        }
        if let data = UserDefaults.standard.data(forKey: Self.firedKey),
           let decoded = try? JSONDecoder().decode([String].self, from: data) {
            firedSlots = Set(decoded)
        }
        if let data = UserDefaults.standard.data(forKey: Self.decisionsKey),
           let decoded = try? JSONDecoder().decode([SelfPostDecision].self, from: data) {
            decisions = decoded
        }
        if let data = UserDefaults.standard.data(forKey: Self.postsKey),
           let decoded = try? JSONDecoder().decode([String: Int].self, from: data) {
            postsToday = decoded
        }
    }

    private func persistAll() {
        if let data = try? JSONEncoder().encode(config) {
            UserDefaults.standard.set(data, forKey: Self.configKey)
        }
        if let data = try? JSONEncoder().encode(Array(firedSlots)) {
            UserDefaults.standard.set(data, forKey: Self.firedKey)
        }
        if let data = try? JSONEncoder().encode(decisions) {
            UserDefaults.standard.set(data, forKey: Self.decisionsKey)
        }
        if let data = try? JSONEncoder().encode(postsToday) {
            UserDefaults.standard.set(data, forKey: Self.postsKey)
        }
    }

    // MARK: config (only SHE changes these)

    /// Called from the settings UI (her hand) or the selfpost_config tool
    /// (with her explicit confirmation — enforced in the tool handler).
    func updateConfig(_ update: (inout SelfPostConfig) -> Void, byHer: Bool) {
        guard byHer else {
            logDecision(kind: "config", text: "拒绝：AI 不能擅自改自发帖配置")
            return
        }
        update(&config)
        // Normalize: 1–5 slots, hours 0–23 sorted, cap clamped 0–3.
        config.slotHours = Array(Set(config.slotHours.filter { $0 >= 0 && $0 < 24 })
            .sorted().prefix(5))
        config.dailyCap = min(3, max(0, config.dailyCap))
        persistAll()
        logDecision(kind: "config",
                    text: "配置已更新：开关\(config.enabled ? "开" : "关")，" +
                          "时段 \(config.slotHours.map(String.init).joined(separator: ","))，" +
                          "每日上限 \(config.dailyCap)")
    }

    /// Validate a proposed config WITHOUT applying it. Returns an error
    /// string, or nil when valid.
    func validate(slots: [Int]?, dailyCap: Int?) -> String? {
        if let slots {
            if slots.isEmpty || slots.count > 5 {
                return "时段数量只能是 1 到 5 个"
            }
            for h in slots where h < 0 || h > 23 {
                return "时段小时数必须在 0 到 23 之间"
            }
            let sleepy = slots.filter { $0 >= 6 && $0 < 16 }
            if !sleepy.isEmpty {
                return "她 06:00–16:00 在睡觉，自发帖时段不能落在里面（\(sleepy.map(String.init).joined(separator: ",")) 点不行）。换个晚上的时间吧。"
            }
        }
        if let cap = dailyCap, cap < 0 || cap > 3 {
            return "每日上限只能是 0 到 3"
        }
        return nil
    }

    // MARK: slot ledger

    /// Whether a slot already fired (or was silently consumed).
    func isSlotFired(hour: Int, dateKey: String) -> Bool {
        firedSlots.contains(slotKey(hour: hour, dateKey: dateKey))
    }

    private func slotKey(hour: Int, dateKey: String) -> String {
        "\(dateKey)-\(hour)"
    }

    /// The foreground tick calls this. Returns the slot hour when a slot is
    /// due AND the full gate passes — the slot is then consumed (fired slots
    /// never refire). Slots whose 15-minute grace expired are consumed
    /// silently here and logged, never delivered.
    func evaluateDue(now: Date = Date()) -> Int? {
        guard config.enabled else { return nil }
        let key = ProactiveClock.dateKey(of: now)
        // First: silently consume expired slots from today.
        for h in config.slotHours {
            guard let fire = ProactiveClock.date(hour: h, on: key) else { continue }
            let sk = slotKey(hour: h, dateKey: key)
            guard !firedSlots.contains(sk) else { continue }
            if now.timeIntervalSince(fire) > 15 * 60 {
                firedSlots.insert(sk)
                logDecision(kind: "expired",
                            text: "今日 \(h):00 时段已过期，静默消费，不补发")
            }
        }
        persistAll()
        // Then: is any slot inside its 15-minute grace right now?
        for h in config.slotHours.sorted() {
            guard let fire = ProactiveClock.date(hour: h, on: key) else { continue }
            let sk = slotKey(hour: h, dateKey: key)
            guard !firedSlots.contains(sk) else { continue }
            let elapsed = now.timeIntervalSince(fire)
            guard elapsed >= 0, elapsed <= 15 * 60 else { continue }
            // Deterministic gate first — no model call on veto.
            if postsToday[key, default: 0] >= config.dailyCap {
                logDecision(kind: "skip",
                            text: "今日 \(h):00 时段：今日已发 \(config.dailyCap) 条，达到自发帖上限，这次不发")
                continue
            }
            switch ProactiveEngine.shared.gate(kind: "selfpost", now: now) {
            case .allow:
                firedSlots.insert(sk)
                persistAll()
                logger.info("[selfpost] slot \(h):00 passed gate")
                return h
            case .veto(let reason):
                logDecision(kind: "veto", text: "今日 \(h):00 时段：\(reason)，静默跳过")
                continue
            }
        }
        return nil
    }

    func postsCountToday(now: Date = Date()) -> Int {
        postsToday[ProactiveClock.dateKey(of: now), default: 0]
    }

    // MARK: publish

    /// Publish the AI-composed copy. Fail-closed: gate runs again; the feed
    /// sink may refuse (honest gap — never fake a publish).
    func publish(copy: String, now: Date = Date()) async -> Result<String, Error> {
        guard config.enabled else {
            return .failure(SelfPostVetoError("自发帖没开：只有她能打开"))
        }
        let trimmed = copy.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .failure(SelfPostVetoError("文案是空的，不发"))
        }
        let key = ProactiveClock.dateKey(of: now)
        if postsToday[key, default: 0] >= config.dailyCap {
            logDecision(kind: "skip", text: "想发但今日已达上限（\(config.dailyCap)），没发")
            return .failure(SelfPostVetoError("今日自发帖已达上限"))
        }
        switch ProactiveEngine.shared.gate(kind: "selfpost", now: now) {
        case .veto(let reason):
            logDecision(kind: "veto", text: "想发但被拦下：\(reason)")
            return .failure(SelfPostVetoError(reason))
        case .allow:
            break
        }
        do {
            try await feedSink.publishSelfPost(text: trimmed)
        } catch {
            logDecision(kind: "skip", text: "发失败了（\(error.localizedDescription)），如实记下来")
            return .failure(error)
        }
        postsToday[key, default: 0] += 1
        persistAll()
        ProactiveEngine.shared.recordSend(kind: "selfpost", now: now)
        logDecision(kind: "post", text: "发了一条动态：\(String(trimmed.prefix(60)))")
        return .success("已发布到我们的空间动态流")
    }

    // MARK: decision log

    func logDecision(kind: String, text: String, now: Date = Date()) {
        decisions.append(SelfPostDecision(at: now.timeIntervalSince1970,
                                          kind: kind, text: text))
        if decisions.count > 50 {
            decisions.removeFirst(decisions.count - 50)
        }
        persistAll()
    }

    /// "AI 今天想发没发" — newest first, for the settings section.
    func todaysDecisions(now: Date = Date()) -> [SelfPostDecision] {
        let key = ProactiveClock.dateKey(of: now)
        return decisions
            .filter { ProactiveClock.dateKey(of: Date(timeIntervalSince1970: $0.at)) == key }
            .reversed()
    }
}

struct SelfPostVetoError: Error, LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
