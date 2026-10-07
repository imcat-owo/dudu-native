//
//  D20a (2026-10-08): next-day follow-up （次日跟进）.
//
//  Manual: openmuse/apps/mobile/src/manuals/initiative.ts
//  ("Memory-driven next-day follow-ups")
//
//  When SHE mentions a future-dated commitment/event （我明天有个面试）,
//  the AI records it with followup_add — like writing it down, and ALWAYS
//  tells her it is tracking it （记下了，后天问你结果怎么样）, so nothing
//  fires secretly. The follow-up fires ONCE, the day after the event at
//  17:00 Shanghai (her "morning" — never in her 06:00–16:00 sleep window),
//  through the shared proactive gate: shared daily cap, never retried.
//  A failed fire still consumes its slot.
//
//  Auto-cancel: if the event already came up in chat after tracking started,
//  the follow-up cancels itself — never ask about something she already
//  told you. The chat engine calls mentionsEvent(_:) per her message
//  (heuristic keyword match) or eventDiscussed(id:). The AI itself is the
//  primary judge: it reads followup_list and calls followup_delete when she
//  already told it — the heuristic below is only a backstop.

import Foundation
import Combine

struct FollowUpItem: Codable, Identifiable {
    var id: String = UUID().uuidString
    var text: String              // her words about the event
    var eventDateKey: String      // "yyyy-MM-dd" Shanghai, the event day
    var createdAt: TimeInterval
    var delivered: Bool = false   // fired (or consumed) — fires exactly once
    var cancelled: Bool = false   // she deleted it, or auto-cancelled
    var personaId: String? = nil

    /// Fire time: the day AFTER the event, 17:00 Shanghai.
    var fireDate: Date? {
        let f = DateFormatter()
        f.timeZone = ProactiveClock.shanghai
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        guard let day = f.date(from: eventDateKey) else { return nil }
        guard let next = ProactiveClock.addDays(day, 1) else { return nil }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = ProactiveClock.shanghai
        return cal.date(bySettingHour: 17, minute: 0, second: 0, of: next)
    }

    var isPending: Bool { !delivered && !cancelled }
}

@MainActor
final class FollowUpManager: ObservableObject {
    static let shared = FollowUpManager()

    private static let itemsKey = "followup.items.v1"
    private static let masterKey = "followup.masterEnabled.v1"

    private let logger = AppLogger(category: "FollowUp")

    @Published private(set) var items: [FollowUpItem] = []

    /// Master toggle (Our Space -> 次日跟进). Only SHE flips it.
    var masterEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: Self.masterKey) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: Self.masterKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: Self.masterKey) }
    }

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.itemsKey),
           let decoded = try? JSONDecoder().decode([FollowUpItem].self, from: data) {
            items = decoded
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: Self.itemsKey)
        }
    }

    // MARK: CRUD (write tools are incognito-blocked; see ProactiveTools)

    func add(text: String, eventDateKey: String, personaId: String? = nil,
             now: Date = Date()) throws -> FollowUpItem {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw FollowUpError("要记的事是空的") }
        let item = FollowUpItem(text: trimmed, eventDateKey: eventDateKey,
                                createdAt: now.timeIntervalSince1970,
                                personaId: personaId)
        guard item.fireDate != nil else {
            throw FollowUpError("日期格式不对，用 yyyy-MM-dd（比如 2026-10-09）")
        }
        items.append(item)
        persist()
        logger.info("[followup] tracking: \(trimmed.prefix(40)) -> \(eventDateKey)")
        return item
    }

    func delete(id: String) {
        items.removeAll { $0.id == id }
        persist()
    }

    func cancel(id: String, reason: String) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        items[i].cancelled = true
        persist()
        logger.info("[followup] cancelled \(id.prefix(6)): \(reason)")
    }

    func pendingItems() -> [FollowUpItem] {
        items.filter(\.isPending).sorted {
            ($0.fireDate ?? .distantFuture) < ($1.fireDate ?? .distantFuture)
        }
    }

    // MARK: firing

    /// Foreground tick: items whose time has come attempt to fire through
    /// the shared gate. Returns the ones that PASSED (the AI phrases and
    /// sends them through the normal proactive path). Consumed either way —
    /// a fired slot never refires, and a veto consumes silently.
    func attemptDueFires(now: Date = Date()) -> [FollowUpItem] {
        guard masterEnabled else { return [] }
        var fired: [FollowUpItem] = []
        for i in items.indices where items[i].isPending {
            guard let fire = items[i].fireDate, fire <= now else { continue }
            // Consume the slot first: never retried, whatever happens.
            items[i].delivered = true
            switch ProactiveEngine.shared.gate(kind: "followup", now: now) {
            case .allow:
                ProactiveEngine.shared.recordSend(kind: "followup", now: now)
                fired.append(items[i])
                logger.info("[followup] firing: \(items[i].text.prefix(40))")
            case .veto(let reason):
                logger.info("[followup] vetoed (consumed): \(reason)")
            }
        }
        persist()
        return fired
    }

    /// Background tick helper: one item that is already due, to be delivered
    /// as a single template notification. Call consume(_:) after scheduling.
    func peekBackgroundDue(now: Date = Date()) -> FollowUpItem? {
        guard masterEnabled else { return nil }
        return pendingItems().first { ($0.fireDate ?? .distantFuture) <= now }
    }

    func consume(_ id: String) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        items[i].delivered = true
        persist()
    }

    // MARK: auto-cancel

    /// HOOK: the chat engine calls this for each of her messages. Heuristic
    /// backstop (the AI's own judgment via followup_list is primary).
    /// Returns the cancelled item, if any.
    func mentionsEvent(_ message: String) -> FollowUpItem? {
        let norm = normalize(message)
        guard norm.count >= 2 else { return nil }
        for item in pendingItems() {
            for phrase in keyPhrases(of: item.text) {
                // Short phrase: 2-char windows; long phrase: 4-char windows.
                let size = phrase.count <= 6 ? 2 : 4
                if charWindows(phrase, size).contains(where: { norm.contains($0) }) {
                    cancel(id: item.id, reason: "她在聊天里已经提到了，自动取消")
                    return item
                }
            }
        }
        return nil
    }

    /// Explicit hook when the coordinator knows an event was discussed.
    func eventDiscussed(id: String) {
        cancel(id: id, reason: "事件已在聊天里聊过，自动取消")
    }

    // MARK: text helpers

    private static let separators =
        CharacterSet(charactersIn: "，。！？；：、…—· \t\n\"'「」『』（）()【】,.!?;:")

    private func normalize(_ s: String) -> String {
        s.components(separatedBy: Self.separators).joined()
    }

    /// Key phrases: the item's text split on separators, normalized,
    /// 3+ chars each.
    private func keyPhrases(of text: String) -> [String] {
        text.components(separatedBy: Self.separators)
            .map { normalize($0) }
            .filter { $0.count >= 3 }
    }

    private func charWindows(_ s: String, _ size: Int) -> [String] {
        let chars = Array(s)
        guard chars.count >= size else { return [s] }
        return (0...(chars.count - size)).map { String(chars[$0..<$0 + size]) }
    }
}

struct FollowUpError: Error, LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
