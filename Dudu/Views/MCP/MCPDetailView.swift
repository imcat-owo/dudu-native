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
                    Text("「调用前需批准」打开时，AI 每次用这个工具都会先弹窗问你；关掉后可直接调用，不再弹窗。")
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
                    Image(systemName: "arrow.clockwise")
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
    }

    // MARK: - Tool row

    private func toolRow(_ tool: MCPStore.MCPToolInfo) -> some View {
        let needsApproval = approvals.needsApproval(serverId: serverId, tool: tool.name)
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(tool.name)
                    .font(DuduTheme.bodyFont(weight: .medium))
                    .foregroundStyle(DuduTheme.duduText)
                Spacer()
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
        }
        .padding(.vertical, 4)
    }

    // MARK: - Helpers

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
