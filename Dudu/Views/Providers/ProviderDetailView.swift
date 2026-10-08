import SwiftUI
import UIKit

// MARK: - ProviderDetailView · 服务详情
//
// Edits one ProviderInstance. Credential section is either the API-key field
// (SecureField, Keychain, never displayed back) or the OAuth login section,
// depending on instance.credentialType. Model entries can be added/removed.

struct ProviderDetailView: View {
    @EnvironmentObject private var store: ProviderConfigStore
    @EnvironmentObject private var nav: SettingsNavigator
    let instanceId: String
    @State private var showingDeleteConfirm = false
    @State private var showingAddModel = false
    @State private var kimiFlowItem: KimiFlowItem?
    @Environment(\.dismiss) private var dismiss

    private var instance: ProviderInstance? {
        store.instance(for: instanceId)
    }

    var body: some View {
        Group {
            if let instance {
                detailBody(instance)
            } else {
                Text("服务不存在")
                    .font(DuduTheme.bodyFont())
                    .foregroundStyle(DuduTheme.duduTextDim)
            }
        }
        .navigationTitle(instance?.label ?? "详情")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingAddModel) {
            AddModelView(instanceId: instanceId)
        }
        .sheet(item: $kimiFlowItem) { item in
            KimiDeviceFlowView(presentation: item.presentation)
        }
    }

    // MARK: Body

    @ViewBuilder
    private func detailBody(_ instance: ProviderInstance) -> some View {
        List {
            Section {
                labelRow(instance)
                enabledRow(instance)
            }

            Section {
                baseURLRow(instance)
                v1SuffixRow(instance)
                imageModeRow(instance)
            } header: {
                DuduSectionTitle("连接")
            }

            credentialSection(instance)

            // D24: 分享 —— 把这份配置生成二维码 / 分享文本发给别人
            Section {
                Button {
                    nav.path.append(SettingsRoute.providerShare(instance.id))
                } label: {
                    HStack(spacing: 12) {
                        DuduIcon(systemName: "qrcode")
                            .font(DuduTheme.appFont(size: 15))
                            .foregroundStyle(DuduTheme.pink)
                            .frame(width: 30, height: 30)
                            .background(DuduTheme.pinkSoft)
                            .clipShape(RoundedRectangle(cornerRadius: DuduTheme.radiusChip))
                        Text(AppLocalized("shareimport.shareEntry"))
                            .font(DuduTheme.bodyFont(weight: .medium))
                            .foregroundStyle(DuduTheme.duduText)
                        Spacer()
                        DuduIcon(systemName: "chevron.right")
                            .font(DuduTheme.appFont(size: 12, weight: .medium))
                            .foregroundStyle(DuduTheme.duduTextDim)
                    }
                    .frame(minHeight: 44)
                }
            }

            Section {
                let entries = store.entries(for: instance.id)
                if entries.isEmpty {
                    Text("暂无模型")
                        .font(DuduTheme.captionFont())
                        .foregroundStyle(DuduTheme.duduTextDim)
                }
                ForEach(entries) { entry in
                    HStack {
                        Text(entry.model.displayName)
                            .font(DuduTheme.bodyFont())
                            .foregroundStyle(DuduTheme.duduText)
                        Spacer()
                        Text(entry.model.id)
                            .font(DuduTheme.captionFont())
                            .foregroundStyle(DuduTheme.duduTextDim)
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            store.removeEntry(entry.uuid)
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                    }
                }
                Button {
                    showingAddModel = true
                } label: {
                    Label("添加模型", systemImage: "plus")
                        .font(DuduTheme.bodyFont())
                }
            } header: {
                DuduSectionTitle("模型")
            }

            Section {
                Button(role: .destructive) {
                    showingDeleteConfirm = true
                } label: {
                    Text("删除此服务")
                        .font(DuduTheme.bodyFont())
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .duduCardList()
        .confirmationDialog("删除此服务？", isPresented: $showingDeleteConfirm) {
            Button("删除", role: .destructive) {
                store.removeInstance(instance.id)
                dismiss()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("“\(instance.label)”及其模型条目将被删除。此操作不可撤销。")
        }
    }

    // MARK: Rows

    private func labelRow(_ instance: ProviderInstance) -> some View {
        HStack {
            Text("名称")
                .font(DuduTheme.bodyFont())
                .foregroundStyle(DuduTheme.duduText)
            Spacer()
            TextField("服务名称", text: Binding(
                get: { instance.label },
                set: { newValue in
                    var updated = instance
                    updated.label = newValue
                    store.updateInstance(updated)
                }
            ))
            .font(DuduTheme.bodyFont())
            .multilineTextAlignment(.trailing)
        }
    }

    private func enabledRow(_ instance: ProviderInstance) -> some View {
        Toggle("启用", isOn: Binding(
            get: { instance.isEnabled },
            set: { newValue in
                var updated = instance
                updated.isEnabled = newValue
                store.updateInstance(updated)
            }
        ))
        .font(DuduTheme.bodyFont())
        .tint(DuduTheme.pink)
    }

    private func baseURLRow(_ instance: ProviderInstance) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("自定义 Base URL")
                .font(DuduTheme.bodyFont())
                .foregroundStyle(DuduTheme.duduText)
            TextField("留空使用默认", text: Binding(
                get: { instance.customBaseURL ?? "" },
                set: { newValue in
                    var updated = instance
                    updated.customBaseURL = newValue.isEmpty ? nil : newValue
                    store.updateInstance(updated)
                }
            ))
            .font(DuduTheme.bodyFont())
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .foregroundStyle(DuduTheme.duduText)
            Text("代理或中转服务的地址")
                .font(DuduTheme.captionFont())
                .foregroundStyle(DuduTheme.duduTextDim)
        }
    }

    private func v1SuffixRow(_ instance: ProviderInstance) -> some View {
        Toggle("自动追加 /v1", isOn: Binding(
            get: { instance.appendV1Suffix },
            set: { newValue in
                var updated = instance
                updated.appendV1Suffix = newValue
                store.updateInstance(updated)
            }
        ))
        .font(DuduTheme.bodyFont())
        .tint(DuduTheme.pink)
    }

    private func imageModeRow(_ instance: ProviderInstance) -> some View {
        Picker("图片接口模式", selection: Binding(
            get: { instance.imageEndpointMode },
            set: { newValue in
                var updated = instance
                updated.imageEndpointMode = newValue
                store.updateInstance(updated)
            }
        )) {
            ForEach(ImageEndpointMode.allCases, id: \.self) { mode in
                Text(mode.displayName).tag(mode)
            }
        }
        .font(DuduTheme.bodyFont())
    }

    // MARK: Credential section

    @ViewBuilder
    private func credentialSection(_ instance: ProviderInstance) -> some View {
        switch instance.credentialType {
        case .apiKey:
            Section {
                ApiKeyFieldView(instanceId: instance.id)
            } header: {
                DuduSectionTitle("API Key")
            }
            // 手动填写的服务也要可测：填 key → 测试连接 → 拉取模型列表。
            Section {
                ManualTestConnectionView(instanceId: instance.id)
            } header: {
                DuduSectionTitle(AppLocalized("manualsetup.test"))
            }
        case .oauth:
            Section {
                oauthBody(instance)
            } header: {
                DuduSectionTitle("OAuth 登录")
            }
        }
    }

    @ViewBuilder
    private func oauthBody(_ instance: ProviderInstance) -> some View {
        if let manager = instance.providerType.oauthManager {
            let authed = manager.isAuthenticated(instanceId: instance.id)
            if authed {
                HStack {
                    DuduIcon(systemName: "checkmark.circle.fill")
                        .foregroundStyle(DuduTheme.success)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("已登录")
                            .font(DuduTheme.bodyFont())
                            .foregroundStyle(DuduTheme.duduText)
                        if let masked = manager.maskedToken(instanceId: instance.id) {
                            Text(masked)
                                .font(DuduTheme.captionFont())
                                .foregroundStyle(DuduTheme.duduTextDim)
                        }
                    }
                    Spacer()
                    Button("退出登录") {
                        manager.logout(instanceId: instance.id)
                    }
                    .font(DuduTheme.bodyFont())
                    .foregroundStyle(DuduTheme.destructive)
                }
            } else {
                if instance.providerType == .kimiCode {
                    kimiLoginRow(instance)
                } else {
                    OAuthLoginButton(
                        title: "OAuth 登录",
                        login: {
                            try await oauthLogin(instance)
                        }
                    )
                }
            }
        } else {
            Text("该服务不支持 OAuth")
                .font(DuduTheme.captionFont())
                .foregroundStyle(DuduTheme.duduTextDim)
        }
    }

    /// Non-Kimi managers: login(instanceId:) async throws — verified in engine.
    private func oauthLogin(_ instance: ProviderInstance) async throws {
        switch instance.providerType {
        case .anthropic: try await ClaudeOAuthManager.shared.login(instanceId: instance.id)
        case .gemini: try await GeminiOAuthManager.shared.login(instanceId: instance.id)
        case .antigravity: try await AntigravityOAuthManager.shared.login(instanceId: instance.id)
        case .openRouter: try await OpenRouterOAuthManager.shared.login(instanceId: instance.id)
        case .xAI: try await XAIOAuthManager.shared.login(instanceId: instance.id)
        case .openAI, .openAIResponses: try await CodexOAuthManager.shared.login(instanceId: instance.id)
        default: break
        }
    }

    // MARK: Kimi device flow (engine-verified signature)

    private func kimiLoginRow(_ instance: ProviderInstance) -> some View {
        Group {
            if KimiOAuthManager.shared.isLoginAvailable {
                OAuthLoginButton(title: "OAuth 登录") {
                    try await KimiOAuthManager.shared.login(
                        instanceId: instance.id,
                        present: { presentation in
                            Task { @MainActor in
                                kimiFlowItem = KimiFlowItem(presentation: presentation)
                            }
                        }
                    )
                    // Polled to completion → dismiss the device-code sheet.
                    Task { @MainActor in kimiFlowItem = nil }
                }
            } else {
                Text("OAuth 未配置（缺少 client ID），暂无法登录")
                    .font(DuduTheme.captionFont())
                    .foregroundStyle(DuduTheme.duduTextDim)
            }
        }
    }
}

private struct KimiFlowItem: Identifiable {
    let id = UUID()
    let presentation: KimiOAuthManager.DeviceLoginPresentation
}

// MARK: - OAuth login button with error handling

private struct OAuthLoginButton: View {
    let title: String
    let login: () async throws -> Void
    @State private var isWorking = false
    @State private var errorText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                Task {
                    isWorking = true
                    errorText = nil
                    defer { isWorking = false }
                    do {
                        try await login()
                    } catch {
                        errorText = error.localizedDescription
                    }
                }
            } label: {
                HStack {
                    if isWorking {
                        ProgressView()
                    }
                    Text(title)
                        .font(DuduTheme.bodyFont(weight: .medium))
                }
            }
            .disabled(isWorking)
            if let errorText {
                Text(errorText)
                    .font(DuduTheme.captionFont())
                    .foregroundStyle(DuduTheme.destructive)
            }
        }
    }
}

// MARK: - Kimi device-code sheet

private struct KimiDeviceFlowView: View {
    let presentation: KimiOAuthManager.DeviceLoginPresentation
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("在浏览器中打开以下地址，输入验证码完成登录")
                    .font(DuduTheme.bodyFont())
                    .foregroundStyle(DuduTheme.duduText)
                    .multilineTextAlignment(.center)
                if let url = URL(string: presentation.verificationURL) {
                    Link(destination: url) {
                        Text(presentation.verificationURL)
                            .font(DuduTheme.bodyFont(weight: .medium))
                            .foregroundStyle(DuduTheme.pink)
                            .padding()
                            .background(DuduTheme.pinkSoft)
                            .clipShape(RoundedRectangle(cornerRadius: DuduTheme.radiusChip))
                    }
                }
                HStack {
                    Text("验证码")
                        .font(DuduTheme.captionFont())
                        .foregroundStyle(DuduTheme.duduTextDim)
                    Text(presentation.userCode)
                        .font(DuduTheme.titleFont())
                        .foregroundStyle(DuduTheme.duduText)
                    Button {
                        UIPasteboard.general.string = presentation.userCode
                    } label: {
                        DuduIcon(systemName: "doc.on.doc")
                    }
                }
                ProgressView()
                Text("等待验证中…")
                    .font(DuduTheme.captionFont())
                    .foregroundStyle(DuduTheme.duduTextDim)
                Spacer()
            }
            .padding()
            .navigationTitle("Kimi 登录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Add model

private struct AddModelView: View {
    let instanceId: String
    @EnvironmentObject private var store: ProviderConfigStore
    @Environment(\.dismiss) private var dismiss
    @State private var modelId = ""
    @State private var displayName = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("模型 ID（如 gpt-4o）", text: $modelId)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("显示名称（可选）", text: $displayName)
                }
            }
            .duduCardForm()
            .navigationTitle("添加模型")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        let trimmed = modelId.trimmingCharacters(in: .whitespaces)
                        guard !trimmed.isEmpty else { return }
                        let instance = store.instance(for: instanceId)
                        let model = LLMModel(
                            id: trimmed,
                            displayName: displayName.isEmpty ? trimmed : displayName,
                            provider: instance?.providerType.rawValue ?? ""
                        )
                        let entry = ModelEntry(
                            providerInstanceId: instanceId,
                            model: model,
                            isCustom: true
                        )
                        _ = store.addEntry(entry)
                        dismiss()
                    }
                    .disabled(modelId.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

private extension ImageEndpointMode {
    var displayName: String {
        switch self {
        case .auto: return "自动"
        case .imagesGenerations: return "images/generations"
        case .chatCompletions: return "chat/completions"
        }
    }
}
