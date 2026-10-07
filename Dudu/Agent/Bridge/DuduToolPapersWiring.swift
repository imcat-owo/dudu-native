import Foundation

// MARK: - DuduToolPapersWiring (D10, 2026-10-07)
//
// 工具纸条机制（ENGINE ONLY，无 UI），设计遵循 ToolPapers.md 的口径：
// 纸条是注册好的、分条下发；按对话"话题"匹配（软提示、不是死关键词锁定）；
// 话题相关时才塞进 agent loop 的 system prompt；AI 被明确告知它已经读过哪
// 些纸条，所以同一纸条一会话只下发一次，不重复塞。
//
// 纸条内容来源与适配（诚实映射）：
// - 设计文档：~/workspace/openminis-fix/repo/src/ios/Agent/Bridge/ToolPapers.md
//   （OpenMinis 的 9 张纸条，讲的是「搜/命令」后面那批设备工具）。
// - dudu-native 的实际工具行为以本仓代码为准，纸条按实测逐条校准过，
//   与原文档有出入的地方以本仓为准（差异见各纸条正文里的标注），不照抄过期描述：
//   1. device_clipboard：本仓只有 set/clear/status，读剪贴板拆成了独立的
//      device_clipboard_read（敏感，需主人确认）。原文档的 action=get 已失效。
//   2. device_location：本仓只有 geocode/forward，查当前位置拆成了独立的
//      device_location_current（敏感，需主人确认）。原文档的 action=current 已失效。
//   3. device_notification：本仓只有 pending/delivered/settings，安排通知拆成
//      device_notification_schedule（敏感），取消拆成 device_notification_cancel
//      （敏感）。原文档的 schedule/cancel 同名动作已失效。
//   4. device_photos：本仓只有 list/near/albums/album/stats（只读）；导出/导入/
//      建相册/加进相册/收藏拆成 device_photos_write（敏感）。原文档把读写混在
//      一个 action 表里，已失效。
//   5. report_issue：本仓仓库是 imcat-owo/OpenDudu，令牌入口是
//      「设置 > 桥·对外连接 > 报问题到 GitHub」。原文档的 OpenMinis 仓库名已失效。
//   6. 敏感审批：本仓由 StewardSensitiveApprovalGate 签发，超时 120 秒。
//   7. 「搜/命令」的参数口径按 BridgeCore/BridgeMetaTools.swift 的实际
//      schema 写（timeoutSeconds 默认 30、超 60 第一次必 504；
//      sensitiveApproved 已作废）。
// - 旧 Dudu（openmuse/apps/mobile/src/manuals/*.ts）的 40 份手册格式是
//   {id, title, file, when, body} 的 TS 模块，讲的是旧 Expo App 的功能用法
//   （音乐房、主题、我们的空间等），不是桥设备工具的说明书；UserManualMirror
//   镜像的是 bundle 里的 user-manual.md（用户视角的 App 说明书），三者主题
//   不同，不能互相套用。所以这里不做"把旧手册塞进纸条"的硬搬：纸条只覆盖
//   桥设备工具；旧手册若以后要进 chat loop，应该另起一套按 when 话题路由的
//   机制，而不是塞进本文件。
//
// 注入点：AIChatViewModel.runAgentLoop 里组装 userSystemPrompt 的位置，
// 紧跟 TTSPaper 的注入（同一模式：paperIfRelevant + 按需追加）；另外
// runAgentLoop 的 provider fallback 重组 userSystemPrompt 时也要补一次
// 注入（D10 fix 2026-10-07，否则 fallback 那轮会丢纸条）——已下发过的
// 纸条在那里只给 compact 提醒，不重塞全文（会话级去重保持不变）。
// 状态：static 的 shownBySession 记录本会话已下发过的纸条 id，防重复注入。

// MARK: - Paper registry

/// 一张工具纸条：id + 标题 + 软话题提示 + 正文。
/// topics 是"相关话题"的宽松提示（中英混排），匹配是包含式、不做死关键词锁定。
enum DuduToolPapers {

    struct Paper {
        let id: String
        let title: String
        let topics: [String]
        /// 与这张纸条同属一次下发的伴随纸条 id（如下发删照片纸条时顺带下发审批流纸条）。
        let companions: [String]
        let body: String
    }

    static let all: [Paper] = [
        Paper(
            id: "bridge-starter",
            title: "桥的用法（搜/命令）",
            topics: ["有什么工具", "能做什么", "能干什么", "桥", "小管家", "搜工具",
                     "工具库", "怎么用桥", "bridge", "steward"],
            companions: [],
            body: """
                【纸条·桥的用法（搜/命令）】
                你连上的是「桥」。桥对外只有两个工具：「搜」和「命令」。
                1. 调「搜」：query 里用中文关键词说想找什么（比如：蓝牙、剪贴板、定位、通知、相册、报问题）。返回短清单：工具名＋一句话简介＋参数简述（参数名/类型/必填）。
                2. 调「命令」：instruction 用一句话说要干什么（必填，比如：帮我查一下手机现在的位置）。第 1 步已点名工具时，把 tool 填工具名、arguments 填参数对象（参数名和必填项看「搜」返回的参数简述）；不填 tool，小管家按指令自己挑工具。
                注意：timeoutSeconds 默认 30 秒，不要超过 60——超过 60 中继第一次必回 504。sensitiveApproved 参数已作废，别传，传了也不会被信任。
                「命令」只回清洗后的高密度结果，直接转述给主人就行。
                """
        ),
        Paper(
            id: "report_issue",
            title: "report_issue 报问题",
            topics: ["报问题", "反馈", "不好用", "报错", "bug", "issue", "出问题", "有毛病",
                     "闪退", "崩了", "故障", "report_issue", "提意见"],
            companions: ["sensitive-approval"],
            body: """
                【纸条·report_issue 报问题】
                什么时候调：主人明确说了 App 哪里有问题、不好用、报错了才调。主人只是在问怎么用、提意见但没说「这是问题」时，先问一句再调，不要自作主张发出去。
                分 3 步：
                1. 调 report_issue：title 必填（一句话说清是什么问题，比如「深色模式下输入框看不清」）；detail 可选（主人原话，尽量原样转述，别改写、别脑补；主人没细说就留空，不要编）。
                2. 工具自动附上发送时的小快照（App 版本、系统版本、发送时间、小管家当时在忙的任务）和最近的共享事件日志片段，不用另外传。同一内容 15 分钟内不会重复发——超时以为没发出去时，直接重发一次就行，不会建出第二条 Issue。
                3. 发完之后：工具会返回 Issue 编号和链接，一定要转述给主人（比如「已发到 GitHub，编号 #123，链接 https://…」），让主人知道去哪看。
                办不成时跟主人说什么：工具报「令牌还没填」→ 跟主人说去「设置 > 桥·对外连接 > 报问题到 GitHub」里粘贴令牌（需要对 imcat-owo/OpenDudu 有 Issues 写权限的 PAT），不要反复重试。
                这是敏感动作：执行前手机上会弹框，主人点了「允许」才发；主人超时没点或不在手机旁就按拒绝处理（见敏感审批纸条）。
                """
        ),
        Paper(
            id: "sensitive-approval",
            title: "敏感工具审批流",
            topics: ["敏感", "审批", "确认", "弹框", "允许", "device_photos_delete", "report_issue"],
            companions: [],
            body: """
                【纸条·敏感工具审批流】
                哪些工具是敏感的：device_photos_delete（删照片）、report_issue（发 Issue）、device_location_current（查当前位置）、device_clipboard_read（读剪贴板）、device_notification_schedule（安排通知）、device_notification_cancel（取消通知）、device_photos_write（相册写入）。简介里写了「敏感动作，需主人确认」的就是。
                外部 AI 发起敏感动作后会发生什么：
                1. 你调「命令」让小管家执行敏感工具，小管家不会直接执行，先请手机侧审批。
                2. 主人在手机前台：手机上弹框「小管家请求执行敏感操作」，主人点「允许」才执行，点「拒绝」就不执行；120 秒没点按拒绝处理。
                3. 主人不在手机旁（App 不在前台）：直接按「主人不在」拒绝，不排队、不等待。
                4. 传 sensitiveApproved=true 没用——这个参数已作废，真正的确认只能由手机侧弹框签发，防外部 AI 自己给自己批。
                AI 该怎么跟主人说：动手前先告诉主人「我要做 X（比如删这几张照片／把这个问题发到 GitHub），需要你在手机上点一下确认。」让主人有预期去看手机。收到「未获批准，已拒绝」：停手，如实说「主人没在手机上确认，这事没办」，不要反复重试刷屏。收到「主人未在手机旁，已拒绝」：跟主人说「我刚才想做 X，但你不在手机旁，系统按拒绝处理了；你在手机旁时跟我说一声，我再办。」
                """
        ),
        Paper(
            id: "device_bluetooth",
            title: "device_bluetooth 蓝牙",
            topics: ["蓝牙", "bluetooth", "ble", "device_bluetooth", "扫描设备", "连设备"],
            companions: [],
            body: """
                【纸条·device_bluetooth 蓝牙】
                先知道：这里管的是低功耗蓝牙（BLE）设备，不是蓝牙耳机/音箱这类经典蓝牙设备。想连耳机音箱别用这个。
                分步（每步调一次，action 换值）：
                1. action=status：看蓝牙开关状态和当前连着的设备。
                2. action=scan：扫附近 BLE 设备（duration 秒数默认 5，可带 service 按服务 UUID 过滤）。先扫，才能拿到设备的 uuid。
                3. action=connect：用扫到的 uuid 连一台设备（uuid 必填）。
                4. action=services：列已连设备的服务和特征（uuid 可省，省了就用当前连的那台；先查，才能拿到 service 和 characteristic 的 UUID）。
                5. action=read：读特征值（service＋characteristic 必填）；action=write：写特征值（再加 value 十六进制或 value_string 文本，二选一）；action=notify：订阅特征通知一段时间（duration 默认 10 秒，必须大于 0）。
                6. action=disconnect：断开（uuid 可省）。
                执行上限：默认 60 秒；scan/notify 按 duration 秒数＋45 秒。
                """
        ),
        Paper(
            id: "device_clipboard",
            title: "device_clipboard 剪贴板",
            topics: ["剪贴板", "剪切板", "复制", "粘贴", "clipboard", "device_clipboard", "拷贝"],
            companions: [],
            body: """
                【纸条·device_clipboard 剪贴板】
                device_clipboard（写/清/查）：action=set 写入（text 要写的文字和 image 沙箱内图片路径至少给一个，比如 /var/dudu/attachments/a.png）；action=clear 清空；action=status 看剪贴板里有什么类型的内容（默认）。
                读剪贴板里的内容不能用这个——调 device_clipboard_read（敏感动作，需主人确认）。
                执行上限 30 秒：「命令」口的 timeoutSeconds 传更大也不会延长，以这个为准。
                """
        ),
        Paper(
            id: "device_location",
            title: "device_location 定位",
            topics: ["定位", "位置", "经纬度", "地址", "gps", "location", "device_location",
                     "在哪", "导航", "坐标"],
            companions: [],
            body: """
                【纸条·device_location 定位】
                device_location（换算）：action=geocode 经纬度换成地址（lat 纬度＋lng 经度，两个都要给）；action=forward 地址换成经纬度（address 地址文字必填）。
                注意：这里经度叫 lng；相册按位置找照片（device_photos 的 near）里经度叫 lon，别混了，照各工具的参数名填。
                查手机当前 GPS 位置不能用这个——调 device_location_current（accuracy 可选 best/near/km，默认 best；精确位置是隐私，敏感动作，需主人确认）。
                执行上限 45 秒：「命令」口的 timeoutSeconds 传更大也不会延长，以这个为准。
                """
        ),
        Paper(
            id: "device_notification",
            title: "device_notification 本地通知",
            topics: ["通知", "提醒", "notification", "device_notification", "闹钟", "定时"],
            companions: [],
            body: """
                【纸条·device_notification 本地通知】
                device_notification（查看类，直接调）：action=pending 看待触发的通知；action=delivered 看已送达的；action=settings 看通知授权状态。
                安排一条调 device_notification_schedule（敏感动作，需主人确认）：title（标题）/body（正文）至少给一个；after（多少秒后，整数）或 at（ISO 时间，如 2026-10-01T09:00:00）至少给一个；repeat=true 是重复提醒（配 at 就是每天该时刻响，配 after 就是每 N 秒响，N 最短 60）；action_spec 可带交互按钮，格式「按钮名:id」逗号分隔，如 "继续:continue,停止:stop"。
                取消调 device_notification_cancel（敏感动作，需主人确认）：id 指定取消一条（先调 pending 查到 id），或 all=true 全部取消。删掉设好的提醒不可恢复。
                排完后跟主人说一声什么时候会响、内容是什么，让主人心里有数。执行上限 30 秒：「命令」口的 timeoutSeconds 传更大也不会延长，以这个为准。
                """
        ),
        Paper(
            id: "device_photos",
            title: "device_photos 相册",
            topics: ["相册", "照片", "图片", "视频", "photos", "album", "图库", "device_photos",
                     "找图", "找照片", "看照片"],
            companions: [],
            body: """
                【纸条·device_photos 相册】
                device_photos（只读查询）：action=list 列最近照片/视频（limit 上限默认 100；type=photo/video/all；start/end 日期；days 最近 N 天）；action=near 找某经纬度附近的照片（lat＋lon 必填，radius 半径公里默认 1）；action=albums 列相册（type=user/smart/all）；action=album 看某个相册里的内容（id 或 name，limit）；action=stats 相册统计。
                写动作调 device_photos_write（敏感动作，需主人确认）：export 导出一张到 /var/dudu/offloads/（id 必填，size=thumb/medium/original 默认 original），导出后拿那个路径去用；import 把沙箱里的图片/视频文件存进相册（path 必填，可带 album 或 album_name，没有会新建）；create-album 新建相册（name 必填）；add-to-album 把已有照片（assets 逗号分隔 id）或文件（paths 逗号分隔路径）加进相册（album 或 album_name 必填其一）；favorite 收藏/取消收藏一张（id 必填）。
                删照片不用这两个，用 device_photos_delete（见删照片纸条，要主人确认）。
                id 从哪来：先调 list 或 albums 查到 id，再拿 id 办后面的事。
                执行上限 120 秒；注意「命令」口的中继转发上限是 60 秒，传超 60 秒的超时第一次必吃 504。
                """
        ),
        Paper(
            id: "device_photos_delete",
            title: "device_photos_delete 删照片",
            topics: ["删照片", "删除照片", "删掉", "删视频", "删除视频", "device_photos_delete"],
            companions: ["sensitive-approval"],
            body: """
                【纸条·device_photos_delete 删照片】
                分 3 步：
                1. 先用 device_photos 的 list 查到要删的照片 id，跟主人核对一遍删哪几张（别删错，删了进系统删除流程）。
                2. 调 device_photos_delete，ids 填逗号分隔的照片 id。
                3. 这是敏感动作，走审批流（见敏感审批纸条）：主人要在手机上点「允许」才真删；被拒绝就停手，如实跟主人说。
                跟主人说什么：动手前说「我准备删这几张（把标题/时间列出来），需要你在手机上点确认」；删完说「删好了」；被拒绝就说「没删，你没确认/不在手机旁」。
                """
        ),
    ]

    private static func paper(id: String) -> Paper? {
        all.first { $0.id == id }
    }

    /// 按话题宽松匹配：用户消息里出现任一话题提示词即命中（不做死关键词锁定）。
    /// 匹配不到返回空数组，调用方不注入任何东西。
    static func matching(userMessage: String) -> [Paper] {
        let t = userMessage.lowercased()
        guard !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        var hits: [Paper] = []
        var seen = Set<String>()
        for p in all where p.topics.contains(where: { t.contains($0.lowercased()) }) {
            hits.append(p)
            seen.insert(p.id)
            for cid in p.companions where !seen.contains(cid) {
                if let c = paper(id: cid) {
                    hits.append(c)
                    seen.insert(cid)
                }
            }
        }
        return hits
    }
}

// MARK: - Wiring: inject into the agent-loop prompt

/// 把话题相关的工具纸条塞进 agent loop 的 system prompt。
/// 调用方（AIChatViewModel.runAgentLoop）在组装 userSystemPrompt 时调一次。
enum DuduToolPapersWiring {

    /// 本会话已下发过的纸条 id（防重复注入）。key 是 sessionId。
    /// 只在 @MainActor 上下文读写（调用点是 @MainActor 的 runAgentLoop）。
    /// 每个会话最多记几张纸条的 id（短字符串），进程级内存占用可忽略。
    /// 曾有 resetSession / shownPaperIDs 两个 API，但全仓零调用：
    /// 真正的会话销毁路径在 ChatStore.deleteSession（D10 作用域外），
    /// 在两个可编辑文件里找不到诚实的接线点，所以直接删除，不留死代码。
    private static var shownBySession: [String: Set<String>] = [:]

    /// 话题相关的纸条拼进 prompt。本轮命中的纸条中，未下发过的塞全文；
    /// 已在本会话下发过的只给一句「已读过」的 compact 提醒（同一轮里两种
    /// 都要处理，不能因为塞了新纸条就吞掉旧纸条的提醒）。
    /// 无相关话题时 prompt 原样不动。
    /// sessionID 为 nil 时不做去重：nil 是瞬时/测试上下文，没有稳定会话
    /// 身份，用一个全局桶会把不同对话的已读状态混在一起（跨轮污染）。诚
    /// 实做法是每次按话题重下全文——保证纸条不会在 provider fallback 或
    /// 别的重组路径里被静默吞掉，代价只是多塞几个 token。
    @MainActor
    static func inject(into prompt: inout String, userMessage: String, sessionID: String?) {
        let matched = DuduToolPapers.matching(userMessage: userMessage)
        guard !matched.isEmpty else { return }

        guard let sid = sessionID else {
            prompt += "\n\n" + matched.map(\.body).joined(separator: "\n\n")
            return
        }

        var shown = shownBySession[sid] ?? Set<String>()
        let fresh = matched.filter { !shown.contains($0.id) }
        if !fresh.isEmpty {
            prompt += "\n\n" + fresh.map(\.body).joined(separator: "\n\n")
            for p in fresh { shown.insert(p.id) }
            shownBySession[sid] = shown
        }

        // 同一轮里：已下发过的纸条给 compact 提醒，不再重复塞全文。
        let known = matched.filter { shown.contains($0.id) }
        if !known.isEmpty {
            let names = known.map(\.title).joined(separator: "、")
            prompt += "\n\n【纸条已读】本会话你已读过这些工具纸条：" + names + "。按纸条里的步骤来，不用再问我要纸条。"
        }
    }
}
