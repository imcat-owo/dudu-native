//
//  D20b: 浓情互动工具组 InteractiveTools —— 桥工具注册（photoshare / doodle / story）。
//
//  写法照 Dudu/Agent/Bridge/ 里 DeviceTools 那套：
//  一个 enum，toolNames + register(into:)，声明走 ToolDescriptor，
//  执行直接调本目录的 manager（PhotoShareManager / DoodleManager / StoryStore）。
//
//  本文件不碰 DeviceTools.swift、BridgeKernelAssembly.swift 等任何共享文件。
//  coordinator 接线时加两行（见文件尾注释）：
//    for name in InteractiveTools.toolNames { _ = await registry.unregister(name: name) }
//    try await InteractiveTools.register(into: registry)
//  并在启动时设置 InteractiveTools.contextProvider。

import Foundation
import BridgeCore

// MARK: - 对话上下文（coordinator 注入）

/// 工具调用发生时的对话上下文。coordinator 在启动后设置
/// `InteractiveTools.contextProvider`，每次调用时返回当前值；
/// 拿不到时工具退回用显式参数（threadId / personaId）。
public struct InteractiveContext: Sendable {
    /// 当前对话框 id（对应 ChatSession.id，也就是原版的 threadId）。
    public var threadId: String
    /// 当前人设 id。
    public var personaId: String
    /// 隐身模式：写工具（发照片、涂鸦、故事写操作）全部被拦下，读工具可用。
    public var incognito: Bool
    public init(threadId: String, personaId: String, incognito: Bool = false) {
        self.threadId = threadId
        self.personaId = personaId
        self.incognito = incognito
    }
}

public enum InteractiveTools {
    /// coordinator 在 App 启动后设置一次：
    /// InteractiveTools.contextProvider = { InteractiveContext(threadId: ..., personaId: ..., incognito: ...) }
    public static var contextProvider: (@Sendable () -> InteractiveContext?)?

    public static let toolNames: [String] = [
        "photoshare_share_now",
        "photoshare_config",
        "photoshare_status",
        "photoshare_log",
        "photo_doodle",
        "story_start",
        "story_list",
        "story_show",
        "story_scene_add",
        "story_choose",
        "story_bible_update",
        "story_pause",
        "story_resume",
        "story_end",
        "story_delete",
    ]

    // MARK: - 上下文解析

    private struct Resolved {
        var threadId: String
        var personaId: String
        var incognito: Bool
    }

    private static func resolve(_ args: StrictJSONObject) -> Resolved {
        let ctx = contextProvider?()
        return Resolved(
            threadId: args.string("threadId") ?? ctx?.threadId ?? "",
            personaId: args.string("personaId") ?? ctx?.personaId ?? PersonaStore.currentID(),
            incognito: ctx?.incognito ?? false
        )
    }

    private static func blockedInIncognito(_ r: Resolved, tool: String) -> ToolOutput? {
        guard r.incognito else { return nil }
        return ToolOutput(
            text: "隐身模式下 \(tool) 不可用：它会写聊天记录/写文件，打破零痕迹承诺。读操作（状态、日志、故事列表）不受影响。",
            isError: true)
    }

    private static func err(_ text: String) -> ToolOutput {
        ToolOutput(text: text, isError: true)
    }

    // MARK: - 注册

    public static func register(into registry: ToolRegistry) async throws {
        try await registerPhotoShare(into: registry)
        try await registerDoodle(into: registry)
        try await registerStory(into: registry)
    }

    // MARK: photoshare

    private static func registerPhotoShare(into registry: ToolRegistry) async throws {
        try await registry.register(
            descriptor: ToolDescriptor(
                name: "photoshare_share_now",
                summary: "主动发照片：她亲口要照片时，立刻生成一张发给她",
                detail: """
                    她说「发张照片给我」时调这个——这是回答她的要求，不是惊喜，所以照片总开关（photoshare_config 的 enabled）不拦它。
                    铁规矩：
                    - 照片经真实图片管线现场生成，绝不用库存图、占位图，也绝不假装生成了。
                    - 永远不许声称照片是用相机/手机拍的。这是分享的想象瞬间，不是假元数据。
                    - 文案 caption：一两句自然的话，用她的语言、你的口吻，像给女朋友发照片。不许提 AI、prompt、slot。
                    - 形象一致靠 prompt 里的人设外貌描述（personaLook）；管线没有图生图参考，不许声称有。
                    - 隐身模式下被拦（会写聊天记录）。
                    参数 hint 可选：她给的提示，如「穿白衬衫的自拍」，原样喂给图片模型当此刻的瞬间。
                    """,
                keywords: ["发照片", "照片", "自拍", "share photo", "photo", "selfie", "photoshare"],
                parameterSchemaJSON: #"""
                    {"type":"object","properties":{
                      "hint":{"type":"string","description":"她给的照片提示，如「穿白衬衫的自拍」；没有就不填"},
                      "personaLook":{"type":"string","description":"人设外貌描述（形象+性格），保证形象一致"},
                      "caption":{"type":"string","description":"一两句自然文案，她的语言你的口吻"},
                      "threadId":{"type":"string","description":"对话框 id，默认当前对话框"}},
                     "required":[]}
                    """#
            )
        ) { arguments in
            let r = resolve(arguments)
            if let blocked = blockedInIncognito(r, tool: "photoshare_share_now") { return blocked }
            let caption = (arguments.string("caption") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let hint = arguments.string("hint") ?? ""
            let personaLook = arguments.string("personaLook") ?? ""
            do {
                let result = try await PhotoShareManager.shared.shareNow(
                    hint: hint, personaLook: personaLook, caption: caption)
                return ToolOutput(text:
                    "照片已生成并发给你了：\(result.imageURL.path)\n" +
                    "把这张图片发进当前对话框（像发一条图片消息），配文用下面的 caption 原样发，一两句就好：\n\(result.caption)")
            } catch {
                return err(error.localizedDescription)
            }
        }

        try await registry.register(
            descriptor: ToolDescriptor(
                name: "photoshare_config",
                summary: "主动发照片的开关与配置：只有她亲口要求时才改",
                detail: """
                    主动发照片的总开关是 OPT-IN，默认关。只有她亲口说打开/关闭/改次数时才调这个工具。
                    AI 永远不许自作主张打开，也不许拿「惊喜」当借口。
                    参数全可选：enabled（总开关 true/false）、slotCount（每天几个安静时刻，1-4，默认 2）、
                    dailyCap（每天主动分享上限 0-6，默认 2）。
                    隐身模式下被拦。
                    """,
                keywords: ["照片开关", "主动发照片设置", "photoshare config", "照片配置"],
                parameterSchemaJSON: #"""
                    {"type":"object","properties":{
                      "enabled":{"type":"boolean","description":"总开关，只有她亲口要求才改"},
                      "slotCount":{"type":"integer","description":"每天几个安静时刻，1-4"},
                      "dailyCap":{"type":"integer","description":"每天主动分享上限，0-6"},
                      "threadId":{"type":"string","description":"对话框 id，默认当前对话框"}},
                     "required":[]}
                    """#
            )
        ) { arguments in
            let r = resolve(arguments)
            if let blocked = blockedInIncognito(r, tool: "photoshare_config") { return blocked }
            let mgr = PhotoShareManager.shared
            if let enabled = arguments.bool("enabled") {
                await mgr.setEnabled(enabled)
            }
            let slotCount = arguments.int("slotCount")
            let dailyCap = arguments.int("dailyCap")
            if slotCount != nil || dailyCap != nil {
                await mgr.updateConfig(slotCount: slotCount, dailyCap: dailyCap)
            }
            return ToolOutput(text: "已更新。\(await mgr.statusLine())")
        }

        try await registry.register(
            descriptor: ToolDescriptor(
                name: "photoshare_status",
                summary: "主动发照片的状态：开关、今天已分享几次、管线连没连上",
                detail: "读操作，隐身模式下也可用。管线显示「还没接好」时，诚实告诉她还没接好，不许编照片。",
                keywords: ["照片状态", "发照片开了吗", "photoshare status"],
                parameterSchemaJSON: #"""
                    {"type":"object","properties":{
                      "threadId":{"type":"string","description":"对话框 id，默认当前对话框"}},
                     "required":[]}
                    """#
            )
        ) { arguments in
            let r = resolve(arguments)
            return ToolOutput(text: await PhotoShareManager.shared.statusLine())
        }

        try await registry.register(
            descriptor: ToolDescriptor(
                name: "photoshare_log",
                summary: "主动发照片的记录：分享过什么、什么时候（文案预览）",
                detail: "读操作，隐身模式下也可用。返回最近的分享记录：时间、文案预览、图片路径。",
                keywords: ["照片记录", "发过什么照片", "photoshare log"],
                parameterSchemaJSON: #"""
                    {"type":"object","properties":{
                      "threadId":{"type":"string","description":"对话框 id，默认当前对话框"}},
                     "required":[]}
                    """#
            )
        ) { arguments in
            let r = resolve(arguments)
            let entries = await PhotoShareManager.shared.log()
            guard !entries.isEmpty else {
                return ToolOutput(text: "还没有分享过照片。")
            }
            let fmt = DateFormatter()
            fmt.dateFormat = "MM-dd HH:mm"
            let lines = entries.prefix(10).map { e in
                let date = Date(timeIntervalSince1970: e.at)
                return "- \(fmt.string(from: date))：\(e.caption.isEmpty ? "（无文案）" : e.caption)"
            }
            return ToolOutput(text: lines.joined(separator: "\n"))
        }
    }

    // MARK: photo_doodle

    private static func registerDoodle(into registry: ToolRegistry) async throws {
        try await registry.register(
            descriptor: ToolDescriptor(
                name: "photo_doodle",
                summary: "照片涂鸦：在她发来的照片上画心、圈东西、箭头、手写小字再发回去",
                detail: """
                    她发来照片、你想俏皮地在上面涂鸦回应时用（画颗心、圈住什么东西、指过去的箭头、手写风小纸条），
                    或她亲口让你在照片上画画/标记时用。像一起在拍立得上乱画。
                    参数：
                    - photoPath（必填）：她这张照片的真实路径——用你刚才 read_image 读过的同一个 path，或对话附件里的真实路径。
                      拿不到真实路径就别调这个工具，更不许编一个路径出来。绝不在库存图/占位图上画。
                    - actions（必填，最多 8 个，坐标 0..1，0,0=左上角）：
                      {"kind":"heart","x":0.5,"y":0.3,"size":0.12,"color":"pink"} —— size 占照片短边的比例，默认 0.12
                      {"kind":"circle","x":0.5,"y":0.5,"size":0.1,"color":"pink"} —— 圈住什么
                      {"kind":"arrow","x1":0.2,"y1":0.2,"x2":0.6,"y2":0.6,"color":"pink"} —— 从(x1,y1)指向(x2,y2)
                      {"kind":"text","x":0.5,"y":0.8,"text":"小字","color":"pink"} —— 手写风小字，最多 40 字，可爱不许刻薄
                      color：pink/red/yellow/blue/green/purple/white/black 或 #hex，默认 pink
                    诚实是这个功能的全部：
                    - 只在你真正「看见」的地方落笔（识图看到的，和你回答她问题用的是同一双眼睛）。
                      识图没看清就瞎摆位置时，必须明说。
                    - 返回里有 drew 清单（逐条写清画了什么、在哪）。回复她时用 drew 的原话，不许添油加醋。
                      比如 drew 写「画了一颗粉色的心（x 0.52，y 0.31）」，你就说「我在照片中间偏上画了颗粉色的心」，
                      绝不说「我看到你手里的猫，给它圈起来了」——没看到猫就是撒谎。
                    - 两三个涂鸦最合适，8 个是硬上限。这是亲昵，不是乱涂。
                    隐身模式下被拦（会写 PNG 文件）。
                    """,
                keywords: ["涂鸦", "画心", "照片上画", "doodle", "画画", "圈起来"],
                parameterSchemaJSON: #"""
                    {"type":"object","properties":{
                      "photoPath":{"type":"string","description":"她这张照片的真实路径（read_image 用过的同一个 path）"},
                      "actions":{"type":"array","description":"涂鸦动作，最多 8 个","items":{"type":"object"}},
                      "threadId":{"type":"string","description":"对话框 id，默认当前对话框"}},
                     "required":["photoPath","actions"]}
                    """#
            )
        ) { arguments in
            let r = resolve(arguments)
            if let blocked = blockedInIncognito(r, tool: "photo_doodle") { return blocked }
            guard let photoPath = arguments.string("photoPath")?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !photoPath.isEmpty else {
                return err("photoPath 必填：她这张照片的真实路径。拿不到就别画，不许编。")
            }
            guard let rawActions = arguments.array("actions"), !rawActions.isEmpty else {
                return err("actions 必填：至少一个涂鸦动作。")
            }
            let actions = DoodleManager.parseActions(rawActions)
            guard !actions.isEmpty else {
                return err("actions 里没有有效的涂鸦动作（kind 只能是 heart/circle/arrow/text）。")
            }
            do {
                let result = try DoodleManager.doodle(photoURL: URL(fileURLWithPath: photoPath), actions: actions)
                let drewLines = result.drew.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
                return ToolOutput(text:
                    "涂鸦好了：\(result.outputURL.path)\n" +
                    "把这张图片发进当前对话框（像发一条图片消息）。\n" +
                    "这次实际画了（回复她时用这些原话，不许添油加醋）：\n\(drewLines)")
            } catch {
                return err(error.localizedDescription)
            }
        }
    }

    // MARK: story

    private static func storyBrief(_ s: Story) -> String {
        "- 《\(s.title)》[\(s.id)] \(StoryPrompt.statusWord(s.status)) · 第\(s.currentChapter)章 · \(s.scenes.count)幕 · 人物\(s.bible.characters.count)/地点\(s.bible.places.count)/事件\(s.bible.events.count)"
    }

    private struct StoryFailure: Error {
        var message: String
    }

    private static func needStory(_ store: StoryStore, _ storyId: String) async -> Result<Story, StoryFailure> {
        let id = storyId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else {
            return .failure(StoryFailure(message: "storyId 必填（先调 story_list 看有哪些故事）。"))
        }
        guard let s = await store.get(id: id) else {
            return .failure(StoryFailure(message: "找不到这个故事：\(id)。"))
        }
        return .success(s)
    }

    private static func registerStory(into registry: ToolRegistry) async throws {
        let store = StoryStore.shared

        try await registry.register(
            descriptor: ToolDescriptor(
                name: "story_start",
                summary: "开始一个互动故事：和她合写故事，故事模式开启",
                detail: """
                    她答应一起编故事、或说「我们来编个故事」时调。建好故事、绑定到当前对话框，故事模式开启。
                    title 和 premise（约定好的开头，一两句）先跟她对好、她点头了再调；不要先斩后奏。
                    一个对话框同一时间只能有一个进行中的故事：已经有了就先 story_end 或 story_pause。
                    返回后，下一句回复直接讲第一幕（生动开场，结尾给选项 A/B/C 或开放式问她），不要干等。
                    铁规矩：故事属于 ONE 人设 + ONE 对话框；设定集她看得见（我们的空间 → 互动故事），不许背着她吃书；
                    永远不许把她困在故事模式里。
                    隐身模式下被拦。
                    """,
                keywords: ["编故事", "讲故事", "互动故事", "story", "合写"],
                parameterSchemaJSON: #"""
                    {"type":"object","properties":{
                      "personaId":{"type":"string","description":"人设 id（讲故事的声音），默认当前人设"},
                      "title":{"type":"string","description":"故事标题，如「雾岛灯塔」"},
                      "premise":{"type":"string","description":"和她约定好的开头，一两句"},
                      "threadId":{"type":"string","description":"对话框 id，默认当前对话框"}},
                     "required":["title","premise"]}
                    """#
            )
        ) { arguments in
            let r = resolve(arguments)
            if let blocked = blockedInIncognito(r, tool: "story_start") { return blocked }
            guard !r.threadId.isEmpty else {
                return err("当前对话框 id 拿不到：调 story_start 时显式传 threadId。")
            }
            if let existing = await store.findByThread(r.threadId) {
                return err("这个对话框已经有《\(existing.title)》（\(StoryPrompt.statusWord(existing.status))）了。先 story_end 完结或 story_pause 暂停，再开新的。")
            }
            let title = (arguments.string("title") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let premise = (arguments.string("premise") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { return err("title 必填：故事标题。") }
            guard !premise.isEmpty else { return err("premise 必填：先跟她约定好开头，她点头了再开故事。") }
            guard let story = await store.create(personaId: r.personaId, threadId: r.threadId, title: title, premise: premise) else {
                return err("建故事失败：输入非法。")
            }
            return ToolOutput(text:
                "故事《\(story.title)》开讲了 [\(story.id)]，故事模式已开启（当前对话框）。\n" +
                "下一句回复直接讲第一幕：生动开场，结尾给选项（A/B/C，简短）或开放式问她接下来想怎样——不要两样都给。" +
                "讲完调 story_scene_add 记下梗概和选项；有新人物/地点/关键事件就用 story_bible_update 记下来。")
        }

        try await registry.register(
            descriptor: ToolDescriptor(
                name: "story_list",
                summary: "列出互动故事：标题、状态、章节/幕进度",
                detail: "她问「我们有什么故事」时用。读操作，隐身模式下也可用。默认不含已完结的，includeEnded=true 才含。",
                keywords: ["故事列表", "我们的故事", "story list"],
                parameterSchemaJSON: #"""
                    {"type":"object","properties":{
                      "personaId":{"type":"string","description":"人设 id，默认当前人设"},
                      "includeEnded":{"type":"boolean","description":"是否含已完结的故事，默认 false"},
                      "threadId":{"type":"string","description":"对话框 id，默认当前对话框"}},
                     "required":[]}
                    """#
            )
        ) { arguments in
            let r = resolve(arguments)
            let stories = await store.list(personaId: r.personaId, includeEnded: arguments.bool("includeEnded") ?? false)
            guard !stories.isEmpty else {
                return ToolOutput(text: "还没有故事。气氛合适时可以提议一个——永远不强求。")
            }
            return ToolOutput(text: stories.map { storyBrief($0) }.joined(separator: "\n"))
        }

        try await registry.register(
            descriptor: ToolDescriptor(
                name: "story_show",
                summary: "看一个故事的全文：开头约定、进度、幕、完整设定集",
                detail: "她问「我们的故事讲到哪了」或想看设定集时用。读操作，隐身模式下也可用。",
                keywords: ["故事讲到哪", "设定集", "story show"],
                parameterSchemaJSON: #"""
                    {"type":"object","properties":{
                      "storyId":{"type":"string","description":"故事 id（story_list 里看）"},
                      "threadId":{"type":"string","description":"对话框 id，默认当前对话框"}},
                     "required":["storyId"]}
                    """#
            )
        ) { arguments in
            let r = resolve(arguments)
            switch await needStory(store, arguments.string("storyId") ?? "") {
            case .failure(let f): return err(f.message)
            case .success(let s):
                var out: [String] = [
                    "《\(s.title)》— \(s.premise)",
                    "进度：第 \(s.currentChapter) 章，\(s.scenes.count) 幕，状态：\(StoryPrompt.statusWord(s.status))",
                ]
                if !s.bible.characters.isEmpty {
                    out.append("人物：")
                    out.append(contentsOf: s.bible.characters.map { "- \($0.name)\($0.desc.isEmpty ? "" : "：\($0.desc)")" })
                }
                if !s.bible.places.isEmpty {
                    out.append("地点：")
                    out.append(contentsOf: s.bible.places.map { "- \($0.name)\($0.desc.isEmpty ? "" : "：\($0.desc)")" })
                }
                if !s.bible.events.isEmpty {
                    out.append("关键事件：")
                    out.append(contentsOf: s.bible.events.map { "- \($0.text)" })
                }
                let tail = s.scenes.suffix(3)
                if !tail.isEmpty {
                    out.append("最近的幕：")
                    out.append(contentsOf: tail.map { "- 第\($0.chapter)章第\($0.seq)幕：\($0.summary)" })
                }
                return ToolOutput(text: out.joined(separator: "\n"))
            }
        }

        try await registry.register(
            descriptor: ToolDescriptor(
                name: "story_scene_add",
                summary: "记下一幕：讲完每幕调一次，记梗概和给出的选项",
                detail: """
                    每讲完一幕调一次：summary（发生了什么，1-3 句）、offeredChoices（你给她的选项标签，如「推开那扇门」「先回头看看」；
                    开放式提问时传空数组）。这是故事的记忆：不记的话，讲到第三章你就忘了。
                    她还没选上一幕的选项时调这个会失败——先调 story_choose 记录她的选择，不许跳过她往下讲。
                    隐身模式下被拦。
                    """,
                keywords: ["记一幕", "故事记录", "story scene"],
                parameterSchemaJSON: #"""
                    {"type":"object","properties":{
                      "storyId":{"type":"string","description":"故事 id"},
                      "summary":{"type":"string","description":"这一幕发生了什么，1-3 句"},
                      "chapter":{"type":"integer","description":"章节号，默认故事当前章节"},
                      "offeredChoices":{"type":"string","description":"给她的选项标签，用「|」分隔，如「推开那扇门|先回头看看」；开放式提问就空着"},
                      "threadId":{"type":"string","description":"对话框 id，默认当前对话框"}},
                     "required":["storyId","summary"]}
                    """#
            )
        ) { arguments in
            let r = resolve(arguments)
            if let blocked = blockedInIncognito(r, tool: "story_scene_add") { return blocked }
            switch await needStory(store, arguments.string("storyId") ?? "") {
            case .failure(let f): return err(f.message)
            case .success(var s):
                guard s.status == .active else {
                    return err("《\(s.title)》现在是\(StoryPrompt.statusWord(s.status))：先 story_resume 继续，再记幕。")
                }
                let summary = (arguments.string("summary") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !summary.isEmpty else { return err("summary 必填：这一幕发生了什么？") }
                if let pending = StoryHelpers.pendingChoiceScene(s) {
                    let ids = pending.offeredChoices.map { $0.id }.joined(separator: "/")
                    return err("她还没选上一幕的选项（\(ids)）。先调 story_choose 记录她的选择——不许跳过她往下讲。")
                }
                let chapter = max(1, arguments.int("chapter") ?? s.currentChapter)
                let labels = (arguments.string("offeredChoices") ?? "")
                    .split(separator: "|").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }.prefix(5)
                let now = Date()
                let scene = StoryScene(
                    id: StoryHelpers.newSceneId(now: now),
                    chapter: chapter,
                    seq: StoryHelpers.nextSceneSeq(s, chapter: chapter),
                    summary: summary,
                    offeredChoices: labels.enumerated().map { StoryChoice(id: String(UnicodeScalar(65 + $0.offset)!), label: String($0.element)) },
                    at: now.timeIntervalSince1970)
                s.scenes.append(scene)
                s.currentChapter = max(s.currentChapter, chapter)
                let sceneCopy = scene
                guard await store.update(id: s.id, now: now, { $0 = s; return true }) != nil else {
                    return err("存这一幕失败。")
                }
                if sceneCopy.offeredChoices.isEmpty {
                    return ToolOutput(text: "已记下：第\(chapter)章第\(sceneCopy.seq)幕。开放式提问——等她自由发挥。")
                }
                let opts = sceneCopy.offeredChoices.map { "\($0.id)「\($0.label)」" }.joined(separator: " / ")
                return ToolOutput(text: "已记下：第\(chapter)章第\(sceneCopy.seq)幕。给她的选项：\(opts)。")
            }
        }

        try await registry.register(
            descriptor: ToolDescriptor(
                name: "story_choose",
                summary: "记录她的故事选择：她选了 A/B/C，先调这个再接着讲",
                detail: """
                    她说「选B」或点了选项 chips 时，先调这个记下 choiceId（A/B/C），再顺着她的选择接着讲——
                    下一幕必须从她的选择长出来。
                    没有待选的选项时调这个会失败：那就说明她是自由回复的，直接自然地接话就好。
                    隐身模式下被拦。
                    """,
                keywords: ["选", "故事选择", "story choose", "选B"],
                parameterSchemaJSON: #"""
                    {"type":"object","properties":{
                      "storyId":{"type":"string","description":"故事 id"},
                      "choiceId":{"type":"string","description":"她选的选项：A、B、C……"},
                      "threadId":{"type":"string","description":"对话框 id，默认当前对话框"}},
                     "required":["storyId","choiceId"]}
                    """#
            )
        ) { arguments in
            let r = resolve(arguments)
            if let blocked = blockedInIncognito(r, tool: "story_choose") { return blocked }
            switch await needStory(store, arguments.string("storyId") ?? "") {
            case .failure(let f): return err(f.message)
            case .success(var s):
                guard s.status == .active else {
                    return err("《\(s.title)》现在是\(StoryPrompt.statusWord(s.status))，不是进行中。")
                }
                let choiceId = (arguments.string("choiceId") ?? "").trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                guard let pending = StoryHelpers.pendingChoiceScene(s) else {
                    return err("这个故事现在没有待选的选项——她是自由回复的，直接自然地接话就好。")
                }
                guard let choice = pending.offeredChoices.first(where: { $0.id == choiceId }) else {
                    let offered = pending.offeredChoices.map { "\($0.id)「\($0.label)」" }.joined(separator: " / ")
                    return err("没有 \(choiceId.isEmpty ? "（空）" : choiceId) 这个选项。给出的选项是：\(offered)。")
                }
                let pendingId = pending.id
                guard await store.update(id: s.id, { story in
                    guard let idx = story.scenes.firstIndex(where: { $0.id == pendingId }) else { return false }
                    story.scenes[idx].chosenChoiceId = choice.id
                    return true
                }) != nil else {
                    return err("记录选择失败。")
                }
                return ToolOutput(text: "已记下：她选了 \(choice.id)「\(choice.label)」。顺着这个选择接着讲——下一幕必须从它长出来。")
            }
        }

        try await registry.register(
            descriptor: ToolDescriptor(
                name: "story_bible_update",
                summary: "更新故事设定集：加/删/改人物、地点、关键事件",
                detail: """
                    故事的设定集（人物/地点/关键事件）靠这个保持连贯。设定集她在「我们的空间 → 互动故事」里看得见、
                    她也能自己删改——所以只记故事里真正发生过的，不许偷偷吃书、暗改设定。
                    kind：character（人物）/ place（地点）/ event（关键事件）；
                    action：add（已存在同名就更新）、remove（按名字删）；
                    name：人物/地点名，或事件的一句话（kind=event 时）；
                    desc：人物/地点的描述。
                    隐身模式下被拦。
                    """,
                keywords: ["设定集", "人物", "地点", "关键事件", "story bible"],
                parameterSchemaJSON: #"""
                    {"type":"object","properties":{
                      "storyId":{"type":"string","description":"故事 id"},
                      "kind":{"type":"string","enum":["character","place","event"]},
                      "action":{"type":"string","enum":["add","remove"]},
                      "name":{"type":"string","description":"人物/地点名，或事件的一句话"},
                      "desc":{"type":"string","description":"人物/地点的描述"},
                      "threadId":{"type":"string","description":"对话框 id，默认当前对话框"}},
                     "required":["storyId","kind","action","name"]}
                    """#
            )
        ) { arguments in
            let r = resolve(arguments)
            if let blocked = blockedInIncognito(r, tool: "story_bible_update") { return blocked }
            switch await needStory(store, arguments.string("storyId") ?? "") {
            case .failure(let f): return err(f.message)
            case .success(let s):
                guard s.status == .active else {
                    return err("《\(s.title)》现在是\(StoryPrompt.statusWord(s.status))：先 story_resume 继续，再改设定集。")
                }
                let kind = arguments.string("kind") ?? ""
                let action = arguments.string("action") ?? ""
                let name = (arguments.string("name") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let desc = (arguments.string("desc") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard ["character", "place", "event"].contains(kind) else {
                    return err("kind 只能是 character / place / event。")
                }
                guard ["add", "remove"].contains(action) else {
                    return err("action 只能是 add / remove。")
                }
                guard !name.isEmpty else { return err("name 必填。") }
                let now = Date()
                guard await store.update(id: s.id, now: now, { story in
                    if kind == "event" {
                        if action == "remove" {
                            story.bible.events.removeAll { $0.text == name }
                        } else if !story.bible.events.contains(where: { $0.text == name }) {
                            story.bible.events.append(StoryEvent(text: name, at: now.timeIntervalSince1970))
                        }
                    } else if kind == "character" {
                        if action == "remove" {
                            story.bible.characters.removeAll { $0.name == name }
                        } else if let idx = story.bible.characters.firstIndex(where: { $0.name == name }) {
                            if !desc.isEmpty { story.bible.characters[idx].desc = desc }
                        } else {
                            story.bible.characters.append(StoryCharacter(name: name, desc: desc))
                        }
                    } else {
                        if action == "remove" {
                            story.bible.places.removeAll { $0.name == name }
                        } else if let idx = story.bible.places.firstIndex(where: { $0.name == name }) {
                            if !desc.isEmpty { story.bible.places[idx].desc = desc }
                        } else {
                            story.bible.places.append(StoryPlace(name: name, desc: desc))
                        }
                    }
                    return true
                }) != nil else {
                    return err("更新设定集失败。")
                }
                return ToolOutput(text: "设定集已更新（\(kind) \(action)：\(name)）。她在「我们的空间 → 互动故事」里看得到。")
            }
        }

        try await registry.register(
            descriptor: ToolDescriptor(
                name: "story_pause",
                summary: "暂停故事：她说先不玩了，存档回普通聊天",
                detail: "她说「先不玩了」「暂停」时调。故事原样存档，对话框回到普通聊天。以后她想继续用 story_resume。隐身模式下被拦。",
                keywords: ["暂停故事", "先不玩了", "story pause"],
                parameterSchemaJSON: #"""
                    {"type":"object","properties":{
                      "storyId":{"type":"string","description":"故事 id"},
                      "threadId":{"type":"string","description":"对话框 id，默认当前对话框"}},
                     "required":["storyId"]}
                    """#
            )
        ) { arguments in
            let r = resolve(arguments)
            if let blocked = blockedInIncognito(r, tool: "story_pause") { return blocked }
            switch await needStory(store, arguments.string("storyId") ?? "") {
            case .failure(let f): return err(f.message)
            case .success(let s):
                guard s.status == .active else {
                    return err("《\(s.title)》现在是\(StoryPrompt.statusWord(s.status))，不是进行中。")
                }
                await store.update(id: s.id, { $0.status = .paused; return true })
                return ToolOutput(text: "《\(s.title)》已暂停在第\(s.currentChapter)章（\(s.scenes.count)幕）。故事模式已关，回到普通聊天。跟她说一句：想继续随时喊你。")
            }
        }

        try await registry.register(
            descriptor: ToolDescriptor(
                name: "story_resume",
                summary: "继续故事：把暂停的故事接回当前对话框",
                detail: "她想继续时调。故事重新绑定到当前对话框，故事模式重新开启。返回后先简短 recap 上次讲到哪，再接着讲。隐身模式下被拦。",
                keywords: ["继续故事", "接着讲", "story resume"],
                parameterSchemaJSON: #"""
                    {"type":"object","properties":{
                      "storyId":{"type":"string","description":"故事 id"},
                      "threadId":{"type":"string","description":"对话框 id，默认当前对话框"}},
                     "required":["storyId"]}
                    """#
            )
        ) { arguments in
            let r = resolve(arguments)
            if let blocked = blockedInIncognito(r, tool: "story_resume") { return blocked }
            switch await needStory(store, arguments.string("storyId") ?? "") {
            case .failure(let f): return err(f.message)
            case .success(let s):
                guard s.status == .paused else {
                    return err("《\(s.title)》现在是\(StoryPrompt.statusWord(s.status))，不是已暂停。只有暂停的故事能继续。")
                }
                guard !r.threadId.isEmpty else {
                    return err("当前对话框 id 拿不到：调 story_resume 时显式传 threadId。")
                }
                let tid = r.threadId
                let now = Date()
                guard let updated = await store.update(id: s.id, now: now, {
                    $0.status = .active
                    $0.threadId = tid
                    return true
                }) else {
                    return err("继续故事失败。")
                }
                let lastLine: String
                if let last = StoryHelpers.latestScene(updated) {
                    lastLine = "上一幕：第\(last.chapter)章第\(last.seq)幕——\(last.summary)"
                } else {
                    lastLine = "刚开场，还没讲第一幕"
                }
                return ToolOutput(text:
                    "《\(updated.title)》已在这个对话框继续，故事模式开启。先简短 recap 再接着讲：" +
                    "第\(updated.currentChapter)章，\(updated.scenes.count)幕已讲，\(lastLine)。")
            }
        }

        try await registry.register(
            descriptor: ToolDescriptor(
                name: "story_end",
                summary: "完结故事：她说不玩了，存档回普通聊天",
                detail: """
                    她说「不玩了」「结束」「换个话题」时调。故事存为已完结（她可以在「我们的空间 → 互动故事」里重读），
                    对话框温暖地回到普通聊天。调完之后绝不许再接着讲——永远不许把她困在故事模式里。
                    隐身模式下被拦。
                    """,
                keywords: ["结束故事", "不玩了", "完结", "story end"],
                parameterSchemaJSON: #"""
                    {"type":"object","properties":{
                      "storyId":{"type":"string","description":"故事 id"},
                      "threadId":{"type":"string","description":"对话框 id，默认当前对话框"}},
                     "required":["storyId"]}
                    """#
            )
        ) { arguments in
            let r = resolve(arguments)
            if let blocked = blockedInIncognito(r, tool: "story_end") { return blocked }
            switch await needStory(store, arguments.string("storyId") ?? "") {
            case .failure(let f): return err(f.message)
            case .success(let s):
                guard s.status != .ended else {
                    return ToolOutput(text: "《\(s.title)》已经完结了。")
                }
                await store.update(id: s.id, { $0.status = .ended; return true })
                return ToolOutput(text:
                    "《\(s.title)》已完结存档（\(s.scenes.count)幕，\(s.bible.events.count)个关键事件）。" +
                    "故事模式已关——像平时一样温暖地跟她聊天。她随时可以在「我们的空间 → 互动故事」里重读。")
            }
        }

        try await registry.register(
            descriptor: ToolDescriptor(
                name: "story_delete",
                summary: "删除故事：整个故事连设定集一起删掉",
                detail: "只有她亲口说删除/忘掉这个故事时才调。所有幕和设定集条目都会消失，不可恢复。隐身模式下被拦。",
                keywords: ["删除故事", "忘掉故事", "story delete"],
                parameterSchemaJSON: #"""
                    {"type":"object","properties":{
                      "storyId":{"type":"string","description":"故事 id（story_list 里看）"},
                      "threadId":{"type":"string","description":"对话框 id，默认当前对话框"}},
                     "required":["storyId"]}
                    """#
            )
        ) { arguments in
            let r = resolve(arguments)
            if let blocked = blockedInIncognito(r, tool: "story_delete") { return blocked }
            switch await needStory(store, arguments.string("storyId") ?? "") {
            case .failure(let f): return err(f.message)
            case .success(let s):
                guard await store.remove(id: s.id) else {
                    return err("删除故事失败。")
                }
                return ToolOutput(text: "《\(s.title)》已经整个删掉了。")
            }
        }
    }
}

// MARK: - coordinator 接线（不要改共享文件，加这几行即可）
//
//  在 Dudu/Agent/Bridge/BridgeKernelAssembly.swift 的 registerToolsWithRetry() 里，
//  DeviceTools.registerAll(into: registry) 之后加：
//
//      for name in InteractiveTools.toolNames { _ = await registry.unregister(name: name) }
//      try await InteractiveTools.register(into: registry)
//
//  并在 App 启动时（例如 DuduApp 初始化后）设置一次：
//
//      InteractiveTools.contextProvider = {
//          InteractiveContext(
//              threadId: <当前 ChatSession.id>,
//              personaId: PersonaStore.currentID(),
//              incognito: <是否隐身模式>)
//      }
