import SwiftUI

// MARK: - ProviderListView · 模型服务列表
//
// Lists every ProviderInstance from ProviderConfigStore. Each row shows the
// provider label/type, a "configured" status dot, and an enable toggle.
// Real engine bindings — no stubs, no dead buttons.

struct ProviderListView: View {
    @EnvironmentObject private var store: ProviderConfigStore
    @EnvironmentObject private var nav: SettingsNavigator
    @State private var showingTypePicker = false
    @State private var pendingDelete: ProviderInstance?

    var body: some View {
        List {
            // D24: 扫码导入 —— 二维码 / 粘贴分享文本导入服务配置
            Section {
                Button {
                    nav.path.append(SettingsRoute.qrScan)
                } label: {
                    HStack(spacing: 12) {
                        DuduIcon(systemName: "qrcode.viewfinder")
                            .font(DuduTheme.appFont(size: 15))
                            .foregroundStyle(DuduTheme.pink)
                            .frame(width: 30, height: 30)
                            .background(DuduTheme.pinkSoft)
                            .clipShape(RoundedRectangle(cornerRadius: DuduTheme.radiusChip))
                        Text(AppLocalized("shareimport.scanEntry"))
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
            ForEach(store.instances) { instance in
                NavigationLink(value: SettingsRoute.providerDetail(instance.id)) {
                    ProviderRowView(instance: instance)
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        pendingDelete = instance
                    } label: {
                        Label("删除", systemImage: "trash")
                    }
                }
            }
        }
        .duduCardList()
        .navigationTitle("模型服务")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingTypePicker = true
                } label: {
                    DuduIcon(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingTypePicker) {
            ProviderTypePickerView()
        }
        .confirmationDialog(
            "删除此服务？",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            )
        ) {
            Button("删除", role: .destructive) {
                if let instance = pendingDelete {
                    store.removeInstance(instance.id)
                    pendingDelete = nil
                }
            }
            Button("取消", role: .cancel) {
                pendingDelete = nil
            }
        } message: {
            if let instance = pendingDelete {
                Text("“\(instance.label)”及其模型条目将被删除。此操作不可撤销。")
            }
        }
    }
}

// MARK: - Row

private struct ProviderRowView: View {
    @EnvironmentObject private var store: ProviderConfigStore
    let instance: ProviderInstance

    var body: some View {
        HStack(spacing: 12) {
            DuduIcon(systemName: instance.providerType.iconName)
                .font(DuduTheme.appFont(size: 17))
                .foregroundStyle(DuduTheme.pink)
                .frame(width: 32, height: 32)
                .background(DuduTheme.pinkSoft)
                .clipShape(RoundedRectangle(cornerRadius: DuduTheme.radiusChip))

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(instance.label)
                        .font(DuduTheme.bodyFont(weight: .medium))
                        .foregroundStyle(DuduTheme.duduText)
                    Circle()
                        .fill(configured ? DuduTheme.success : DuduTheme.duduTextDim.opacity(0.4))
                        .frame(width: 8, height: 8)
                }
                Text(instance.providerType.displayName)
                    .font(DuduTheme.captionFont())
                    .foregroundStyle(DuduTheme.duduTextDim)
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: { instance.isEnabled },
                set: { newValue in
                    var updated = instance
                    updated.isEnabled = newValue
                    store.updateInstance(updated)
                }
            ))
            .labelsHidden()
        }
        .frame(minHeight: 44)
    }

    /// Configured = credential actually stored. API key: Keychain timestamp.
    /// OAuth: the type's OAuth manager reports authenticated.
    private var configured: Bool {
        switch instance.credentialType {
        case .apiKey:
            return ProviderKeychainHelper.apiKeySavedAt(instanceId: instance.id) != .distantPast
        case .oauth:
            return instance.providerType.oauthManager?.isAuthenticated(instanceId: instance.id) ?? false
        }
    }
}

// MARK: - Provider type → SF icon + OAuth manager

extension ProviderType {
    /// SF Symbol for the type picker and rows.
    var iconName: String {
        switch self {
        case .anthropic: return "sparkles"
        case .gemini: return "globe"
        case .openAI: return "circle.hexagongrid"
        case .openAIResponses: return "circle.hexagongrid.fill"
        case .openRouter: return "arrow.triangle.swap"
        case .antigravity: return "cloud"
        case .xAI: return "xmark.circle"
        case .kimiCode: return "moon.stars"
        case .unsupported: return "questionmark.circle"
        }
    }

    /// The OAuth manager for this type, if one exists (all real, verified in engine).
    var oauthManager: (any ProviderOAuthManager)? {
        switch self {
        case .anthropic: return ClaudeOAuthManager.shared
        case .gemini: return GeminiOAuthManager.shared
        case .antigravity: return AntigravityOAuthManager.shared
        case .kimiCode: return KimiOAuthManager.shared
        case .openRouter: return OpenRouterOAuthManager.shared
        case .xAI: return XAIOAuthManager.shared
        case .openAI, .openAIResponses: return CodexOAuthManager.shared
        case .unsupported: return nil
        }
    }

    /// Types the UI allows creating new instances of (engine-recognized types only).
    static var creatable: [ProviderType] {
        [.anthropic, .openAI, .openAIResponses, .gemini, .openRouter, .antigravity, .xAI, .kimiCode]
    }
}

/// Small protocol covering the OAuth-manager surface the UI needs.
/// Every manager below is a real engine class with these exact methods (verified).
protocol ProviderOAuthManager {
    func isAuthenticated(instanceId: String) -> Bool
    func maskedToken(instanceId: String) -> String?
    func logout(instanceId: String)
}

extension ClaudeOAuthManager: ProviderOAuthManager {}
extension GeminiOAuthManager: ProviderOAuthManager {}
extension AntigravityOAuthManager: ProviderOAuthManager {}
extension KimiOAuthManager: ProviderOAuthManager {}
extension OpenRouterOAuthManager: ProviderOAuthManager {}
extension XAIOAuthManager: ProviderOAuthManager {}
extension CodexOAuthManager: ProviderOAuthManager {}

// MARK: - Type picker (add provider)

private struct ProviderTypePickerView: View {
    @EnvironmentObject private var store: ProviderConfigStore
    @EnvironmentObject private var nav: SettingsNavigator
    @Environment(\.dismiss) private var dismiss
    @State private var manualSetup: ManualSetupRequest?
    @State private var methodChoiceType: ProviderType?

    var body: some View {
        NavigationStack {
            List {
                // 手动填写 —— 自己填 Base URL + API Key + 模型，不走 OAuth。
                Section {
                    Button {
                        manualSetup = ManualSetupRequest(presetType: nil)
                    } label: {
                        pickerRow(
                            icon: "square.and.pencil",
                            title: AppLocalized("manualsetup.customRow"),
                            subtitle: AppLocalized("manualsetup.customRowSubtitle")
                        )
                    }
                } header: {
                    DuduSectionTitle(AppLocalized("manualsetup.customSection"))
                }

                Section {
                    ForEach(ProviderType.creatable, id: \.self) { type in
                        Button {
                            if type.supportsManualEntry, type.oauthManager != nil {
                                // OAuth 强制型的手动替代：让用户二选一。
                                methodChoiceType = type
                            } else {
                                createOAuthInstance(of: type)
                            }
                        } label: {
                            pickerRow(
                                icon: type.iconName,
                                title: type.displayName,
                                subtitle: pickerSubtitle(for: type)
                            )
                        }
                    }
                } header: {
                    DuduSectionTitle(AppLocalized("manualsetup.presetSection"))
                }
            }
            .duduCardList()
            .navigationTitle("添加服务")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
            .sheet(item: $manualSetup) { request in
                ManualProviderSetupView(request: request) { instanceId in
                    // Close the picker too, then land on the new instance's detail page.
                    dismiss()
                    DispatchQueue.main.async {
                        nav.path.append(SettingsRoute.providerDetail(instanceId))
                    }
                }
            }
            .confirmationDialog(
                AppLocalized("manualsetup.chooseMethod"),
                isPresented: Binding(
                    get: { methodChoiceType != nil },
                    set: { if !$0 { methodChoiceType = nil } }
                ),
                presenting: methodChoiceType
            ) { type in
                Button(AppLocalized("manualsetup.viaOAuth")) {
                    createOAuthInstance(of: type)
                }
                Button(AppLocalized("manualsetup.viaManual")) {
                    manualSetup = ManualSetupRequest(presetType: type)
                }
                Button("取消", role: .cancel) {}
            }
        }
    }

    private func pickerRow(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 12) {
            DuduIcon(systemName: icon)
                .font(DuduTheme.appFont(size: 17))
                .foregroundStyle(DuduTheme.pink)
                .frame(width: 32, height: 32)
                .background(DuduTheme.pinkSoft)
                .clipShape(RoundedRectangle(cornerRadius: DuduTheme.radiusChip))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(DuduTheme.bodyFont(weight: .medium))
                    .foregroundStyle(DuduTheme.duduText)
                Text(subtitle)
                    .font(DuduTheme.captionFont())
                    .foregroundStyle(DuduTheme.duduTextDim)
            }
            Spacer()
        }
    }

    private func pickerSubtitle(for type: ProviderType) -> String {
        if type.supportsManualEntry, type.oauthManager != nil {
            return AppLocalized("manualsetup.typeSubtitleBoth")
        }
        return type.oauthManager == nil ? "API Key" : "OAuth 登录"
    }

    private func createOAuthInstance(of type: ProviderType) {
        let credential: ProviderCredential = type.oauthManager == nil ? .apiKey : .oauth
        let instance = ProviderInstance(
            label: type.displayName,
            providerType: type,
            credentialType: credential
        )
        store.addInstance(instance)
        dismiss()
        // Jump straight into the new instance's detail page.
        DispatchQueue.main.async {
            nav.path.append(SettingsRoute.providerDetail(instance.id))
        }
    }
}
