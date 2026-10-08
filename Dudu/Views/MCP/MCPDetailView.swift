import SwiftUI

// MARK: - MCPDetailView · 服务器详情 + 逐工具审批管理

/// Phase D3: detail page for one MCP server. Server info section plus the
/// per-tool approval list backed by MCPStore.refreshTools (engine) and
/// MCPToolApprovalStore (engine). "调用前需批准" off = AI 可直接调用。
struct MCPDetailView: View {
    @ObservedObject private var store = MCPStore.shared
    @ObservedObject private var approvals = MCPToolApprovalStore.shared
    @Environment(\.dismiss) private var dismiss
    let serverId: String

    @State private var tools: [MCPStore.MCPToolInfo] = []
    @State private var isLoadingTools = false
    @State private var toolsError: String?
    @State private var showingDeleteConfirm = false
    /// "调用前需批准"开着的工具，点"测试"先走这个确认框——测试是真实调用一次，不是模拟。
    @State private var showingTestConfirm = false
    @State private var pendingTestTool: MCPStore.MCPToolInfo?
    @State private var pendingTestToolName: String?
    /// 逐工具"测试"的状态机：视图活着期间状态一直在这儿，滚动不丢。
    @StateObject private var tester = MCPToolTester()

    private var server: MCPServerConfig? {
        store.servers.first { $0.id == serverId }
    }

    var body: some View {
        List {
            Section {
                if let server {
                    detailRow(label: "名称", value: server.id)
                    detailRow(label: "接入方式", value: server.isHTTP ? "HTTP" : server.isSTDIO ? "本地命令" : "未配置")
                    if !server.transportSummary.isEmpty {
                        detailRow(label: "目标", value: server.transportSummary)
                    }
                    HStack {
                        Text("启用")
                            .font(DuduTheme.bodyFont())
                            .foregroundStyle(DuduTheme.duduText)
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { server.enabled },
                            set: { _ in store.toggle(id: server.id) }
                        ))
                        .labelsHidden()
                        .tint(DuduTheme.pink)
                    }
                } else {
                    Text("这个服务器已经被删除了。")
                        .font(DuduTheme.bodyFont())
                        .foregroundStyle(DuduTheme.duduTextDim)
                }
            } header: {
                DuduSectionTitle("服务器信息")
            }

            Section {
                if isLoadingTools {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                    .padding(.vertical, 8)
                } else if let toolsError {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(toolsError)
                            .font(DuduTheme.captionFont())
                            .foregroundStyle(DuduTheme.duduTextDim)
                        Button("重试") {
                            Task { await loadTools() }
                        }
                        .font(DuduTheme.bodyFont(weight: .medium))
                        .foregroundStyle(DuduTheme.pink)
                    }
                    .padding(.vertical, 4)
                } else if tools.isEmpty {
                    Text("没有读到工具。服务器可能还没连上，或它本来就没有工具。")
                        .font(DuduTheme.bodyFont())
                        .foregroundStyle(DuduTheme.duduTextDim)
                        .padding(.vertical, 4)
                } else {
                    ForEach(tools) { tool in
                        toolRow(tool)
                    }
                }
            } header: {
                DuduSectionTitle("工具（逐个管理）")
            } footer: {
                DuduSectionFooter {
                    Text("「调用前需批准」打开时，AI 每次用这个工具都会先弹窗问你；关掉后可直接调用，不再弹窗。每个工具旁边都有「测试」，点一下就能直接试调一次，看看通不通。")
                }
            }

            if server != nil {
                Section {
                    Button(role: .destructive) {
                        showingDeleteConfirm = true
                    } label: {
                        Text("删除服务器")
                            .font(DuduTheme.bodyFont(weight: .medium))
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .duduCardList()
        .navigationTitle(serverId)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await loadTools() }
                } label: {
                    DuduIcon(systemName: "arrow.clockwise")
                }
                .disabled(isLoadingTools)
            }
        }
        .task {
            await loadTools()
        }
        .confirmationDialog(
            "删除这个服务器？",
            isPresented: $showingDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                store.delete(id: serverId)
                dismiss()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("服务器「\(serverId)」及其工具审批配置会被删掉，无法恢复。")
        }
        .confirmationDialog(
            "试一下这个工具？",
            isPresented: $showingTestConfirm,
            titleVisibility: .visible
        ) {
            Button("确认") {
                if let tool = pendingTestTool {
                    tester.test(serverId: serverId, toolName: tool.name)
                } else if let name = pendingTestToolName {
                    tester.test(serverId: serverId, toolName: name)
                }
                pendingTestTool = nil
                pendingTestToolName = nil
            }
            Button("取消", role: .cancel) {
                pendingTestTool = nil
                pendingTestToolName = nil
            }
        } message: {
            Text("测试会真实调用一次「\(pendingTestTool?.name ?? pendingTestToolName ?? "")」，不是演习——能发邮件的工具会真的发出去，能删东西的工具会真的删掉。想好再点确认。")
        }
        .onDisappear {
            // 没跑完的探针停掉，避免后台转圈。
            tester.cancelAll()
        }
        .alert(tester.detailTitle, isPresented: $tester.showingDetail) {
            Button("再试一次") {
                if let tool = tools.first(where: { $0.name == tester.detailToolName }) {
                    requestTest(tool)
                } else {
                    // 工具已不在当前列表里：照样按名字查审批，不能绕过。
                    requestTest(toolName: tester.detailToolName)
                }
            }
            Button("知道了", role: .cancel) {}
        } message: {
            Text(tester.detailText.isEmpty ? "没有更多信息。" : tester.detailText)
        }
    }

    // MARK: - Tool row

    private func toolRow(_ tool: MCPStore.MCPToolInfo) -> some View {
        let needsApproval = approvals.needsApproval(serverId: serverId, tool: tool.name)
        let testStatus = tester.status(of: tool.name)
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(tool.name)
                    .font(DuduTheme.bodyFont(weight: .medium))
                    .foregroundStyle(DuduTheme.duduText)
                Spacer()
                Button {
                    requestTest(tool)
                } label: {
                    Text("测试")
                        .font(DuduTheme.bodyFont(weight: .medium))
                        .foregroundStyle(DuduTheme.pink)
                        .frame(minWidth: 64, minHeight: 44)
                        .background(DuduTheme.pinkSoft)
                        .clipShape(Capsule())
                }
                .disabled(testStatus == .testing)
                .opacity(testStatus == .testing ? 0.5 : 1)
                Toggle("调用前需批准", isOn: Binding(
                    get: { needsApproval },
                    set: { approvals.setNeedsApproval($0, serverId: serverId, tool: tool.name) }
                ))
                .labelsHidden()
                .tint(DuduTheme.pink)
            }
            if !tool.description.isEmpty {
                Text(tool.description)
                    .font(DuduTheme.captionFont())
                    .foregroundStyle(DuduTheme.duduTextDim)
            }
            Text(needsApproval ? "每次调用前都会弹窗问你。" : "AI 可直接调用，不再弹窗。")
                .font(DuduTheme.captionFont())
                .foregroundStyle(DuduTheme.duduTextDim)
            testStatusLine(for: tool, status: testStatus)
        }
        .padding(.vertical, 4)
    }

    // MARK: - 测试状态行

    /// 每行的测试状态：没测 → 转圈 → 通过 / 连通（缺参数）/ 失败。
    /// 失败和"连通（缺参数）"可点，点开看完整返回。
    @ViewBuilder
    private func testStatusLine(for tool: MCPStore.MCPToolInfo,
                               status: MCPToolTester.ToolTestStatus) -> some View {
        switch status {
        case .idle:
            EmptyView()
        case .testing:
            HStack(spacing: 8) {
                ProgressView()
                Text("正在试着调用…")
                    .font(DuduTheme.captionFont())
                    .foregroundStyle(DuduTheme.duduTextDim)
            }
            .frame(minHeight: 44, alignment: .leading)
        case .passed:
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(DuduTheme.success)
                Text("通过")
                    .font(DuduTheme.captionFont(weight: .medium))
                    .foregroundStyle(DuduTheme.success)
            }
            .frame(minHeight: 44, alignment: .leading)
        case .reachable:
            Button {
                tester.showDetail(for: tool.name)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                        .foregroundStyle(DuduTheme.success)
                    Text("连通了（这次没带参数）")
                        .font(DuduTheme.captionFont(weight: .medium))
                        .foregroundStyle(DuduTheme.success)
                    Image(systemName: "chevron.right")
                        .font(DuduTheme.captionFont())
                        .foregroundStyle(DuduTheme.duduTextDim)
                }
                .frame(minHeight: 44, alignment: .leading)
            }
        case .failed(let short):
            Button {
                tester.showDetail(for: tool.name)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(DuduTheme.duduDestructive)
                    Text(short)
                        .font(DuduTheme.captionFont())
                        .foregroundStyle(DuduTheme.duduDestructive)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Image(systemName: "chevron.right")
                        .font(DuduTheme.captionFont())
                        .foregroundStyle(DuduTheme.duduTextDim)
                }
                .frame(minHeight: 44, alignment: .leading)
            }
        }
    }

    // MARK: - Helpers

    /// "测试"的统一入口：这个工具开了"调用前需批准"时，先弹窗确认——
    /// 测试是真实调用一次，不是模拟，不能绕过审批开关。
    private func requestTest(_ tool: MCPStore.MCPToolInfo) {
        requestTest(toolName: tool.name, pending: tool)
    }

    /// 按名字测试的统一入口（工具已不在列表里时的兜底路径）。
    private func requestTest(toolName: String, pending: MCPStore.MCPToolInfo? = nil) {
        if approvals.needsApproval(serverId: serverId, tool: toolName) {
            pendingTestTool = pending
            pendingTestToolName = pending == nil ? toolName : nil
            showingTestConfirm = true
        } else {
            tester.test(serverId: serverId, toolName: toolName)
        }
    }

    private func detailRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(DuduTheme.bodyFont())
                .foregroundStyle(DuduTheme.duduTextDim)
            Spacer()
            Text(value)
                .font(DuduTheme.bodyFont())
                .foregroundStyle(DuduTheme.duduText)
                .multilineTextAlignment(.trailing)
        }
    }

    private func loadTools() async {
        guard !isLoadingTools else { return }
        isLoadingTools = true
        toolsError = nil
        defer { isLoadingTools = false }
        do {
            tools = try await store.refreshTools(server: serverId)
        } catch {
            toolsError = error.localizedDescription
        }
    }
}
