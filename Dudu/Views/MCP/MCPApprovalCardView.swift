import SwiftUI

// MARK: - MCPToolDenyList · "总是拒绝"小名单（UI 层）

/// Engine 的逐工具审批只认"需不需要批准"（MCPToolApprovalStore），没有
/// "总是拒绝"的字段。这个名单记在 UserDefaults：卡片看到名单里的工具，
/// 直接替用户点"拒绝"，不弹窗、不打扰。跟"每次都问"（needsApproval=true）
/// 是两回事 —— 名单里的是问都不问。
@MainActor
final class MCPToolDenyList: ObservableObject {
    static let shared = MCPToolDenyList()
    private let defaultsKey = "mcp.denyAlwaysTools"
    @Published private(set) var denied: Set<String> = []

    private init() {
        denied = Set(UserDefaults.standard.stringArray(forKey: defaultsKey) ?? [])
    }

    private func key(serverId: String, tool: String) -> String {
        "\(serverId)/\(tool)"
    }

    func isDenied(serverId: String, tool: String) -> Bool {
        denied.contains(key(serverId: serverId, tool: tool))
    }

    func setDenied(_ denied: Bool, serverId: String, tool: String) {
        let k = key(serverId: serverId, tool: tool)
        if denied {
            self.denied.insert(k)
        } else {
            self.denied.remove(k)
        }
        UserDefaults.standard.set(Array(self.denied), forKey: defaultsKey)
    }
}

// MARK: - MCPApprovalCardView · 工具审批卡片

/// Phase D3: ToolApprovalGate 的 UI。AI 想调 MCP 工具（或日历写入、shell
/// 命令）时，ToolApprovalGate → ToolSuspensionService.suspendApproval 挂起，
/// 这里观察 `current` 并弹出浮层卡片。
///
/// 非阻塞：挂在 DuduTabView 上的 overlay 浮层，不是 sheet/modal，
/// 聊天输入不受影响，继续能聊。
struct MCPApprovalCardView: View {
    @ObservedObject private var suspension = ToolSuspensionService.shared
    @ObservedObject private var denyList = MCPToolDenyList.shared

    /// 记住选项。
    private enum RememberChoice: String, CaseIterable, Identifiable {
        case none = "不记住"
        case session = "本次会话免问"
        case alwaysAllow = "总是允许"
        case alwaysDeny = "总是拒绝"
        var id: String { rawValue }
    }
    @State private var remember: RememberChoice = .none

    var body: some View {
        Group {
            if let request = suspension.current,
               case .approval(let payload) = request.kind {
                approvalCard(request: request, payload: payload)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .onAppear { autoDenyIfListed(request: request, payload: payload) }
                    .onChange(of: request.id) { _ in remember = .none }
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: suspension.current?.id)
    }

    // MARK: - MCP 目标解析

    /// 从审批载荷里解析出 (server, tool)。优先读 rows 的"服务器/工具"
    /// 键（ToolApprovalGate 就是这么写的），兜底按 title "server / tool" 切。
    /// 非 MCP 审批（日历写入/shell 命令）返回 nil。
    private func mcpTarget(of payload: ApprovalPayload) -> (server: String, tool: String)? {
        let server = payload.rows.first(where: { $0.key == "服务器" })?.value
        let tool = payload.rows.first(where: { $0.key == "工具" })?.value
        if let s = server, let t = tool, !s.isEmpty, !t.isEmpty {
            return (s, t)
        }
        let parts = payload.title.split(separator: "/")
            .map { $0.trimmingCharacters(in: .whitespaces) }
        if parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty {
            return (parts[0], parts[1])
        }
        return nil
    }

    /// "总是拒绝"名单里的工具：不弹窗，直接拒绝。
    private func autoDenyIfListed(request: SuspendedRequest, payload: ApprovalPayload) {
        guard let target = mcpTarget(of: payload),
              denyList.isDenied(serverId: target.server, tool: target.tool) else { return }
        suspension.respond(id: request.id, decision: .denied)
    }

    // MARK: - Card

    private func approvalCard(request: SuspendedRequest, payload: ApprovalPayload) -> some View {
        let isMCP = mcpTarget(of: payload) != nil
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "shield.fill")
                    .foregroundStyle(DuduTheme.pink)
                    .font(.system(size: 18))
                Text(payload.title)
                    .font(DuduTheme.bodyFont(weight: .semibold))
                    .foregroundStyle(DuduTheme.duduText)
                    .lineLimit(2)
                Spacer()
            }

            if !payload.description.isEmpty {
                Text(payload.description)
                    .font(DuduTheme.captionFont())
                    .foregroundStyle(DuduTheme.duduTextDim)
            }

            ForEach(payload.rows, id: \.self) { row in
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.key)
                        .font(DuduTheme.captionFont())
                        .foregroundStyle(DuduTheme.duduTextDim)
                    Text(row.value)
                        .font(DuduTheme.captionFont())
                        .foregroundStyle(DuduTheme.duduText)
                        .textSelection(.enabled)
                }
            }

            Picker("记住", selection: $remember) {
                Text(RememberChoice.none.rawValue).tag(RememberChoice.none)
                if payload.allowSessionGrant, payload.grantKey != nil {
                    Text(RememberChoice.session.rawValue).tag(RememberChoice.session)
                }
                if isMCP {
                    Text(RememberChoice.alwaysAllow.rawValue).tag(RememberChoice.alwaysAllow)
                    Text(RememberChoice.alwaysDeny.rawValue).tag(RememberChoice.alwaysDeny)
                }
            }
            .pickerStyle(.segmented)

            HStack(spacing: 12) {
                Button {
                    applyRemember(request: request, payload: payload, approved: false)
                } label: {
                    Text(payload.denyLabel.isEmpty ? "拒绝" : payload.denyLabel)
                        .font(DuduTheme.bodyFont(weight: .medium))
                        .foregroundStyle(DuduTheme.duduText)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(DuduTheme.duduDivider)
                        .clipShape(RoundedRectangle(cornerRadius: DuduTheme.radiusChip))
                }
                Button {
                    applyRemember(request: request, payload: payload, approved: true)
                } label: {
                    Text(payload.approveLabel.isEmpty ? "允许" : payload.approveLabel)
                        .font(DuduTheme.bodyFont(weight: .medium))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(DuduTheme.pink)
                        .clipShape(RoundedRectangle(cornerRadius: DuduTheme.radiusChip))
                }
            }

            if let timeout = request.timeoutSeconds {
                Text("若 \(Int(timeout)) 秒内不作答，将自动拒绝。")
                    .font(DuduTheme.captionFont())
                    .foregroundStyle(DuduTheme.duduTextDim)
            }
        }
        .padding(16)
        .background(DuduTheme.duduCard)
        .clipShape(RoundedRectangle(cornerRadius: DuduTheme.radiusCard))
        .shadow(color: .black.opacity(0.12), radius: 16, y: 8)
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    // MARK: - 决策

    private func applyRemember(request: SuspendedRequest, payload: ApprovalPayload, approved: Bool) {
        let target = mcpTarget(of: payload)
        switch remember {
        case .none:
            suspension.respond(id: request.id, decision: approved ? .approved(grantSession: false) : .denied)
        case .session:
            // 会话放行只在"允许"时有意义；拒绝没有会话放行概念。
            suspension.respond(id: request.id, decision: approved ? .approved(grantSession: true) : .denied)
        case .alwaysAllow:
            if let t = target {
                // 引擎级持久：以后这个工具直接放行，不再走审批。
                MCPToolApprovalStore.shared.setNeedsApproval(false, serverId: t.server, tool: t.tool)
                denyList.setDenied(false, serverId: t.server, tool: t.tool)
            }
            suspension.respond(id: request.id, decision: approved ? .approved(grantSession: false) : .denied)
        case .alwaysDeny:
            if let t = target {
                denyList.setDenied(true, serverId: t.server, tool: t.tool)
            }
            suspension.respond(id: request.id, decision: .denied)
        }
    }
}
