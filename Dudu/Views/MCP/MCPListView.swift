import SwiftUI

// MARK: - MCPListView · MCP 服务器管理

/// Phase D3: MCP server management UI. Backed by the ported engine
/// (MCPStore / MCPToolApprovalStore); this file adds the missing UI only.
/// Each row: server name, transport summary, enabled toggle, status dot.
/// Add via sheet; delete with confirmation; tap a row for MCPDetailView.
struct MCPListView: View {
    @ObservedObject private var store = MCPStore.shared
    @State private var showingAdd = false
    @State private var pendingDelete: MCPServerConfig?

    var body: some View {
        List {
            if store.servers.isEmpty {
                Section {
                    VStack(spacing: 12) {
                        Image(systemName: "server.rack")
                            .font(.system(size: 36))
                            .foregroundStyle(DuduTheme.duduTextDim)
                        Text("还没有 MCP 服务器")
                            .font(DuduTheme.bodyFont())
                            .foregroundStyle(DuduTheme.duduText)
                        Text("添加一个 MCP 服务器，AI 就能调用它提供的工具。")
                            .font(DuduTheme.captionFont())
                            .foregroundStyle(DuduTheme.duduTextDim)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                }
            } else {
                Section {
                    ForEach(store.servers) { server in
                        NavigationLink {
                            MCPDetailView(serverId: server.id)
                        } label: {
                            MCPServerRow(server: server)
                        }
                    }
                    .onDelete { indexSet in
                        // Confirm each deletion; only the first is queued.
                        if let first = indexSet.first {
                            pendingDelete = store.servers[first]
                        }
                    }
                } header: {
                    DuduSectionTitle("服务器")
                } footer: {
                    DuduSectionFooter {
                        Text("关闭的服务器不会被 AI 使用。工具调用默认需要批准。")
                    }
                }
            }
        }
        .duduCardList()
        .navigationTitle("MCP 服务器")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingAdd = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAdd) {
            MCPAddServerSheet()
        }
        .confirmationDialog(
            "删除这个服务器？",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                if let server = pendingDelete {
                    store.delete(id: server.id)
                }
                pendingDelete = nil
            }
            Button("取消", role: .cancel) { pendingDelete = nil }
        } message: {
            Text("服务器「\(pendingDelete?.id ?? "")」及其工具审批配置会被删掉，无法恢复。")
        }
    }
}

// MARK: - Server row

private struct MCPServerRow: View {
    @ObservedObject private var store = MCPStore.shared
    let server: MCPServerConfig

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(server.enabled ? DuduTheme.pink : DuduTheme.duduDivider)
                .frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 4) {
                Text(server.id)
                    .font(DuduTheme.bodyFont(weight: .medium))
                    .foregroundStyle(DuduTheme.duduText)
                Text(transportLine)
                    .font(DuduTheme.captionFont())
                    .foregroundStyle(DuduTheme.duduTextDim)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { server.enabled },
                set: { _ in store.toggle(id: server.id) }
            ))
            .labelsHidden()
            .tint(DuduTheme.pink)
        }
        .frame(minHeight: 52)
    }

    private var transportLine: String {
        if !server.transportSummary.isEmpty { return server.transportSummary }
        if server.isHTTP { return "HTTP" }
        if server.isSTDIO { return "本地命令" }
        return "未配置接入方式"
    }
}

// MARK: - Add server sheet

private struct MCPAddServerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = MCPStore.shared

    @State private var name = ""
    @State private var transport: TransportKind = .http
    @State private var url = ""
    @State private var command = ""
    @State private var argsText = ""
    @State private var errorMessage: String?

    private enum TransportKind: String, CaseIterable, Identifiable {
        case http = "HTTP 地址"
        case stdio = "本地命令"
        var id: String { rawValue }
    }

    private var isValid: Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return false }
        switch transport {
        case .http:
            return !url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .stdio:
            return !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("服务器名称", text: $name)
                    Picker("接入方式", selection: $transport) {
                        ForEach(TransportKind.allCases) { kind in
                            Text(kind.rawValue).tag(kind)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                Section {
                    if transport == .http {
                        TextField("https://…", text: $url)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    } else {
                        TextField("命令（如 npx）", text: $command)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        TextField("参数（空格分隔，可空）", text: $argsText)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                } footer: {
                    DuduSectionFooter {
                        if let errorMessage {
                            Text(errorMessage)
                        } else {
                            Text(transport == .http
                                ? "填 MCP 服务的 HTTP 地址。"
                                : "填本地启动命令和参数，多个参数用空格隔开。")
                        }
                    }
                }
            }
            .duduCardForm()
            .navigationTitle("添加服务器")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("添加") { addServer() }
                        .disabled(!isValid)
                }
            }
        }
    }

    private func addServer() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { errorMessage = "先给服务器起个名字。"; return }
        let config: MCPServerConfig
        switch transport {
        case .http:
            let u = url.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !u.isEmpty else { errorMessage = "填一下 HTTP 地址。"; return }
            config = MCPServerConfig(
                id: trimmedName, note: nil, enabled: true,
                createdAt: nil, updatedAt: nil,
                url: u, headers: nil, oauth: nil,
                command: nil, args: nil, env: nil,
                startupTimeoutSeconds: nil, toolApprovals: nil
            )
        case .stdio:
            let c = command.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !c.isEmpty else { errorMessage = "填一下启动命令。"; return }
            let args = argsText.split(separator: " ").map(String.init)
            config = MCPServerConfig(
                id: trimmedName, note: nil, enabled: true,
                createdAt: nil, updatedAt: nil,
                url: nil, headers: nil, oauth: nil,
                command: c, args: args.isEmpty ? nil : args, env: nil,
                startupTimeoutSeconds: nil, toolApprovals: nil
            )
        }
        store.add(config)
        dismiss()
    }
}
