import Foundation
import BridgeCore

// MARK: - MCPToolTester · 逐工具"测试"调用（MCP 详情页用）

/// UI 层（MCPDetailView 的每行"测试"按钮）背后的引擎：用空参数调一次
/// 工具，走的和 AI 调 MCP 同一条链路 —— `MCPAggregator.call` →
/// in-guest `dudu-mcp-cli call <server> <tool> --input '{}'`。
///
/// 判读规则（只看返回的文本，不猜 daemon 内部实现）：
/// - 调通且无错 → .passed（"通过"）
/// - 返回了错误，但错误明显是"参数校验"（缺必填参数/类型不对），且
///   不含任何连通性/查找失败的信号 → .reachable：传输链路是通的，
///   只是空参数被工具拒了，界面显示"连通了（这次没带参数）"
/// - 其余 → .failed：原样报错误文本，界面红色显示、可点看全文
///
/// 状态存在这个对象里（key = 工具名），MCPDetailView 持有它作
/// @StateObject，所以视图活着期间状态一直在，滚动不会丢。
@MainActor
final class MCPToolTester: ObservableObject {

    enum ToolTestStatus: Equatable {
        case idle
        case testing
        case passed
        /// 传输通了，工具因缺参拒绝（空参数试调的预期情况之一）。
        case reachable
        case failed(short: String)
    }

    enum TesterError: LocalizedError {
        case timeout
        var errorDescription: String? {
            switch self {
            case .timeout:
                return "调用超时（60 秒）：服务器可能卡住了，稍后再试一次看看。"
            }
        }
    }

    /// UI 的探针超时：引擎层 ishExecute 自带 120 秒，这里 60 秒先判超时，
    /// 免得用户盯着转圈太久。超时只取消这次 UI 探针，不影响 AI 的正常调用。
    private static let probeTimeoutNanoseconds: UInt64 = 60_000_000_000

    @Published private(set) var statuses: [String: ToolTestStatus] = [:]
    /// 失败/连通时的完整错误原文（key = 工具名），点开详情时看。
    @Published private(set) var detailTexts: [String: String] = [:]
    @Published var showingDetail = false
    @Published private(set) var detailTitle = ""
    @Published private(set) var detailText = ""
    @Published private(set) var detailToolName = ""

    private var tasks: [String: Task<Void, Never>] = [:]
    /// 代际计数（key = 工具名）：同一工具重测时 +1。老任务写回状态前先对
    /// 代号，对不上就闭嘴——被取消的老任务不能覆盖新一轮的状态，也不能
    /// 把新任务从 tasks 里摘掉。
    private var generations: [String: UInt64] = [:]

    func status(of toolName: String) -> ToolTestStatus {
        statuses[toolName] ?? .idle
    }

    /// 发起一次试调。同一工具在测时再点，会先取消上一轮。
    func test(serverId: String, toolName: String) {
        tasks[toolName]?.cancel()
        let generation = (generations[toolName] ?? 0) + 1
        generations[toolName] = generation
        statuses[toolName] = .testing
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            /// 只有当前这一代能写状态、能摘 tasks；老一代一律闭嘴。
            let isCurrent = { self.generations[toolName] == generation }
            defer {
                if isCurrent() { self.tasks[toolName] = nil }
            }
            do {
                let output = try await Self.invoke(serverId: serverId, toolName: toolName)
                try Task.checkCancellation()
                let outcome = Self.classify(output)
                guard isCurrent() else { return }
                self.statuses[toolName] = outcome.status
                if let full = outcome.fullText {
                    self.detailTexts[toolName] = full
                }
            } catch is CancellationError {
                // 被取消的老任务不许把新一轮的 .testing 盖回 .idle。
                if isCurrent() { self.statuses[toolName] = .idle }
            } catch {
                guard isCurrent() else { return }
                let text = error.localizedDescription
                self.statuses[toolName] = .failed(short: Self.shortError(text))
                self.detailTexts[toolName] = text
            }
        }
        tasks[toolName] = task
    }

    /// 点开某工具的完整报错/返回。
    func showDetail(for toolName: String) {
        detailToolName = toolName
        switch statuses[toolName] {
        case .reachable:
            detailTitle = "连通了，但工具想要参数"
        default:
            detailTitle = "没调通"
        }
        detailText = detailTexts[toolName] ?? ""
        showingDetail = true
    }

    /// 页面关掉时把还没跑完的探针都停掉。
    func cancelAll() {
        for task in tasks.values { task.cancel() }
        tasks.removeAll()
    }

    // MARK: - 调用

    /// 空参数试调 + 60 秒探针超时。取消信号透传（页面关掉/重测时用）。
    private static func invoke(serverId: String, toolName: String) async throws -> ToolOutput {
        try await withThrowingTaskGroup(of: ToolOutput.self) { group in
            group.addTask {
                try await MCPAggregator.call(
                    serverId: serverId,
                    toolName: toolName,
                    arguments: StrictJSONObject(raw: [:])
                )
            }
            group.addTask {
                try await Task.sleep(nanoseconds: probeTimeoutNanoseconds)
                throw TesterError.timeout
            }
            guard let first = try await group.next() else { throw TesterError.timeout }
            group.cancelAll()
            return first
        }
    }

    // MARK: - 判读

    private struct Outcome {
        let status: ToolTestStatus
        /// 非 nil 时记入 detailTexts（失败/连通的完整原文）。
        let fullText: String?
    }

    private static func classify(_ output: ToolOutput) -> Outcome {
        guard output.isError else {
            return Outcome(status: .passed, fullText: nil)
        }
        let lowered = output.text.lowercased()
        // 先看传输是不是真断了：这些信号出现时，"参数"字样也救不回来。
        if transportBrokenHints.contains(where: { lowered.contains($0) }) {
            return Outcome(status: .failed(short: shortError(output.text)), fullText: output.text)
        }
        // 传输没毛病、错在参数上 → 判连通（空参数试调的预期情况）。
        if argumentValidationHints.contains(where: { lowered.contains($0) }) {
            return Outcome(status: .reachable, fullText: output.text)
        }
        return Outcome(status: .failed(short: shortError(output.text)), fullText: output.text)
    }

    /// 传输/查找失败的信号（中英文都留，daemon 和 CLI 的文案混着来）。
    private static let transportBrokenHints = [
        "沙箱", "kernel", "daemon", "连接", "connect", "超时", "timeout",
        "timed out", "拒绝", "refused", "未运行", "not running",
        "找不到", "not found", "no such", "unknown tool", "没有这个工具",
        "不存在", "退出码", "exit code", "failed to", "unavailable", "不可用",
        "spawn", "econnrefused", "econnreset", "enotfound",
    ]

    /// 干净的参数校验信号：工具/daemon 在说"参数不对"，而不是"连不上"。
    private static let argumentValidationHints = [
        "缺少", "缺失", "必填", "不能为空", "参数",
        "required", "missing", "invalid argument", "invalid params",
        "invalid parameters", "schema", "must provide", "expected",
    ]

    /// 行内短报错：压成一行、截断，完整版点开展示。
    private static func shortError(_ text: String) -> String {
        let oneLine = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        if oneLine.count <= 120 { return oneLine }
        return String(oneLine.prefix(120)) + "…"
    }
}
