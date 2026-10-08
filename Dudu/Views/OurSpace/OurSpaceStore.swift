import Combine
import SwiftUI

// MARK: - OurSpaceStore · 我们的空间 data layer
//
// Five sections, persisted device-local (UserDefaults JSON).
// Ported from the old Dudu spec (openmuse/apps/mobile/src/our-space/store.ts):
// same section semantics (status / diary / timeline / memory garden /
// tell-her-later), same newest-first ordering discipline.
//
// Hook points for the AI engine (all public, @MainActor):
//   OurSpaceStore.shared.setAIStatus(text:detail:)  — what the AI is doing
//   OurSpaceStore.shared.addMemorySeed(...)         — chat extraction plants seeds
//   OurSpaceStore.shared.addLater(...)              — "tell her later" queue
//   OurSpaceStore.shared.addMoment(...)             — timeline moments
//   OurSpaceStore.shared.addMomentComment(...)      — comment a moment ("她" = her, "他" = AI)
// Everything publishes through @Published so the UI refreshes live.

// MARK: - Models

/// What the AI is currently doing. Written by the AI (via dialog/tools).
struct AIStatus: Codable, Equatable {
    var text: String
    var detail: String
    var updatedAt: Date
}

/// Her mood, as she told him. A good partner remembers.
struct HerMood: Codable, Equatable {
    var mood: String
    var note: String
    var updatedAt: Date
}

struct DiaryEntry: Codable, Identifiable, Equatable {
    var id: String
    /// Display date, YYYY-MM-DD.
    var date: String
    var title: String
    var content: String
    var createdAt: Date
}

enum MomentKind: String, Codable, CaseIterable {
    case moment
    case milestone
    case note

    var label: String {
        switch self {
        case .moment: return "时刻"
        case .milestone: return "里程碑"
        case .note: return "小记"
        }
    }

    /// Timeline dot color — DuduTheme only.
    @MainActor
    var dotColor: Color {
        switch self {
        case .moment: return DuduTheme.pink
        case .milestone: return DuduTheme.brandBrown
        case .note: return DuduTheme.duduTextDim
        }
    }

    var systemImage: String {
        switch self {
        case .moment: return "heart.fill"
        case .milestone: return "flag.fill"
        case .note: return "note.text"
        }
    }
}

/// One comment on a moment. Author is "她" (her) or "他" (him, the AI).
struct MomentComment: Codable, Identifiable, Equatable {
    var id: String
    var author: String
    var text: String
    var createdAt: Date
}

struct Moment: Codable, Identifiable, Equatable {
    var id: String
    var timestamp: Date
    var title: String
    var detail: String
    var kind: MomentKind
    /// Her like state — the heart button toggles this.
    var likedByHer: Bool
    /// Total likes (hers + his).
    var likeCount: Int
    /// Comment thread, oldest first.
    var comments: [MomentComment]

    private enum CodingKeys: String, CodingKey {
        case id, timestamp, title, detail, kind, likedByHer, likeCount, comments
    }

    init(id: String, timestamp: Date, title: String, detail: String, kind: MomentKind,
         likedByHer: Bool = false, likeCount: Int = 0, comments: [MomentComment] = []) {
        self.id = id
        self.timestamp = timestamp
        self.title = title
        self.detail = detail
        self.kind = kind
        self.likedByHer = likedByHer
        self.likeCount = likeCount
        self.comments = comments
    }

    /// Tolerates moments saved before like/comment existed (v1 data).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        timestamp = try c.decode(Date.self, forKey: .timestamp)
        title = try c.decode(String.self, forKey: .title)
        detail = try c.decode(String.self, forKey: .detail)
        kind = try c.decode(MomentKind.self, forKey: .kind)
        likedByHer = try c.decodeIfPresent(Bool.self, forKey: .likedByHer) ?? false
        likeCount = try c.decodeIfPresent(Int.self, forKey: .likeCount) ?? 0
        comments = try c.decodeIfPresent([MomentComment].self, forKey: .comments) ?? []
    }
}

enum MemoryConfidence: String, Codable, CaseIterable {
    case blooming
    case sprouting
    case ask

    var label: String {
        switch self {
        case .blooming: return "盛放"
        case .sprouting: return "萌芽"
        case .ask: return "想问她"
        }
    }

    var hint: String {
        switch self {
        case .blooming: return "记得很牢"
        case .sprouting: return "拿不太准，等她确认"
        case .ask: return "想问她，在对话框里回答就行"
        }
    }

    @MainActor
    var chipColor: Color {
        switch self {
        case .blooming: return DuduTheme.pink
        case .sprouting: return DuduTheme.duduIconChip
        case .ask: return DuduTheme.pinkSoft
        }
    }

    var systemImage: String {
        switch self {
        case .blooming: return "flower.fill"
        case .sprouting: return "leaf.fill"
        case .ask: return "questionmark.circle"
        }
    }
}

enum MemoryCategory: String, Codable, CaseIterable {
    case preference
    case fact
    case relationship
    case goal
    case habit
    case other

    var label: String {
        switch self {
        case .preference: return "偏好"
        case .fact: return "事实"
        case .relationship: return "关系"
        case .goal: return "目标"
        case .habit: return "习惯"
        case .other: return "其他"
        }
    }
}

/// One memory card — the unit the garden renders.
struct MemorySeed: Codable, Identifiable, Equatable {
    var id: String
    var content: String
    var category: MemoryCategory
    var confidence: MemoryConfidence
    var createdAt: Date
    var updatedAt: Date
}

/// "Tell her later" inbox item. She checks them off.
struct LaterItem: Codable, Identifiable, Equatable {
    var id: String
    var text: String
    var createdAt: Date
    var done: Bool
    var doneAt: Date?
}

// MARK: - Store

@MainActor
final class OurSpaceStore: ObservableObject {
    static let shared = OurSpaceStore()

    @Published private(set) var aiStatus: AIStatus?
    @Published private(set) var herMood: HerMood?
    @Published private(set) var diary: [DiaryEntry] = []
    @Published private(set) var moments: [Moment] = []
    @Published private(set) var seeds: [MemorySeed] = []
    @Published private(set) var laterItems: [LaterItem] = []

    private enum Key {
        static let status = "dudu.ourspace.v1.status"
        static let herMood = "dudu.ourspace.v1.herMood"
        static let diary = "dudu.ourspace.v1.diary"
        static let moments = "dudu.ourspace.v1.moments"
        static let seeds = "dudu.ourspace.v1.seeds"
        static let later = "dudu.ourspace.v1.later"
    }

    private let defaults = UserDefaults.standard
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .secondsSince1970
        return e
    }()
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .secondsSince1970
        return d
    }()

    init() {
        aiStatus = load(Key.status, as: AIStatus.self)
        herMood = load(Key.herMood, as: HerMood.self)
        diary = (load(Key.diary, as: [DiaryEntry].self) ?? []).sorted { $0.createdAt > $1.createdAt }
        moments = (load(Key.moments, as: [Moment].self) ?? []).sorted { $0.timestamp > $1.timestamp }
        seeds = (load(Key.seeds, as: [MemorySeed].self) ?? []).sorted { $0.updatedAt > $1.updatedAt }
        laterItems = sortLater(load(Key.later, as: [LaterItem].self) ?? [])
    }

    // MARK: Persistence

    /// Re-read everything from UserDefaults, dropping in-memory state.
    /// Used after a restore rollback rewrote the raw values behind this store.
    func reloadFromDisk() {
        aiStatus = load(Key.status, as: AIStatus.self)
        herMood = load(Key.herMood, as: HerMood.self)
        diary = (load(Key.diary, as: [DiaryEntry].self) ?? []).sorted { $0.createdAt > $1.createdAt }
        moments = (load(Key.moments, as: [Moment].self) ?? []).sorted { $0.timestamp > $1.timestamp }
        seeds = (load(Key.seeds, as: [MemorySeed].self) ?? []).sorted { $0.updatedAt > $1.updatedAt }
        laterItems = sortLater(load(Key.later, as: [LaterItem].self) ?? [])
    }

    private func load<T: Decodable>(_ key: String, as type: T.Type) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? decoder.decode(T.self, from: data)
    }

    private func save<T: Encodable>(_ value: T, key: String) {
        if let data = try? encoder.encode(value) {
            defaults.set(data, forKey: key)
        }
    }

    private func sortLater(_ items: [LaterItem]) -> [LaterItem] {
        items.sorted { a, b in
            if a.done != b.done { return !a.done }
            if a.done {
                return (a.doneAt ?? a.createdAt) > (b.doneAt ?? b.createdAt)
            }
            return a.createdAt < b.createdAt
        }
    }

    // MARK: Status (AI hook)

    /// What the AI is doing right now. Called by the AI via dialog/tools.
    func setAIStatus(text: String, detail: String = "") {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        aiStatus = AIStatus(text: t, detail: detail.trimmingCharacters(in: .whitespacesAndNewlines), updatedAt: Date())
        save(aiStatus, key: Key.status)
    }

    func setHerMood(mood: String, note: String = "") {
        let m = mood.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !m.isEmpty else { return }
        herMood = HerMood(mood: m, note: note.trimmingCharacters(in: .whitespacesAndNewlines), updatedAt: Date())
        save(herMood, key: Key.herMood)
        // [D18-avatar] her-mood hook: the avatar reflects her mood when idle.
        if let herMood {
            AvatarEmotionEngine.shared.noteHerMood(herMood)
        }
    }

    // MARK: Diary

    @discardableResult
    func addDiary(title: String, content: String, date: String? = nil) -> DiaryEntry? {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let c = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, !c.isEmpty else { return nil }
        let entry = DiaryEntry(
            id: UUID().uuidString,
            date: Self.validDateString(date) ?? Self.todayString(),
            title: t,
            content: c,
            createdAt: Date()
        )
        diary.insert(entry, at: 0)
        save(diary, key: Key.diary)
        return entry
    }

    func deleteDiary(id: String) {
        diary.removeAll { $0.id == id }
        save(diary, key: Key.diary)
    }

    // MARK: Moments (timeline)

    @discardableResult
    func addMoment(title: String, detail: String = "", kind: MomentKind = .moment) -> Moment? {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }
        let m = Moment(
            id: UUID().uuidString,
            timestamp: Date(),
            title: t,
            detail: detail.trimmingCharacters(in: .whitespacesAndNewlines),
            kind: kind
        )
        moments.insert(m, at: 0)
        save(moments, key: Key.moments)
        return m
    }

    func deleteMoment(id: String) {
        moments.removeAll { $0.id == id }
        save(moments, key: Key.moments)
    }

    /// Current snapshot of one moment (structs are values; views re-read on change).
    func moment(id: String) -> Moment? {
        moments.first(where: { $0.id == id })
    }

    /// WeChat/Instagram-style heart toggle. Her like adds one, unliking removes one.
    func toggleMomentLike(id: String) {
        guard let i = moments.firstIndex(where: { $0.id == id }) else { return }
        if moments[i].likedByHer {
            moments[i].likedByHer = false
            moments[i].likeCount = max(0, moments[i].likeCount - 1)
        } else {
            moments[i].likedByHer = true
            moments[i].likeCount += 1
        }
        save(moments, key: Key.moments)
    }

    /// Add a comment to a moment. Author "她" is her; the AI posts as "他" (AI hook).
    @discardableResult
    func addMomentComment(momentID: String, text: String, author: String = "她") -> MomentComment? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, let i = moments.firstIndex(where: { $0.id == momentID }) else { return nil }
        let comment = MomentComment(id: UUID().uuidString, author: author, text: t, createdAt: Date())
        moments[i].comments.append(comment)
        save(moments, key: Key.moments)
        return comment
    }

    func deleteMomentComment(momentID: String, commentID: String) {
        guard let i = moments.firstIndex(where: { $0.id == momentID }) else { return }
        moments[i].comments.removeAll { $0.id == commentID }
        save(moments, key: Key.moments)
    }

    // MARK: Memory garden

    @discardableResult
    func addMemorySeed(content: String, category: MemoryCategory = .other, confidence: MemoryConfidence = .sprouting) -> MemorySeed? {
        let c = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !c.isEmpty else { return nil }
        let now = Date()
        let seed = MemorySeed(id: UUID().uuidString, content: c, category: category, confidence: confidence, createdAt: now, updatedAt: now)
        seeds.insert(seed, at: 0)
        save(seeds, key: Key.seeds)
        return seed
    }

    /// She confirmed a sprouting seed is right — it blooms.
    @discardableResult
    func confirmSeed(id: String) -> Bool {
        guard let i = seeds.firstIndex(where: { $0.id == id }), seeds[i].confidence == .sprouting else { return false }
        seeds[i].confidence = .blooming
        seeds[i].updatedAt = Date()
        save(seeds, key: Key.seeds)
        return true
    }

    /// She answered a question seed — the answer is kept, and it blooms.
    @discardableResult
    func answerSeed(id: String, answer: String) -> Bool {
        let a = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !a.isEmpty,
              let i = seeds.firstIndex(where: { $0.id == id }),
              seeds[i].confidence == .ask else { return false }
        seeds[i].content = seeds[i].content + "\n她的回答：" + a
        seeds[i].confidence = .blooming
        seeds[i].updatedAt = Date()
        save(seeds, key: Key.seeds)
        return true
    }

    func deleteSeed(id: String) {
        seeds.removeAll { $0.id == id }
        save(seeds, key: Key.seeds)
    }

    // MARK: Tell-her-later inbox

    @discardableResult
    func addLater(text: String) -> LaterItem? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }
        let item = LaterItem(id: UUID().uuidString, text: t, createdAt: Date(), done: false, doneAt: nil)
        laterItems = sortLater(laterItems + [item])
        save(laterItems, key: Key.later)
        return item
    }

    func toggleLater(id: String) {
        guard let i = laterItems.firstIndex(where: { $0.id == id }) else { return }
        laterItems[i].done.toggle()
        laterItems[i].doneAt = laterItems[i].done ? Date() : nil
        laterItems = sortLater(laterItems)
        save(laterItems, key: Key.later)
    }

    func deleteLater(id: String) {
        laterItems.removeAll { $0.id == id }
        save(laterItems, key: Key.later)
    }

    var undoneLaterCount: Int { laterItems.filter { !$0.done }.count }

    // MARK: - Backup / restore

    /// Snapshot of every persisted section as the store's own UserDefaults
    /// key → encoded bytes. Carried opaquely by the backup (`data/our_space.jsonl`)
    /// so the package never pins a second copy of these models.
    /// `count` is the number of items in the section (1 for singletons), for
    /// honest category stats.
    func backupRecords() -> [(key: String, data: Data, count: Int)] {
        var out: [(key: String, data: Data, count: Int)] = []
        if let d = defaults.data(forKey: Key.status),
           (try? decoder.decode(AIStatus.self, from: d)) != nil {
            out.append((Key.status, d, 1))
        }
        if let d = defaults.data(forKey: Key.herMood),
           (try? decoder.decode(HerMood.self, from: d)) != nil {
            out.append((Key.herMood, d, 1))
        }
        if let d = defaults.data(forKey: Key.diary),
           let v = try? decoder.decode([DiaryEntry].self, from: d) {
            out.append((Key.diary, d, v.count))
        }
        if let d = defaults.data(forKey: Key.moments),
           let v = try? decoder.decode([Moment].self, from: d) {
            out.append((Key.moments, d, v.count))
        }
        if let d = defaults.data(forKey: Key.seeds),
           let v = try? decoder.decode([MemorySeed].self, from: d) {
            out.append((Key.seeds, d, v.count))
        }
        if let d = defaults.data(forKey: Key.later),
           let v = try? decoder.decode([LaterItem].self, from: d) {
            out.append((Key.later, d, v.count))
        }
        return out
    }

    /// Every key this store may own, including absent ones — for restore
    /// rollback, which must also remove keys the restore created.
    /// Nonisolated so the backup engine can read it off the MainActor.
    nonisolated static var backupAllKeys: [String] {
        [Key.status, Key.herMood, Key.diary, Key.moments, Key.seeds, Key.later]
    }

    /// Merge one backup's records into the live store. Merge, never replace:
    /// an entry already present locally keeps the local version (the restore
    /// confirmation promises "nothing is deleted"), and only genuinely new
    /// entries are added. Singleton sections (AI status, her mood) keep the
    /// local value when one exists — a restore onto the device that produced
    /// the backup must be a no-op. Returns (imported, skipped).
    @discardableResult
    func restoreBackupRecords(_ records: [(key: String, data: Data, count: Int)])
        -> (imported: Int, skipped: Int) {
        var imported = 0
        var skipped = 0
        for (key, data, _) in records {
            switch key {
            case Key.status:
                if aiStatus == nil, let v = try? decoder.decode(AIStatus.self, from: data) {
                    aiStatus = v; save(aiStatus, key: Key.status); imported += 1
                } else { skipped += 1 }
            case Key.herMood:
                if herMood == nil, let v = try? decoder.decode(HerMood.self, from: data) {
                    herMood = v; save(herMood, key: Key.herMood); imported += 1
                } else { skipped += 1 }
            case Key.diary:
                guard let incoming = try? decoder.decode([DiaryEntry].self, from: data) else {
                    skipped += 1; continue
                }
                let r = mergeIdentifiable(&diary, incoming: incoming)
                diary.sort { $0.createdAt > $1.createdAt }
                save(diary, key: Key.diary)
                imported += r.added; skipped += r.skipped
            case Key.moments:
                guard let incoming = try? decoder.decode([Moment].self, from: data) else {
                    skipped += 1; continue
                }
                let r = mergeIdentifiable(&moments, incoming: incoming)
                moments.sort { $0.timestamp > $1.timestamp }
                save(moments, key: Key.moments)
                imported += r.added; skipped += r.skipped
            case Key.seeds:
                guard let incoming = try? decoder.decode([MemorySeed].self, from: data) else {
                    skipped += 1; continue
                }
                let r = mergeIdentifiable(&seeds, incoming: incoming)
                seeds.sort { $0.updatedAt > $1.updatedAt }
                save(seeds, key: Key.seeds)
                imported += r.added; skipped += r.skipped
            case Key.later:
                guard let incoming = try? decoder.decode([LaterItem].self, from: data) else {
                    skipped += 1; continue
                }
                let r = mergeIdentifiable(&laterItems, incoming: incoming)
                laterItems = sortLater(laterItems)
                save(laterItems, key: Key.later)
                imported += r.added; skipped += r.skipped
            default:
                // A newer writer's section this build doesn't know — ignore,
                // don't fail (§2.2 rule 2).
                skipped += 1
            }
        }
        return (imported, skipped)
    }

    /// Union by id; local wins on collision. Every Our Space list item is
    /// Identifiable with a String id.
    private func mergeIdentifiable<T: Identifiable>(
        _ current: inout [T], incoming: [T]
    ) -> (added: Int, skipped: Int) where T.ID == String {
        var ids = Set(current.map(\.id))
        var added = 0
        var skipped = 0
        for item in incoming {
            if ids.contains(item.id) { skipped += 1 }
            else { ids.insert(item.id); current.append(item); added += 1 }
        }
        return (added, skipped)
    }

    // MARK: Date helpers

    static func todayString(_ date: Date = Date()) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    private static func validDateString(_ s: String?) -> String? {
        guard let s, s.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil else { return nil }
        return s
    }
}

// MARK: - Display formatting (shared by the section views)

func ourSpaceRelativeTime(from date: Date, now: Date = Date()) -> String {
    let s = Int(now.timeIntervalSince(date))
    if s < 60 { return "刚刚" }
    if s < 3600 { return "\(s / 60) 分钟前" }
    if s < 86400 { return "\(s / 3600) 小时前" }
    if s < 86400 * 30 { return "\(s / 86400) 天前" }
    return ourSpaceDayString(from: date)
}

func ourSpaceDayString(from date: Date) -> String {
    let f = DateFormatter()
    f.locale = Locale(identifier: "zh_CN")
    f.dateFormat = "yyyy-MM-dd"
    return f.string(from: date)
}

func ourSpaceDateTimeString(from date: Date) -> String {
    let f = DateFormatter()
    f.locale = Locale(identifier: "zh_CN")
    f.dateFormat = "yyyy-MM-dd HH:mm"
    return f.string(from: date)
}
