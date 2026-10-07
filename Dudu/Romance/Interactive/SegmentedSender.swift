//
//  D20b: 真人式分段发送 SegmentedSender —— faithfully ported from
//  ~/workspace/openmuse/apps/mobile/src/segments/ (split.ts, drip.ts, store.ts).
//
//  像真人发微信：长回复偶尔拆成 2～3 个短气泡连发，而不是一堵文字墙。
//
//  保守设计（她的 bar，原样移植）：
//  - 回复够长（>= MIN_SPLIT_LEN 字符）才拆。
//  - 只在自然的句子边界拆（中文感知：。！？!?… 和换行）。绝不在句中、
//    代码围栏里、图片/语音消息信封里拆。
//  - 最多 MAX_BUBBLES（3）个气泡。末尾碎片 < 25 字符并入上一泡，不单独 dangling。
//  - 短回复、工具调用消息、结构化消息原样单泡发出。

import Foundation

// MARK: - Split （split.ts 移植，纯函数）

public enum SegmentedSender {
    /// 低于这个长度的回复永远不拆。
    public static let minSplitLen = 140
    /// 每个回复的气泡硬上限。
    public static let maxBubbles = 3
    /// 末尾气泡短于这个就并入上一泡。
    private static let minTrailLen = 25

    /// 强句子边界（中英），标点跟句子走。
    private static let boundaryPattern = "[^。！？!?\\n…]+[。！？!?…\\n]+|[^。！？!?\\n…]+$"

    /// 结构化标记：「这是结构化消息，别碰」。
    /// 移植自原版 STRUCTURED_RE（代码围栏 + 语音/图片消息信封）。
    private static let structuredMarkers = ["```", "\"image_message\"", "\"voice_message\"", "\"voice-message\""]

    /// 按强边界把文本切成句子单元，标点保留。无可切时返回空。
    public static func splitSentences(_ text: String) -> [String] {
        guard let re = try? NSRegularExpression(pattern: boundaryPattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        var out: [String] = []
        for m in re.matches(in: text, range: range) {
            if let r = Range(m.range, in: text) {
                let s = String(text[r]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !s.isEmpty { out.append(s) }
            }
        }
        return out
    }

    public static func isStructured(_ text: String) -> Bool {
        structuredMarkers.contains { text.contains($0) }
    }

    /// 把一条回复拆成 1..maxBubbles 个气泡。纯函数，保序：
    /// 句子按连续分组、用小 DP 均衡各组长度（最小化最长组）。
    public static func splitIntoBubbles(_ text: String) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [text] }
        guard trimmed.count >= minSplitLen else { return [trimmed] }
        guard !isStructured(trimmed) else { return [trimmed] }

        let sentences = splitSentences(trimmed)
        guard sentences.count >= 2 else { return [trimmed] }

        // 气泡数：长回复 2 泡，特别长才 3 泡。
        let k = min(maxBubbles, sentences.count, trimmed.count >= Int(Double(minSplitLen) * 2.2) ? 3 : 2)
        guard k >= 2 else { return [trimmed] }

        var bubbles = balancedSplit(sentences, k: k)
            .map { $0.joined().trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        // 末尾碎片太小就并入上一泡。
        while bubbles.count > 1, let last = bubbles.last, last.count < minTrailLen {
            bubbles.removeLast()
            bubbles[bubbles.count - 1] += last
        }
        return bubbles.isEmpty ? [trimmed] : bubbles
    }

    /// 把 items 按连续 k 组划分，最小化最长组（按字符数）。小 DP：n 句（约 <=40），k <= 3。
    private static func balancedSplit(_ items: [String], k: Int) -> [[String]] {
        let n = items.count
        let lens = items.map { $0.count }
        var prefix = [0]
        for l in lens { prefix.append(prefix.last! + l) }
        func cost(_ i: Int, _ j: Int) -> Int { prefix[j] - prefix[i] } // [i, j)

        // dp[g][j] = 前 j 个分 g 组时的最小可能最长组长。
        var dp = Array(repeating: Array(repeating: Int.max / 2, count: n + 1), count: k + 1)
        var cut = Array(repeating: Array(repeating: -1, count: n + 1), count: k + 1)
        dp[0][0] = 0
        if k >= 1 {
            for g in 1...k {
                for j in g...n {
                    for i in (g - 1)..<j {
                        if dp[g - 1][i] >= Int.max / 2 { continue }
                        let worst = max(dp[g - 1][i], cost(i, j))
                        if worst < dp[g][j] {
                            dp[g][j] = worst
                            cut[g][j] = i
                        }
                    }
                }
            }
        }
        // 回溯。
        var groups: [[String]] = []
        var j = n
        for g in stride(from: k, through: 1, by: -1) {
            let i = cut[g][j]
            guard i >= 0 else { return [items] } // 不该发生；fail safe
            groups.insert(Array(items[i..<j]), at: 0)
            j = i
        }
        return groups
    }

    /// 第 index 个气泡（>0）出现前的人性化延迟，按上一泡长度算阅读时间。
    /// 基准 700ms，每字 ~6ms，上限 2.2s。纯计算，等待由调用方做。
    public static func bubbleDelayMs(prevBubbleLen: Int) -> Int {
        min(2200, 700 + max(0, prevBubbleLen) * 6)
    }
}

// MARK: - BubbleDrip （drip.ts 移植：气泡逐条滴落调度器）

/// 一轮的最终气泡被拆分后：第一泡立刻替换原消息发出，
/// 剩下的按人性化延迟经「真正的发消息路径」逐条滴入（每条都 emit + 持久化，
/// 和普通消息一模一样）。
///
/// 计时器可注入（Task.sleep 封装），测试可确定性驱动。
public actor BubbleDrip {
    public private(set) var pendingCount: Int = 0

    private var queue: [String] = []
    private var currentTask: Task<Void, Never>?

    public init() {}

    /// 开始滴落。第一个元素的延迟按 prevLen 算。
    public func start(
        bubbles: [String],
        prevLen: Int,
        deliver: @escaping @Sendable (String) async -> Void,
        onChange: (@Sendable () -> Void)? = nil
    ) {
        cancel()
        queue = bubbles
        pump(prevLen: prevLen, deliver: deliver, onChange: onChange)
    }

    private func pump(
        prevLen: Int,
        deliver: @escaping @Sendable (String) async -> Void,
        onChange: (@Sendable () -> Void)?
    ) {
        guard !queue.isEmpty else {
            setPending(0, onChange: onChange)
            return
        }
        setPending(queue.count, onChange: onChange)
        let delayMs = SegmentedSender.bubbleDelayMs(prevBubbleLen: prevLen)
        currentTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(delayMs) * 1_000_000)
            guard !Task.isCancelled else { return }
            let next = await self.popNext(onChange: onChange)
            guard let next else { return }
            await deliver(next)
            await self.pump(prevLen: next.count, deliver: deliver, onChange: onChange)
        }
    }

    private func popNext(onChange: (@Sendable () -> Void)?) -> String? {
        guard !queue.isEmpty else {
            setPending(0, onChange: onChange)
            return nil
        }
        return queue.removeFirst()
    }

    private func setPending(_ n: Int, onChange: (@Sendable () -> Void)?) {
        if pendingCount != n {
            pendingCount = n
            onChange?()
        }
    }

    /// 队列里剩下的立刻全发出去。stop 时不丢消息。
    public func flush(deliver: @escaping @Sendable (String) async -> Void) async {
        let rest = queue
        queue = []
        currentTask?.cancel()
        currentTask = nil
        for b in rest { await deliver(b) }
        pendingCount = 0
    }

    public func cancel() {
        queue = []
        currentTask?.cancel()
        currentTask = nil
        pendingCount = 0
    }
}

// MARK: - SegmentStore （store.ts 移植：按人设的开关）

/// 分段发送开关（按人设）。默认 ON（保守：拆分器本身只在长回复时触发）。
/// 她可以按人设关掉；AI 永远不改这个开关。
public enum SegmentStore {
    private static func key(personaId: String?) -> String {
        "dudu.segments.v1.\(personaId ?? "default")"
    }

    /// 默认 true——没关过就是开的（UserDefaults 读失败也 fail open：纯渲染选择，无害）。
    public static func isEnabled(personaId: String?) -> Bool {
        UserDefaults.standard.object(forKey: key(personaId: personaId)) == nil
            ? true
            : UserDefaults.standard.bool(forKey: key(personaId: personaId))
    }

    public static func setEnabled(personaId: String?, enabled: Bool) {
        let k = key(personaId: personaId)
        if enabled {
            UserDefaults.standard.removeObject(forKey: k)
        } else {
            UserDefaults.standard.set(false, forKey: k)
        }
    }
}
