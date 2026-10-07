//
//  D20b: AI 主动发照片 PhotoShareManager —— ported from
//  ~/workspace/openmuse/apps/mobile/src/manuals/photoshare.ts （纯逻辑层）。
//
//  规矩（原版逐字搬）：
//  - MASTER TOGGLE 是 OPT-IN，默认 OFF。只有她亲手打开，AI 永远不许自作主张开。
//  - 她主动要照片（「发张照片给我」）时走 shareNow：这是回答，不是惊喜，toggle 不拦。
//  - 照片必须经 REAL 图片管线 FRESH 生成。没有库存图、没有占位图、没有假装。
//  - 永远不许声称照片是用相机/手机拍的。这是分享的想象瞬间，不是假元数据。
//  - 文案：一两句自然的话，她的语言、AI 的口吻，像给女朋友发照片。不提 AI、prompt、slot。
//
//  现状（诚实缺口 #1）：本仓库里真实的图片生成路由在
//  Dudu/NativeOffloads/ModelUseOffloadBridge.swift（image_output 路由，
//  经 OpenAIProvider.generateImage）。但它目前没有暴露给桥工具的简单入口，
//  所以 PhotoShareManager.imagePipeline 默认为 nil——管线没接好时，
//  shareNow 返回诚实的「图片管线还没接好」错误，绝不用占位图顶上。
//  coordinator 把 ModelUseOffloadBridge 的图片路由（或她配的 image_output 模型）
//  接进来，赋值给 imagePipeline 即可。

import Foundation

// MARK: - 真实图片管线适配口

/// 真实的图片生成入口。coordinator 实现后赋值给
/// `PhotoShareManager.imagePipeline`（例如包一层 ModelUseOffloadBridge
/// 的 image_output 路由，或她自己配的 image_output 模型）。
/// 返回生成好的图片文件 URL（App 可读的本地路径）。
public protocol PhotoShareImagePipeline: Sendable {
    func generatePhoto(prompt: String) async throws -> URL
}

public struct PhotoShareLogEntry: Codable, Sendable, Identifiable {
    public var id: String
    /// 分享时间戳。
    public var at: TimeInterval
    /// 文案预览。
    public var caption: String
    /// 生成的图片本地路径。
    public var imagePath: String
    public init(id: String = UUID().uuidString, at: TimeInterval, caption: String, imagePath: String) {
        self.id = id
        self.at = at
        self.caption = caption
        self.imagePath = imagePath
    }
}

public struct PhotoShareConfig: Codable, Sendable {
    /// 主动分享开关：OPT-IN，默认 false。只有她能改。
    public var enabled: Bool = false
    /// 每天几个安静时刻问一次（默认 2 个：20:00 和 00:30，上海时间——她的活跃时段）。
    public var slotCount: Int = 2
    /// 每天主动分享上限（和所有「AI 主动找她」的发送共享一个日常 cap 口径）。
    public var dailyCap: Int = 2
}

// MARK: - PhotoShareManager

public actor PhotoShareManager {
    public static let shared = PhotoShareManager()

    /// 真实图片管线。nil = 还没接好（诚实缺口 #1）。
    public static var imagePipeline: (any PhotoShareImagePipeline)?

    private let enabledKey = "dudu.photoshare.v1.enabled"
    private let configKey = "dudu.photoshare.v1.config"
    private let logKey = "dudu.photoshare.v1.log"
    private let countDateKey = "dudu.photoshare.v1.countDate"
    private let countKey = "dudu.photoshare.v1.count"
    private static let logCap = 50

    /// 她的睡眠时间（上海）：06:00–16:00。主动分享绝不在这段时间打扰。
    /// shareNow（她主动要的）不受此限。
    public static func isQuietHour(now: Date = Date()) -> Bool {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current
        let hour = cal.component(.hour, from: now)
        return hour >= 6 && hour < 16
    }

    // MARK: toggle & config

    public func isEnabled() -> Bool {
        UserDefaults.standard.bool(forKey: enabledKey)
    }

    /// 只有她亲手操作才调这个。AI 不许自作主张开。
    public func setEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: enabledKey)
    }

    public func config() -> PhotoShareConfig {
        guard let data = UserDefaults.standard.data(forKey: configKey),
              let c = try? JSONDecoder().decode(PhotoShareConfig.self, from: data) else {
            return PhotoShareConfig()
        }
        return c
    }

    public func updateConfig(slotCount: Int?, dailyCap: Int?) {
        var c = config()
        if let slotCount { c.slotCount = max(1, min(4, slotCount)) }
        if let dailyCap { c.dailyCap = max(0, min(6, dailyCap)) }
        if let data = try? JSONEncoder().encode(c) {
            UserDefaults.standard.set(data, forKey: configKey)
        }
    }

    // MARK: daily cap

    /// 今天已经主动分享了几次（自然日，上海）。
    public func sharesToday(now: Date = Date()) -> Int {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current
        let today = cal.startOfDay(for: now).timeIntervalSince1970
        let saved = UserDefaults.standard.double(forKey: countDateKey)
        guard saved == today else { return 0 }
        return UserDefaults.standard.integer(forKey: countKey)
    }

    private func bumpSharesToday(now: Date) {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current
        let today = cal.startOfDay(for: now).timeIntervalSince1970
        UserDefaults.standard.set(today, forKey: countDateKey)
        UserDefaults.standard.set(UserDefaults.standard.integer(forKey: countKey) + 1, forKey: countKey)
    }

    // MARK: share

    public enum ShareError: Error, LocalizedError {
        case pipelineNotConnected
        case dailyCapReached(Int)
        case generationFailed(String)

        public var errorDescription: String? {
            switch self {
            case .pipelineNotConnected:
                return "图片管线还没接好：PhotoShareManager.imagePipeline 未接入真实的图片生成路由，所以这次没法生成照片——没有用库存图或占位图顶上。coordinator 接好管线后再试。"
            case .dailyCapReached(let cap):
                return "今天主动分享的次数已经到上限（\(cap) 次）了，明天再分享吧。"
            case .generationFailed(let msg):
                return "照片生成失败：\(msg)"
            }
        }
    }

    public struct ShareResult: Sendable {
        public var imageURL: URL
        public var caption: String
        public init(imageURL: URL, caption: String) {
            self.imageURL = imageURL
            self.caption = caption
        }
    }

    /// 她主动要照片（「发张照片给我」）：这是回答，不是惊喜，toggle 不拦。
    /// - Parameters:
    ///   - hint: 她给的提示，如「穿白衬衫的自拍」——原样喂给图片模型当此刻的瞬间。
    ///   - personaLook: 她的人设外貌描述（description + personality），保证形象一致。
    ///     注意：管线没有图生图参考，一致性靠 prompt——不许声称有参考图。
    ///   - caption: AI 写的文案（一两句自然的话）。manager 只负责存档，不编文案。
    public func shareNow(hint: String, personaLook: String, caption: String, now: Date = Date()) async throws -> ShareResult {
        guard let pipeline = Self.imagePipeline else {
            throw ShareError.pipelineNotConnected
        }
        var promptParts: [String] = []
        if !personaLook.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            promptParts.append("角色形象（保持一致）：\(personaLook.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
        let h = hint.trimmingCharacters(in: .whitespacesAndNewlines)
        promptParts.append(h.isEmpty ? "此刻值得分享的一个安静瞬间" : "此刻的瞬间：\(h)")
        promptParts.append("要求：画面自然、生活感，像随手分享的一刻；不要摆拍感。")
        let prompt = promptParts.joined(separator: "\n")

        let url: URL
        do {
            url = try await pipeline.generatePhoto(prompt: prompt)
        } catch {
            throw ShareError.generationFailed(error.localizedDescription)
        }
        appendLog(PhotoShareLogEntry(at: now.timeIntervalSince1970, caption: caption, imagePath: url.path))
        return ShareResult(imageURL: url, caption: caption)
    }

    /// 主动分享（定时 slot 触发，coordinator 调度）：走全套被动 rails——
    /// toggle 必须开、 quiet hours 不打扰、每天 cap、60 分钟碰撞由调度层保证。
    /// 返回 nil = 今晚保持沉默（SKIP 永远没问题）。
    public func maybeProactiveShare(personaLook: String, caption: String, now: Date = Date()) async throws -> ShareResult? {
        guard await isEnabled() else { return nil }
        guard !Self.isQuietHour(now: now) else { return nil }
        let cap = config().dailyCap
        guard sharesToday(now: now) < cap else { return nil }
        let result = try await shareNow(hint: "", personaLook: personaLook, caption: caption, now: now)
        bumpSharesToday(now: now)
        return result
    }

    // MARK: log

    public func log() -> [PhotoShareLogEntry] {
        guard let data = UserDefaults.standard.data(forKey: logKey),
              let entries = try? JSONDecoder().decode([PhotoShareLogEntry].self, from: data) else {
            return []
        }
        return entries.sorted { $0.at > $1.at }
    }

    private func appendLog(_ entry: PhotoShareLogEntry) {
        var entries = log()
        entries.insert(entry, at: 0)
        entries = Array(entries.prefix(Self.logCap))
        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: logKey)
        }
    }

    public func statusLine(now: Date = Date()) -> String {
        let c = config()
        let on = isEnabled() ? "开" : "关"
        return "主动发照片：\(on) · 今天已分享 \(sharesToday(now: now))/\(c.dailyCap) 次 · 每天 \(c.slotCount) 个安静时刻 · 管线：\(Self.imagePipeline == nil ? "还没接好" : "已连接")"
    }
}
