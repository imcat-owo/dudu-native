//
//  D20a (2026-10-08): proactive AI tools （自发帖 / 每日心情 / 次日跟进）.
//
//  Registration shape follows MusicDJTools: `toolNames` + `register(into:)`.
//  The coordinator adds the registration lines to DeviceTools.swift —
//  this file must NOT be edited into any shared registry by a builder.
//
//  Iron rules enforced mechanically here:
//  - Write tools (selfpost_config, selfpost_post_now, selfpost_publish,
//    moodcheck_record/delete/set_config, followup_add/delete/set_enabled)
//    refuse in incognito — incognito promises no side effects.
//  - Config that only SHE may change (selfpost enabled/slots/cap,
//    moodcheck hour/enabled, followup master toggle) requires
//    confirm=true, and the tool descriptions forbid calling it without her
//    explicit request in THIS conversation. The AI NEVER enables self-post,
//    raises caps, or adds slots unprompted.
//  - Copy iron rule: never imply she just sent a request （你刚才说/收到
//    are forbidden). Templates live in ProactiveNotificationScheduler.

import BridgeCore
import Foundation

enum ProactiveTools {
    static let toolNames: [String] = [
        "selfpost_config",
        "selfpost_status",
        "selfpost_log",
        "selfpost_post_now",
        "selfpost_publish",
        "moodcheck_record",
        "moodcheck_list",
        "moodcheck_delete",
        "moodcheck_set_config",
        "followup_add",
        "followup_list",
        "followup_delete",
        "followup_set_config",
    ]

    static func register(into registry: ToolRegistry) async throws {
        for (_, descriptor, handler) in toolDefs() {
            try await registry.register(descriptor: descriptor, handler: handler)
        }
    }

    // MARK: - Definitions

    private typealias Def = (String, ToolDescriptor, ToolHandler)

    private static func toolDefs() -> [Def] {
        [
            // ---- self-post ----
            def(
                "selfpost_config",
                summary: "自发帖：读/改配置（改配置只有她能点头）",
                detail: """
                    不传参数 = 只读当前配置。改配置（enabled/slots/daily_cap 任一）\
                    必须传 confirm=true，且只能在她本轮对话里明确同意之后调用。\
                    AI 绝不擅自打开自发帖、提高上限、增加时段——这是死规矩。\
                    slots 1–5 个小时（上海时间，绝不能落在 06:00–16:00 她睡觉的时间）；\
                    daily_cap 0–3。incognito 下写操作被拒绝。
                    """,
                keywords: ["自发帖", "自己发动态", "selfpost", "主动发帖"],
                schema: #"""
                    {"type":"object","properties":{
                      "enabled":{"type":"boolean","description":"总开关"},
                      "slots":{"type":"array","items":{"type":"integer"},"description":"安静时段（小时，上海时间），1-5个"},
                      "daily_cap":{"type":"integer","description":"每日上限，0-3"},
                      "confirm":{"type":"boolean","description":"她已明确同意改配置时传 true"}},
                     "additionalProperties":false}
                    """#
            ) { args in
                let mgr = await SelfPostManager.shared
                let hasWrite = args.bool("enabled") != nil
                    || args.contains("slots") || args.int("daily_cap") != nil
                if !hasWrite {
                    let c = await mgr.config
                    let slots = c.slotHours.map(String.init).joined(separator: ",")
                    return ToolOutput(text:
                        "自发帖配置：开关\(c.enabled ? "开" : "关")，时段 \(slots)（上海时间），" +
                        "每日上限 \(c.dailyCap)，今日已发 \(await mgr.postsCountToday())。")
                }
                if let denied = await denyIfIncognito(tool: "selfpost_config") {
                    return denied
                }
                guard args.bool("confirm") == true else {
                    return ToolOutput(text:
                        "自发帖配置只能她改：请先问她，得到明确同意后再带 confirm=true 调用。" +
                        "AI 绝不擅自开、擅自加时段、擅自提上限。", isError: true)
                }
                var slots: [Int]? = nil
                if let arr = args.array("slots") {
                    slots = arr.compactMap { ($0 as? NSNumber)?.intValue }
                }
                if let msg = await mgr.validate(slots: slots, dailyCap: args.int("daily_cap")) {
                    return ToolOutput(text: msg, isError: true)
                }
                await mgr.updateConfig(byHer: true) { c in
                    if let e = args.bool("enabled") { c.enabled = e }
                    if let s = slots { c.slotHours = s }
                    if let cap = args.int("daily_cap") { c.dailyCap = cap }
                }
                let c = await mgr.config
                return ToolOutput(text:
                    "已按她的要求更新：开关\(c.enabled ? "开" : "关")，" +
                    "时段 \(c.slotHours.map(String.init).joined(separator: ","))，" +
                    "每日上限 \(c.dailyCap)。")
            },

            def(
                "selfpost_status",
                summary: "自发帖：今日时段与发帖数（只读）",
                detail: "返回今日各时段状态（已触发/待触发/已过期）与今日发帖数 vs 上限。",
                keywords: ["自发帖", "状态", "selfpost", "今天发了几条"],
                schema: #"""
                    {"type":"object","properties":{},"additionalProperties":false}
                    """#
            ) { _ in
                let mgr = await SelfPostManager.shared
                let c = await mgr.config
                let key = ProactiveClock.dateKey()
                let now = Date()
                var lines: [String] = []
                for h in c.slotHours.sorted() {
                    guard let fire = ProactiveClock.date(hour: h, on: key) else { continue }
                    let state: String
                    if await mgr.isSlotFired(hour: h, dateKey: key) {
                        state = "已触发"
                    } else if now >= fire.addingTimeInterval(15 * 60) {
                        state = "已过期（静默消费）"
                    } else if now >= fire {
                        state = "等待中（15 分钟宽限内）"
                    } else {
                        state = "未到"
                    }
                    lines.append("\(h):00 \(state)")
                }
                return ToolOutput(text:
                    "自发帖（开关\(c.enabled ? "开" : "关")）：今日已发 \(await mgr.postsCountToday()) / 上限 \(c.dailyCap)。\n" +
                    lines.joined(separator: "\n"))
            },

            def(
                "selfpost_log",
                summary: "自发帖：AI 今天想发没发（决策日志，只读）",
                detail: "她可以在我们的空间看到同一份日志。返回最近 20 条，新的在前。",
                keywords: ["自发帖", "日志", "想发没发", "selfpost"],
                schema: #"""
                    {"type":"object","properties":{},"additionalProperties":false}
                    """#
            ) { _ in
                let mgr = await SelfPostManager.shared
                let items = await mgr.todaysDecisions().prefix(20)
                if items.isEmpty {
                    return ToolOutput(text: "今天还没有自发帖相关的决策记录。")
                }
                return ToolOutput(text: items.map {
                    "\(ProactiveClock.hourMinute(of: Date(timeIntervalSince1970: $0.at))) [\($0.kind)] \($0.text)"
                }.joined(separator: "\n"))
            },

            def(
                "selfpost_post_now",
                summary: "自发帖：现在问一次模型要不要发（闸门先行）",
                detail: """
                    确定性闸门先跑：没过就静默跳过并记日志，不打扰她。过了才返回\
                    「你可以决定了」的指令——由你在上下文里决定发还是 SKIP。\
                    想发就把文案交给 selfpost_publish；不想发就停，不发不算错。\
                    incognito 下被拒绝。
                    """,
                keywords: ["自发帖", "现在发", "selfpost", "发动态"],
                schema: #"""
                    {"type":"object","properties":{},"additionalProperties":false}
                    """#
            ) { _ in
                if let denied = await denyIfIncognito(tool: "selfpost_post_now") {
                    return denied
                }
                let mgr = await SelfPostManager.shared
                let cfg = await mgr.config
                guard cfg.enabled else {
                    return ToolOutput(text: "自发帖没开。只有她能打开——你不能擅自开。")
                }
                if await mgr.postsCountToday() >= cfg.dailyCap {
                    await mgr.logDecision(kind: "skip", text: "手动触发：今日已达上限，不发")
                    return ToolOutput(text: "今日自发帖已达上限（\(cfg.dailyCap)），这次不发。已记入日志。")
                }
                switch await ProactiveEngine.shared.gate(kind: "selfpost") {
                case .veto(let reason):
                    await mgr.logDecision(kind: "veto", text: "手动触发：\(reason)")
                    return ToolOutput(text: "闸门没过：\(reason)。静默跳过，已记入日志。")
                case .allow:
                    return ToolOutput(text:
                        "闸门已过。现在你决定：你现在真心想发一条动态吗？" +
                        "想发就把文案交给 selfpost_publish（copy=你的文案）；" +
                        "不想发就直接停——SKIP 是安静的，不算错，不要勉强。")
                }
            },

            def(
                "selfpost_publish",
                summary: "自发帖：发布你写好的文案（闸门再验）",
                detail: """
                    copy=你决定的文案原文。发布前闸门再验一次；任一环节不过就静默\
                    记日志。发布走 Our Space 动态流管道（作者标 ai，清楚是 AI 自己发的）。\
                    管道没接好时如实报错，绝不假装发布成功。incognito 下被拒绝。
                    """,
                keywords: ["自发帖", "发布", "selfpost", "publish"],
                schema: #"""
                    {"type":"object","properties":{
                      "copy":{"type":"string","description":"要发的文案原文（必填）"}},
                     "required":["copy"],"additionalProperties":false}
                    """#
            ) { args in
                if let denied = await denyIfIncognito(tool: "selfpost_publish") {
                    return denied
                }
                let copy = args.string("copy") ?? ""
                let mgr = await SelfPostManager.shared
                switch await mgr.publish(copy: copy) {
                case .success(let msg):
                    return ToolOutput(text: msg)
                case .failure(let err):
                    return ToolOutput(text: "没发出去：\(err.localizedDescription)", isError: true)
                }
            },

            // ---- mood check-in ----
            def(
                "moodcheck_record",
                summary: "每日心情：记下她的心情（她说的每次都记）",
                detail: """
                    她回答每日心情、或在聊天里随口说心情（我今天好累），都调这个记下来。\
                    mood=她的原话、简短；note=可选的补充、也是她的原话。一天一条：\
                    同一天记两次会更新今天那条，绝不重复。难受的日子会顺手变成一条记忆，\
                    方便以后自然提起；好日子只留在时间线。incognito 下被拒绝\
                    （无痕模式承诺不留痕，记心情就是撒谎）。
                    """,
                keywords: ["心情", "mood", "她今天怎么样", "累", "开心"],
                schema: #"""
                    {"type":"object","properties":{
                      "mood":{"type":"string","description":"她的原话，简短（必填）"},
                      "note":{"type":"string","description":"补充，她的原话"},
                      "date_key":{"type":"string","description":"yyyy-MM-dd，默认今天（上海）"},
                      "source":{"type":"string","enum":["checkin","chat"],"description":"默认 chat"}},
                     "required":["mood"],"additionalProperties":false}
                    """#
            ) { args in
                if let denied = await denyIfIncognito(tool: "moodcheck_record") {
                    return denied
                }
                guard let mood = args.string("mood"),
                      !mood.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    return ToolOutput(text: "mood 是空的，没记。", isError: true)
                }
                let mgr = await MoodCheckInManager.shared
                let entry = await mgr.record(
                    mood: mood,
                    note: args.string("note") ?? "",
                    source: args.string("source") ?? "chat",
                    dateKey: args.string("date_key")
                )
                return ToolOutput(text: "记下了：\(entry.dateKey) 她说「\(entry.mood)」。已上她的心情时间线。")
            },

            def(
                "moodcheck_list",
                summary: "每日心情：她的心情时间线（新的在前，只读）",
                detail: "她问起最近怎么样、或你想自然提起她某天很累时用。incognito 下也可用（只读）。",
                keywords: ["心情", "时间线", "mood", "最近怎么样"],
                schema: #"""
                    {"type":"object","properties":{
                      "limit":{"type":"integer","description":"最多返回条数，默认 14"}},
                     "additionalProperties":false}
                    """#
            ) { args in
                let mgr = await MoodCheckInManager.shared
                let limit = args.int("limit") ?? 14
                let items = await mgr.timeline().prefix(max(1, limit))
                if items.isEmpty {
                    return ToolOutput(text: "心情时间线还是空的，还没记过。")
                }
                return ToolOutput(text: items.map {
                    "\($0.dateKey)：\($0.mood)" + ($0.note.isEmpty ? "" : "（\($0.note)）")
                }.joined(separator: "\n"))
            },

            def(
                "moodcheck_delete",
                summary: "每日心情：删掉某一天的记录（她让忘就忘）",
                detail: "date_key=yyyy-MM-dd。incognito 下被拒绝。",
                keywords: ["心情", "删除", "忘记", "mood"],
                schema: #"""
                    {"type":"object","properties":{
                      "date_key":{"type":"string","description":"yyyy-MM-dd（必填）"}},
                     "required":["date_key"],"additionalProperties":false}
                    """#
            ) { args in
                if let denied = await denyIfIncognito(tool: "moodcheck_delete") {
                    return denied
                }
                guard let key = args.string("date_key") else {
                    return ToolOutput(text: "要传 date_key。", isError: true)
                }
                let mgr = await MoodCheckInManager.shared
                await mgr.delete(dateKey: key)
                return ToolOutput(text: "\(key) 的心情记录删掉了。")
            },

            def(
                "moodcheck_set_config",
                summary: "每日心情：开关 / 改她的时间（只有她能定）",
                detail: """
                    hour 只能是她的时间（上海），绝不能是 06:00–16:00（她在睡觉）——\
                    传了那个区间会被拒绝，请给她换个晚上的时间。改配置必须传 confirm=true，\
                    且只能在她本轮对话里明确同意之后调用。incognito 下写操作被拒绝。
                    """,
                keywords: ["心情", "check-in", "几点问", "mood"],
                schema: #"""
                    {"type":"object","properties":{
                      "enabled":{"type":"boolean"},
                      "hour":{"type":"integer","description":"上海时间小时，0-23，不能是 6-16"},
                      "confirm":{"type":"boolean","description":"她已明确同意时传 true"}},
                     "additionalProperties":false}
                    """#
            ) { args in
                if args.bool("enabled") == nil && args.int("hour") == nil {
                    let mgr = await MoodCheckInManager.shared
                    let c = await mgr.config
                    return ToolOutput(text: "每日心情：开关\(c.enabled ? "开" : "关")，时间 \(c.hour):00（上海）。")
                }
                if let denied = await denyIfIncognito(tool: "moodcheck_set_config") {
                    return denied
                }
                guard args.bool("confirm") == true else {
                    return ToolOutput(text: "每日心情的设置只能她改：请先问她，同意后再带 confirm=true 调用。",
                                      isError: true)
                }
                let mgr = await MoodCheckInManager.shared
                if let h = args.int("hour") {
                    let ok = await mgr.setHour(h)
                    if !ok {
                        return ToolOutput(text: "她 \(h):00 在睡觉，这个时间不行。给她换个晚上的时间（比如 20 点）吧。",
                                          isError: true)
                    }
                }
                if let e = args.bool("enabled") { await mgr.setEnabled(e) }
                let c = await mgr.config
                return ToolOutput(text: "已按她的要求更新：开关\(c.enabled ? "开" : "关")，时间 \(c.hour):00（上海）。")
            },

            // ---- follow-up ----
            def(
                "followup_add",
                summary: "次日跟进：记下她提到的将来的事（她说的才记）",
                detail: """
                    她提到有日期的事（我明天有个面试）时调这个记下来——这是她亲口告诉你的，\
                    像写在小本子上。记下之后必须亲口告诉她你在跟这件事\
                    （比如：记下了，后天问你结果怎么样），绝不偷偷跟。\
                    事件第二天 17:00（上海，她的早上）问一次，只问一次，走主动闸门。\
                    如果她后来在聊天里自己提到了，这条会自动取消。\
                    绝不凭空编造跟进事项。incognito 下被拒绝。
                    """,
                keywords: ["跟进", "明天", "记得问", "followup", "面试", "看牙"],
                schema: #"""
                    {"type":"object","properties":{
                      "text":{"type":"string","description":"她说的事，她的原话（必填）"},
                      "event_date":{"type":"string","description":"事件日期 yyyy-MM-dd，上海（必填）"}},
                     "required":["text","event_date"],"additionalProperties":false}
                    """#
            ) { args in
                if let denied = await denyIfIncognito(tool: "followup_add") {
                    return denied
                }
                guard let text = args.string("text"), !text.isEmpty,
                      let date = args.string("event_date"), !date.isEmpty else {
                    return ToolOutput(text: "要传 text 和 event_date（yyyy-MM-dd）。", isError: true)
                }
                let mgr = await FollowUpManager.shared
                do {
                    let item = try await mgr.add(text: text, eventDateKey: date)
                    let fire = item.fireDate.map { ProactiveClock.hourMinute(of: $0) } ?? "？"
                    let fireDay = item.fireDate.map { ProactiveClock.dateKey(of: $0) } ?? "？"
                    return ToolOutput(text:
                        "记下了：\(fireDay) \(fire)（上海）会问她一次。记得亲口告诉她你在跟这件事，" +
                        "别让它悄悄发生。")
                } catch {
                    return ToolOutput(text: "没记下来：\(error.localizedDescription)", isError: true)
                }
            },

            def(
                "followup_list",
                summary: "次日跟进：在跟的事列表（只读）",
                detail: "返回正在跟进的事项（待触发的在前）。她问起、或你想确认要不要取消时用。incognito 下也可用（只读）。",
                keywords: ["跟进", "在跟什么", "followup"],
                schema: #"""
                    {"type":"object","properties":{},"additionalProperties":false}
                    """#
            ) { _ in
                let mgr = await FollowUpManager.shared
                let items = await mgr.pendingItems()
                if items.isEmpty {
                    return ToolOutput(text: "现在没有在跟进的事。")
                }
                return ToolOutput(text: items.map { item in
                    let fire = item.fireDate.map {
                        "\(ProactiveClock.dateKey(of: $0)) \(ProactiveClock.hourMinute(of: $0))"
                    } ?? "时间未知"
                    return "[\(item.id.prefix(6))] \(item.text)（事件 \(item.eventDateKey)，\(fire) 上海问一次）"
                }.joined(separator: "\n"))
            },

            def(
                "followup_delete",
                summary: "次日跟进：删掉一条（她让删、或她已经告诉你了）",
                detail: "她让删就删；她在聊天里已经告诉你结果了，你也可以主动删（别再问她已经说过的事）。incognito 下被拒绝。",
                keywords: ["跟进", "删除", "不用问了", "followup"],
                schema: #"""
                    {"type":"object","properties":{
                      "id":{"type":"string","description":"followup_list 里 id 的前 6 位或完整 id（必填）"}},
                     "required":["id"],"additionalProperties":false}
                    """#
            ) { args in
                if let denied = await denyIfIncognito(tool: "followup_delete") {
                    return denied
                }
                guard let raw = args.string("id"), !raw.isEmpty else {
                    return ToolOutput(text: "要传 id。", isError: true)
                }
                let mgr = await FollowUpManager.shared
                if let item = await mgr.items.first(where: { $0.id == raw || $0.id.hasPrefix(raw) }) {
                    await mgr.delete(id: item.id)
                    return ToolOutput(text: "删掉了：\(item.text)。不会再问。")
                }
                return ToolOutput(text: "没找到这条跟进。", isError: true)
            },

            def(
                "followup_set_config",
                summary: "次日跟进：总开关（只有她能定）",
                detail: "不传参数=只读。改开关必须传 confirm=true，且只能在她本轮对话里明确同意之后调用。incognito 下写操作被拒绝。",
                keywords: ["跟进", "开关", "followup"],
                schema: #"""
                    {"type":"object","properties":{
                      "enabled":{"type":"boolean"},
                      "confirm":{"type":"boolean","description":"她已明确同意时传 true"}},
                     "additionalProperties":false}
                    """#
            ) { args in
                let mgr = await FollowUpManager.shared
                if args.bool("enabled") == nil {
                    let on = await mgr.masterEnabled
                    return ToolOutput(text: "次日跟进总开关：\(on ? "开" : "关")。")
                }
                if let denied = await denyIfIncognito(tool: "followup_set_config") {
                    return denied
                }
                guard args.bool("confirm") == true else {
                    return ToolOutput(text: "次日跟进的开关只能她定：请先问她，同意后再带 confirm=true 调用。",
                                      isError: true)
                }
                // Property assignment is rejected from @Sendable closures; hop via
                // the isolated mutator instead of awaiting the setter directly.
                await mgr.setMasterEnabled(args.bool("enabled") ?? true)
                let on2 = await mgr.masterEnabled
                return ToolOutput(text: "已按她的要求：次日跟进\(on2 ? "开" : "关")。")
            },
        ]
    }

    // MARK: - helpers

    private static func def(
        _ name: String,
        summary: String,
        detail: String = "",
        keywords: [String] = [],
        schema: String,
        handler: @escaping ToolHandler
    ) -> Def {
        (name, ToolDescriptor(name: name, summary: summary, detail: detail,
                              keywords: keywords, parameterSchemaJSON: schema), handler)
    }

    /// Write tools refuse in incognito. Returns nil when allowed.
    private static func denyIfIncognito(tool: String) async -> ToolOutput? {
        let isIncognito = await ProactiveEngine.shared.incognito
        guard !isIncognito else {
            return ToolOutput(
                text: "\(tool) 在无痕模式下不可用：无痕模式承诺不留痕，不做任何主动打扰或记录。",
                isError: true)
        }
        return nil
    }
}
