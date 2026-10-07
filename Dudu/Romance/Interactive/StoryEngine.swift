//
//  D20b: 互动故事 StoryEngine —— faithfully ported from
//  ~/workspace/openmuse/apps/mobile/src/story/ (types.ts, store.ts, prompt.ts).
//
//  互动故事：她和 AI 在普通对话框里合写故事。AI 按幕讲，她用选项（A/B/C）
//  或自由回复推进。故事设定集（人物/地点/关键事件）她看得见、改得了；
//  故事绑定 ONE dialog + ONE persona；暂停/完结都回到普通聊天——
//  永远不许把她困在故事模式里。

import Foundation

// MARK: - Types （types.ts 逐项移植）

/// 进行中 / 已暂停 / 已完结。
public enum StoryStatus: String, Codable, Sendable {
    case active
    case paused
    case ended
}

public struct StoryCharacter: Codable, Sendable, Equatable, Identifiable {
    public var id: String { name }
    public var name: String
    public var desc: String
    public init(name: String, desc: String = "") {
        self.name = name
        self.desc = desc
    }
}

public struct StoryPlace: Codable, Sendable, Equatable, Identifiable {
    public var id: String { name }
    public var name: String
    public var desc: String
    public init(name: String, desc: String = "") {
        self.name = name
        self.desc = desc
    }
}

public struct StoryEvent: Codable, Sendable, Equatable, Identifiable {
    public var id: String { "\(text)_\(at)" }
    public var text: String
    public var at: TimeInterval
    public init(text: String, at: TimeInterval = 0) {
        self.text = text
        self.at = at
    }
}

/// 故事设定集：她看得见、她改得了，绝不是 AI 背着她偷改的秘密。
public struct StoryBible: Codable, Sendable, Equatable {
    public var characters: [StoryCharacter] = []
    public var places: [StoryPlace] = []
    public var events: [StoryEvent] = []
    public init(characters: [StoryCharacter] = [], places: [StoryPlace] = [], events: [StoryEvent] = []) {
        self.characters = characters
        self.places = places
        self.events = events
    }
}

public struct StoryChoice: Codable, Sendable, Equatable {
    /// 幕内稳定："A"、"B"、"C"……
    public var id: String
    /// 短标签，如「推开那扇门」。
    public var label: String
    public init(id: String, label: String) {
        self.id = id
        self.label = label
    }
}

public struct StoryScene: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var chapter: Int
    /// 章内 1-based 幕号。
    public var seq: Int
    /// AI 自己对这一幕的梗概（不是全文）。
    public var summary: String
    /// 幕末给出的选项。空 = 开放式提问。
    public var offeredChoices: [StoryChoice]
    /// 她选的选项 id。nil = 开放式回答，或还没选。
    public var chosenChoiceId: String?
    /// 开放式提问时她的回复要点（可选）。
    public var freeNote: String
    public var at: TimeInterval
    public init(id: String, chapter: Int, seq: Int, summary: String,
                offeredChoices: [StoryChoice] = [], chosenChoiceId: String? = nil,
                freeNote: String = "", at: TimeInterval = 0) {
        self.id = id
        self.chapter = chapter
        self.seq = seq
        self.summary = summary
        self.offeredChoices = offeredChoices
        self.chosenChoiceId = chosenChoiceId
        self.freeNote = freeNote
        self.at = at
    }
}

public struct Story: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var personaId: String
    /// 讲故事的对话框。resume 时重新绑定。
    public var threadId: String
    public var title: String
    /// 约定好的开头，如「雾岛上的灯塔，潮汐里捡到黄铜钥匙」。
    public var premise: String
    public var status: StoryStatus
    public var currentChapter: Int
    public var scenes: [StoryScene]
    public var bible: StoryBible
    public var createdAt: TimeInterval
    public var updatedAt: TimeInterval

    public init(id: String, personaId: String, threadId: String, title: String,
                premise: String, status: StoryStatus = .active, currentChapter: Int = 1,
                scenes: [StoryScene] = [], bible: StoryBible = StoryBible(),
                createdAt: TimeInterval = 0, updatedAt: TimeInterval = 0) {
        self.id = id
        self.personaId = personaId
        self.threadId = threadId
        self.title = title
        self.premise = premise
        self.status = status
        self.currentChapter = currentChapter
        self.scenes = scenes
        self.bible = bible
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - Pure helpers （types.ts 逐项移植）

public enum StoryHelpers {
    public static func newStoryId(now: Date = Date()) -> String {
        "st_\(Int(now.timeIntervalSince1970 * 1000).description)\(Int.random(in: 0 ..< 36 * 36 * 36 * 36 * 36 * 36).description)"
    }

    public static func newSceneId(now: Date = Date()) -> String {
        "ss_\(Int(now.timeIntervalSince1970 * 1000).description)\(Int.random(in: 0 ..< 36 * 36 * 36 * 36 * 36 * 36).description)"
    }

    /// 等她选的那一幕：选项已给出、还没被选的最新一幕。
    public static func pendingChoiceScene(_ story: Story) -> StoryScene? {
        for scene in story.scenes.reversed() {
            if !scene.offeredChoices.isEmpty, scene.chosenChoiceId == nil {
                return scene
            }
        }
        return nil
    }

    public static func latestScene(_ story: Story) -> StoryScene? {
        story.scenes.last
    }

    /// 章内下一幕的序号（1-based）。
    public static func nextSceneSeq(_ story: Story, chapter: Int) -> Int {
        story.scenes.filter { $0.chapter == chapter }.count + 1
    }
}

// MARK: - StoryStore （store.ts 移植：actor + JSON 文件持久化）

/// 故事仓库。一个 dialog 同一时间只允许一个 active/paused 故事
/// （这个约束由工具层 story_start 执行，store 不强制）。
/// 查找按 threadId——prompt 注入和选项 chips 都靠它找「正在讲的故事」。
public actor StoryStore {
    public static let shared = StoryStore()

    private static let storiesCap = 200
    private var cache: [Story]?
    private let fileURL: URL

    public init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DuduInteractive", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true, attributes: nil)
        self.fileURL = base.appendingPathComponent("stories.json")
    }

    // MARK: persistence

    private func loadAll() -> [Story] {
        if let cache { return cache }
        var stories: [Story] = []
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([Story].self, from: data) {
            stories = decoded
        }
        cache = stories
        return stories
    }

    private func saveAll(_ stories: [Story]) {
        let capped = Array(stories.suffix(Self.storiesCap))
        cache = capped
        if let data = try? JSONEncoder().encode(capped) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    // MARK: API

    /// 建故事。输入非法返回 nil（不抛错）。
    @discardableResult
    public func create(personaId: String, threadId: String, title: String, premise: String, now: Date = Date()) -> Story? {
        let pid = personaId.trimmingCharacters(in: .whitespacesAndNewlines)
        let tid = threadId.trimmingCharacters(in: .whitespacesAndNewlines)
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pid.isEmpty, !tid.isEmpty, !t.isEmpty else { return nil }
        var stories = loadAll()
        let story = Story(
            id: StoryHelpers.newStoryId(now: now),
            personaId: pid, threadId: tid, title: t,
            premise: premise.trimmingCharacters(in: .whitespacesAndNewlines),
            createdAt: now.timeIntervalSince1970, updatedAt: now.timeIntervalSince1970
        )
        stories.append(story)
        saveAll(stories)
        return story
    }

    public func get(id: String) -> Story? {
        loadAll().first { $0.id == id }
    }

    /// 某个人设的故事，最新在前。includeEnded=false 时只看未完结的。
    public func list(personaId: String, includeEnded: Bool = false) -> [Story] {
        loadAll()
            .filter { $0.personaId == personaId && (includeEnded || $0.status != .ended) }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    /// 这个对话框正在讲的故事（active 或 paused）。最新者胜。
    public func findByThread(_ threadId: String) -> Story? {
        loadAll()
            .filter { $0.threadId == threadId && $0.status != .ended }
            .sorted { $0.updatedAt > $1.updatedAt }
            .first
    }

    /// 对一个故事做变更。返回更新后的故事，找不到返回 nil。
    @discardableResult
    public func update(id: String, now: Date = Date(), _ mutate: (inout Story) -> Bool) -> Story? {
        var stories = loadAll()
        guard let idx = stories.firstIndex(where: { $0.id == id }) else { return nil }
        var story = stories[idx]
        guard mutate(&story) else { return nil }
        story.updatedAt = now.timeIntervalSince1970
        stories[idx] = story
        saveAll(stories)
        return story
    }

    @discardableResult
    public func remove(id: String) -> Bool {
        let stories = loadAll()
        let kept = stories.filter { $0.id != id }
        guard kept.count != stories.count else { return false }
        saveAll(kept)
        return true
    }
}

// MARK: - StoryPrompt （prompt.ts 移植：STORY MODE prompt 注入段）

/// 对话框有 ACTIVE 故事时，这段骑在 system prompt 上，
/// 让叙事保持连贯：设定集原文 + 进度 + 她上一次的选择。
/// 没故事 / 非 active / 隐身模式 / 人设不对 → 返回空串，不添噪、不泄漏。
public enum StoryPrompt {
    /// 整段硬预算（字符）。设定集列表先被裁。
    private static let sectionBudget = 1600
    private static let maxBibleLines = 12

    private static func bibleLines(_ story: Story) -> [String] {
        var lines: [String] = []
        for c in story.bible.characters {
            lines.append("人物 · \(c.name)\(c.desc.isEmpty ? "" : "：\(c.desc)")")
        }
        for p in story.bible.places {
            lines.append("地点 · \(p.name)\(p.desc.isEmpty ? "" : "：\(p.desc)")")
        }
        for e in story.bible.events.suffix(4) {
            lines.append("事件 · \(e.text)")
        }
        return Array(lines.prefix(maxBibleLines))
    }

    public static func statusWord(_ status: StoryStatus) -> String {
        switch status {
        case .active: return "进行中"
        case .paused: return "已暂停"
        case .ended: return "已完结"
        }
    }

    public static func buildSection(story: Story?, personaId: String?, incognito: Bool) -> String {
        guard !incognito else { return "" }
        guard let story else { return "" }
        guard story.status == .active else { return "" }
        guard let personaId, !personaId.isEmpty, story.personaId == personaId else { return "" }

        var lines: [String] = []
        lines.append("STORY MODE —— 你正在和她合写一个互动故事《\(story.title)》，这是故事时间，不是普通聊天。")
        if !story.premise.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("故事开头约定：\(story.premise.trimmingCharacters(in: .whitespacesAndNewlines))")
        }

        let bible = bibleLines(story)
        if !bible.isEmpty {
            lines.append("故事设定（必须遵守，不许吃书；有新人物/地点/关键事件就用 story_bible_update 记下来）：")
            lines.append(contentsOf: bible.map { "- \($0)" })
        }

        lines.append("进度：第 \(story.currentChapter) 章，已讲 \(story.scenes.count) 幕。")

        if let last = StoryHelpers.latestScene(story) {
            let summary = last.summary.count > 200 ? String(last.summary.prefix(200)) + "…" : last.summary
            lines.append("上一幕：第 \(last.chapter) 章第 \(last.seq) 幕——\(summary)")
        }

        if let pending = StoryHelpers.pendingChoiceScene(story), !pending.offeredChoices.isEmpty {
            let opts = pending.offeredChoices.map { "\($0.id)「\($0.label)」" }.joined(separator: " / ")
            lines.append("她还没选：上一幕给出的选项是 \(opts)。等她选（她说「选X」或点选项），先调 story_choose 记录，再接着讲。")
        } else {
            // 她最近一次做出的选择——即使后面是开放式幕，剧情也得接住它。
            if let lastChosen = story.scenes.reversed().first(where: { $0.chosenChoiceId != nil }),
               let chosenId = lastChosen.chosenChoiceId {
                let picked = lastChosen.offeredChoices.first { $0.id == chosenId }
                lines.append("她上一次选了：\(chosenId)\(picked.map { "「\($0.label)」" } ?? "")（第\(lastChosen.chapter)章第\(lastChosen.seq)幕）——后面的剧情要接住这个选择。")
            }
        }

        lines.append(
            "讲法：一幕一幕讲，每幕结尾要么给选项（A/B/C，简短），要么开放式问她接下来想怎样——不要两样都给，也不要把路堵死。" +
            "每讲完一幕，调一次 story_scene_add 记下梗概和给出的选项。" +
            "她说「不玩了」「结束」「换个话题」时，调 story_end 存档，然后自然地回到普通聊天——永远不许把她困在故事里。" +
            "她说「先不玩了」「暂停」时，调 story_pause 存档即可。"
        )

        var section = lines.joined(separator: "\n")
        if section.count > sectionBudget {
            let cutIndex = section.index(section.startIndex, offsetBy: sectionBudget - 3, limitedBy: section.endIndex) ?? section.endIndex
            let newlineCut = section[..<cutIndex].lastIndex(of: "\n")
            section = String(section[..<(newlineCut ?? cutIndex)]) + "…"
        }
        return section
    }
}
