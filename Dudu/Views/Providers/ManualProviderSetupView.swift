import SwiftUI
import Security

// MARK: - ManualProviderSetupView · 手动填写服务
//
// Kelivo-style manual provider setup: pick a protocol (or a preset type),
// type in Base URL + API key + model name, hit 测试连接, and see an HONEST
// result — the raw /v1/models probe, no models.dev / built-in fallbacks, so a
// bad key or bad URL fails loudly instead of "succeeding" with a fake list.
//
// The key is saved through the same honest Keychain path as ApiKeyFieldView:
// saveAPIKey's OSStatus is checked, and a failure aborts with the real error
// instead of claiming success.

// MARK: - Manual protocol (for the "custom" entry)

/// Wire protocol a manually-entered service speaks. Maps onto the existing
/// ProviderType so the whole engine (chat, refresh, routing) just works.
enum ManualProviderProtocol: String, CaseIterable {
    case openAICompatible
    case anthropicCompatible
    case gemini

    var providerType: ProviderType {
        switch self {
        case .openAICompatible: return .openAI
        case .anthropicCompatible: return .anthropic
        case .gemini: return .gemini
        }
    }

    var displayName: String {
        switch self {
        case .openAICompatible: return AppLocalized("manualsetup.protocol.openai")
        case .anthropicCompatible: return AppLocalized("manualsetup.protocol.anthropic")
        case .gemini: return AppLocalized("manualsetup.protocol.gemini")
        }
    }

    /// Official default base shown as the field placeholder. Empty = default.
    var defaultBaseURL: String {
        switch self {
        case .openAICompatible: return "https://api.openai.com"
        case .anthropicCompatible: return "https://api.anthropic.com"
        case .gemini: return "https://generativelanguage.googleapis.com"
        }
    }
}

extension ProviderType {
    /// Provider types that accept a manually-typed API key instead of OAuth.
    /// Antigravity is OAuth-only (its API-key path just returns built-ins),
    /// so it keeps OAuth as the only option.
    var supportsManualEntry: Bool {
        switch self {
        case .anthropic, .openAI, .openAIResponses, .gemini, .openRouter, .xAI, .kimiCode:
            return true
        case .antigravity, .unsupported:
            return false
        }
    }

    /// Default base URL shown as placeholder in the manual-entry Base URL field.
    /// nil = the field is not applicable (OpenRouter is official-endpoint only).
    var manualDefaultBaseURL: String? {
        switch self {
        case .anthropic: return "https://api.anthropic.com"
        case .openAI, .openAIResponses: return "https://api.openai.com"
        case .gemini: return "https://generativelanguage.googleapis.com"
        case .xAI: return "https://api.x.ai/v1"
        case .kimiCode: return "https://api.kimi.com/coding"
        case .openRouter: return nil
        case .antigravity, .unsupported: return nil
        }
    }
}

// MARK: - Sheet request

/// Identifiable request driving the manual-setup sheet.
/// `presetType == nil` → the user picks the protocol (the "custom" row).
struct ManualSetupRequest: Identifiable {
    let id = UUID()
    let presetType: ProviderType?
}

// MARK: - Connection tester (shared by setup + detail views)

/// Phases of a connection test / model-list fetch.
enum ManualConnectionPhase {
    case idle
    case testing
    case success(models: [LLMModel])
    /// Connected, but the API returned no model list — user types names by hand.
    case emptySuccess
    /// Detail view: fetch applied, list replaced.
    case fetched(count: Int)
    /// Detail view: fetch returned empty, existing list kept.
    case emptyKept
    case failure(message: String)
}

enum ProviderConnectionTester {
    /// Raw /v1/models probe against the instance's real API — deliberately
    /// WITHOUT the models.dev / built-in fallbacks of fetchModelsWithFallback,
    /// so a wrong key or wrong URL fails HONESTLY instead of "succeeding"
    /// with a fabricated list. The caller must have saved the key to the
    /// Keychain already (fetchModelsForInstance reads it from there).
    static func test(instance: ProviderInstance) async -> Result<[LLMModel], Error> {
        do {
            let models = try await ProviderConfigStore.fetchModelsForInstance(instance, forceRefresh: true)
            return .success(models)
        } catch {
            return .failure(error)
        }
    }

    /// Honest, user-facing message for a test failure. Common cases get
    /// Chinese copy; anything else surfaces the underlying detail verbatim
    /// rather than a generic "failed".
    static func friendlyMessage(_ error: Error) -> String {
        if let llm = error as? LLMError {
            switch llm {
            case .invalidAPIKey:
                return AppLocalized("manualsetup.errInvalidKey")
            case .networkError(let underlying):
                return String(format: AppLocalized("manualsetup.errNetwork"), underlying.localizedDescription)
            case .providerError(let message), .transientError(let message):
                return message
            case .decodingError:
                return AppLocalized("manualsetup.errDecoding")
            case .rateLimited:
                return AppLocalized("manualsetup.errRateLimited")
            case .cancelled:
                return AppLocalized("manualsetup.errCancelled")
            case .unknown:
                return AppLocalized("manualsetup.errUnknown")
            }
        }
        if let refresh = error as? ModelRefreshError {
            return refresh.errorDescription ?? AppLocalized("manualsetup.errUnknown")
        }
        return error.localizedDescription
    }
}

// MARK: - Manual setup view

struct ManualProviderSetupView: View {
    @EnvironmentObject private var store: ProviderConfigStore
    @Environment(\.dismiss) private var dismiss

    let request: ManualSetupRequest
    /// Called with the new instance id after a successful save, so the
    /// presenter (e.g. the type picker sheet) can dismiss itself too and
    /// navigate to the new instance's detail page.
    var onSaved: ((String) -> Void)?

    @State private var draftId = UUID().uuidString
    @State private var name = ""
    @State private var selectedProtocol: ManualProviderProtocol = .openAICompatible
    @State private var baseURL = ""
    @State private var apiKey = ""
    @State private var showKey = false
    @State private var appendV1 = true
    @State private var phase: ManualConnectionPhase = .idle
    @State private var keySavedForTest = false
    @State private var didSave = false
    @State private var saveError: String?
    @State private var manualModelName = ""
    @State private var pendingManualModels: [String] = []

    /// The provider type this setup produces.
    private var resolvedType: ProviderType {
        request.presetType ?? selectedProtocol.providerType
    }

    private var basePlaceholder: String {
        if let preset = request.presetType {
            return preset.manualDefaultBaseURL ?? ""
        }
        return selectedProtocol.defaultBaseURL
    }

    /// OpenRouter keys only work against the official endpoint — the engine
    /// ignores customBaseURL for it, so don't offer the field at all.
    private var showsBaseURLField: Bool {
        resolvedType != .openRouter
    }

    private var draftInstance: ProviderInstance {
        let trimmedBase = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        return ProviderInstance(
            id: draftId,
            label: name.trimmingCharacters(in: .whitespacesAndNewlines),
            providerType: resolvedType,
            credentialType: .apiKey,
            customBaseURL: trimmedBase.isEmpty ? nil : trimmedBase,
            appendV1Suffix: appendV1
        )
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Text(AppLocalized("manualsetup.name"))
                            .font(DuduTheme.bodyFont())
                            .foregroundStyle(DuduTheme.duduText)
                        Spacer()
                        TextField(
                            AppLocalized("manualsetup.namePlaceholder"),
                            text: $name
                        )
                        .font(DuduTheme.bodyFont())
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(DuduTheme.duduText)
                    }
                }

                if request.presetType == nil {
                    Section(AppLocalized("manualsetup.protocol")) {
                        Picker(AppLocalized("manualsetup.protocol"), selection: $selectedProtocol) {
                            ForEach(ManualProviderProtocol.allCases, id: \.self) { proto in
                                Text(proto.displayName).tag(proto)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                }

                Section {
                    if showsBaseURLField {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Base URL")
                                .font(DuduTheme.bodyFont())
                                .foregroundStyle(DuduTheme.duduText)
                            TextField(basePlaceholder, text: $baseURL)
                                .font(DuduTheme.bodyFont())
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .foregroundStyle(DuduTheme.duduText)
                            Text(AppLocalized("manualsetup.baseURLHint"))
                                .font(DuduTheme.captionFont())
                                .foregroundStyle(DuduTheme.duduTextDim)
                        }
                    } else {
                        Text(AppLocalized("manualsetup.openrouterNote"))
                            .font(DuduTheme.captionFont())
                            .foregroundStyle(DuduTheme.duduTextDim)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(AppLocalized("manualsetup.apiKey"))
                                .font(DuduTheme.bodyFont())
                                .foregroundStyle(DuduTheme.duduText)
                            Spacer()
                            Button(showKey ? AppLocalized("manualsetup.hideKey") : AppLocalized("manualsetup.showKey")) {
                                showKey.toggle()
                            }
                            .font(DuduTheme.captionFont())
                            .foregroundStyle(DuduTheme.pink)
                        }
                        Group {
                            if showKey {
                                TextField(AppLocalized("manualsetup.apiKeyPlaceholder"), text: $apiKey)
                            } else {
                                SecureField(AppLocalized("manualsetup.apiKeyPlaceholder"), text: $apiKey)
                            }
                        }
                        .font(DuduTheme.bodyFont())
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(10)
                        .background(DuduTheme.duduCard)
                        .clipShape(RoundedRectangle(cornerRadius: DuduTheme.radiusChip))
                        .overlay(
                            RoundedRectangle(cornerRadius: DuduTheme.radiusChip)
                                .stroke(DuduTheme.duduDivider, lineWidth: 1)
                        )
                    }

                    if showsBaseURLField {
                        Toggle(AppLocalized("manualsetup.appendV1"), isOn: $appendV1)
                            .font(DuduTheme.bodyFont())
                            .tint(DuduTheme.pink)
                    }
                } header: {
                    Text(AppLocalized("manualsetup.connection"))
                }

                Section {
                    Button {
                        testConnection()
                    } label: {
                        HStack {
                            if case .testing = phase {
                                ProgressView()
                            }
                            Text(AppLocalized("manualsetup.test"))
                                .font(DuduTheme.bodyFont(weight: .medium))
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .disabled(isTesting)

                    testStatusView

                    if let saveError {
                        Text(saveError)
                            .font(DuduTheme.captionFont())
                            .foregroundStyle(DuduTheme.destructive)
                    }
                }

                modelSection
            }
            .listStyle(.insetGrouped)
            .navigationTitle(AppLocalized("manualsetup.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppLocalized("manualsetup.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(AppLocalized("manualsetup.save")) { save() }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isTesting)
                }
            }
            .onChange(of: apiKey) { resetTestOnInputChange() }
            .onChange(of: baseURL) { resetTestOnInputChange() }
            .onChange(of: selectedProtocol) { resetTestOnInputChange() }
            .onDisappear {
                // Tested but never saved: don't leave an orphan key behind.
                if !didSave, keySavedForTest {
                    ProviderKeychainHelper.deleteAPIKey(instanceId: draftId, caller: "ManualProviderSetupView.cancel")
                }
            }
        }
    }

    private var isTesting: Bool {
        if case .testing = phase { return true }
        return false
    }

    private func resetTestOnInputChange() {
        // A stale success must not survive an input change.
        if case .testing = phase { return }
        phase = .idle
        saveError = nil
    }

    // MARK: - Test status

    @ViewBuilder
    private var testStatusView: some View {
        switch phase {
        case .idle:
            EmptyView()
        case .testing:
            HStack(spacing: 6) {
                ProgressView()
                Text(AppLocalized("manualsetup.testing"))
                    .font(DuduTheme.captionFont())
                    .foregroundStyle(DuduTheme.duduTextDim)
            }
        case .success(let models):
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(DuduTheme.success)
                Text(String(format: AppLocalized("manualsetup.testSuccessCount"), models.count))
                    .font(DuduTheme.captionFont())
                    .foregroundStyle(DuduTheme.duduText)
            }
        case .emptySuccess:
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(DuduTheme.success)
                Text(AppLocalized("manualsetup.testEmpty"))
                    .font(DuduTheme.captionFont())
                    .foregroundStyle(DuduTheme.duduText)
            }
        case .failure(let message):
            HStack(spacing: 6) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(DuduTheme.destructive)
                VStack(alignment: .leading, spacing: 2) {
                    Text(AppLocalized("manualsetup.testFailed"))
                        .font(DuduTheme.captionFont(weight: .medium))
                        .foregroundStyle(DuduTheme.destructive)
                    Text(message)
                        .font(DuduTheme.captionFont())
                        .foregroundStyle(DuduTheme.duduTextDim)
                }
            }
        case .fetched, .emptyKept:
            // Detail-view-only phases; unreachable here.
            EmptyView()
        }
    }

    // MARK: - Models section

    @ViewBuilder
    private var modelSection: some View {
        switch phase {
        case .success(let models):
            Section(AppLocalized("manualsetup.models")) {
                ForEach(models.prefix(8)) { model in
                    HStack {
                        Text(model.displayName)
                            .font(DuduTheme.bodyFont())
                            .foregroundStyle(DuduTheme.duduText)
                        Spacer()
                        Text(model.id)
                            .font(DuduTheme.captionFont())
                            .foregroundStyle(DuduTheme.duduTextDim)
                    }
                }
                if models.count > 8 {
                    Text(String(format: AppLocalized("manualsetup.moreModels"), models.count - 8))
                        .font(DuduTheme.captionFont())
                        .foregroundStyle(DuduTheme.duduTextDim)
                }
            }
        case .emptySuccess:
            Section(AppLocalized("manualsetup.models")) {
                manualModelAdder
            }
        case .idle, .testing, .failure, .fetched, .emptyKept:
            EmptyView()
        }
    }

    private var manualModelAdder: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField(AppLocalized("manualsetup.modelNamePlaceholder"), text: $manualModelName)
                    .font(DuduTheme.bodyFont())
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .foregroundStyle(DuduTheme.duduText)
                Button(AppLocalized("manualsetup.addModel")) {
                    let trimmed = manualModelName.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty, !pendingManualModels.contains(trimmed) else { return }
                    pendingManualModels.append(trimmed)
                    manualModelName = ""
                }
                .font(DuduTheme.bodyFont(weight: .medium))
                .foregroundStyle(DuduTheme.pink)
                .disabled(manualModelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            ForEach(pendingManualModels, id: \.self) { modelId in
                HStack {
                    Text(modelId)
                        .font(DuduTheme.bodyFont())
                        .foregroundStyle(DuduTheme.duduText)
                    Spacer()
                    Button {
                        pendingManualModels.removeAll { $0 == modelId }
                    } label: {
                        Image(systemName: "trash")
                            .foregroundStyle(DuduTheme.destructive)
                    }
                }
            }
        }
    }

    // MARK: - Test

    private func testConnection() {
        let trimmedBase = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedBase.isEmpty,
           !(trimmedBase.hasPrefix("http://") || trimmedBase.hasPrefix("https://")) {
            phase = .failure(message: AppLocalized("manualsetup.invalidBaseURL"))
            return
        }
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let draft = draftInstance
        if key.isEmpty, !draft.allowsEmptyAPIKey {
            phase = .failure(message: AppLocalized("manualsetup.needKey"))
            return
        }
        phase = .testing
        saveError = nil
        Task {
            // Honest Keychain write FIRST: the probe reads the key from the
            // Keychain, and a failed save must abort before any network call.
            let status = ProviderKeychainHelper.saveAPIKey(key, instanceId: draftId, caller: "ManualProviderSetupView.testConnection")
            guard status == errSecSuccess else {
                phase = .failure(message: String(format: AppLocalized("manualsetup.keySaveFailed"), status))
                return
            }
            keySavedForTest = true
            let result = await ProviderConnectionTester.test(instance: draft)
            switch result {
            case .success(let models):
                phase = models.isEmpty ? .emptySuccess : .success(models: models)
            case .failure(let error):
                phase = .failure(message: ProviderConnectionTester.friendlyMessage(error))
            }
        }
    }

    // MARK: - Save

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            saveError = AppLocalized("manualsetup.needName")
            return
        }
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let instance = ProviderInstance(
            id: draftId,
            label: trimmedName,
            providerType: resolvedType,
            credentialType: .apiKey,
            customBaseURL: {
                let b = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
                return b.isEmpty ? nil : b
            }(),
            appendV1Suffix: appendV1
        )
        if key.isEmpty, !instance.allowsEmptyAPIKey {
            saveError = AppLocalized("manualsetup.needKey")
            return
        }
        // Honest Keychain save: abort (and say so) if the write fails.
        let status = ProviderKeychainHelper.saveAPIKey(key, instanceId: instance.id, caller: "ManualProviderSetupView.save")
        guard status == errSecSuccess else {
            saveError = String(format: AppLocalized("manualsetup.keySaveFailed"), status)
            return
        }
        keySavedForTest = true
        store.addInstance(instance)
        // addInstance fires its own auto-refresh; write the models we already
        // probed so the list is exact even if the refresh races.
        if case .success(let models) = phase {
            store.replaceEntries(for: instance.id, models: models, caller: "ManualProviderSetupView.save")
        }
        // Hand-typed model names become custom entries (replaceEntries keeps them).
        for modelId in pendingManualModels {
            let model = LLMModel(
                id: modelId,
                displayName: modelDisplayName(from: modelId),
                provider: resolvedType.rawValue
            )
            _ = store.addEntry(ModelEntry(
                providerInstanceId: instance.id,
                model: model,
                isCustom: true
            ))
        }
        didSave = true
        dismiss()
        onSaved?(instance.id)
    }
}

// MARK: - Detail-view test / fetch section

/// 测试连接 + 拉取模型列表 for an existing API-key instance.
/// Same honest probe as the setup screen: raw /v1/models, no fallbacks.
struct ManualTestConnectionView: View {
    @EnvironmentObject private var store: ProviderConfigStore
    let instanceId: String
    @State private var phase: ManualConnectionPhase = .idle

    private var instance: ProviderInstance? {
        store.instance(for: instanceId)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 16) {
                Button(AppLocalized("manualsetup.test")) {
                    runTest()
                }
                .font(DuduTheme.bodyFont(weight: .medium))
                .disabled(isTesting)

                Button(AppLocalized("manualsetup.fetchModels")) {
                    runFetch()
                }
                .font(DuduTheme.bodyFont(weight: .medium))
                .disabled(isTesting)

                if isTesting {
                    ProgressView()
                }
            }

            switch phase {
            case .idle:
                EmptyView()
            case .testing:
                Text(AppLocalized("manualsetup.testing"))
                    .font(DuduTheme.captionFont())
                    .foregroundStyle(DuduTheme.duduTextDim)
            case .success(let models):
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(DuduTheme.success)
                    Text(String(format: AppLocalized("manualsetup.testSuccessCount"), models.count))
                        .font(DuduTheme.captionFont())
                        .foregroundStyle(DuduTheme.duduText)
                }
            case .emptySuccess:
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(DuduTheme.success)
                    Text(AppLocalized("manualsetup.testEmpty"))
                        .font(DuduTheme.captionFont())
                        .foregroundStyle(DuduTheme.duduText)
                }
            case .fetched(let count):
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(DuduTheme.success)
                    Text(String(format: AppLocalized("manualsetup.fetchSuccessCount"), count))
                        .font(DuduTheme.captionFont())
                        .foregroundStyle(DuduTheme.duduText)
                }
            case .emptyKept:
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(DuduTheme.pink)
                    Text(AppLocalized("manualsetup.fetchEmptyKept"))
                        .font(DuduTheme.captionFont())
                        .foregroundStyle(DuduTheme.duduText)
                }
            case .failure(let message):
                VStack(alignment: .leading, spacing: 2) {
                    Text(AppLocalized("manualsetup.testFailed"))
                        .font(DuduTheme.captionFont(weight: .medium))
                        .foregroundStyle(DuduTheme.destructive)
                    Text(message)
                        .font(DuduTheme.captionFont())
                        .foregroundStyle(DuduTheme.duduTextDim)
                }
            }
        }
    }

    private var isTesting: Bool {
        if case .testing = phase { return true }
        return false
    }

    /// Probe only — never touches the stored model list.
    private func runTest() {
        guard let instance else { return }
        phase = .testing
        Task {
            let result = await ProviderConnectionTester.test(instance: instance)
            switch result {
            case .success(let models):
                phase = models.isEmpty ? .emptySuccess : .success(models: models)
            case .failure(let error):
                phase = .failure(message: ProviderConnectionTester.friendlyMessage(error))
            }
        }
    }

    /// Probe + replace the stored model list on success. An empty result
    /// keeps the existing list (never wipes it on a bad probe).
    private func runFetch() {
        guard let instance else { return }
        phase = .testing
        Task {
            let result = await ProviderConnectionTester.test(instance: instance)
            switch result {
            case .success(let models):
                if models.isEmpty {
                    phase = .emptyKept
                } else {
                    store.replaceEntries(for: instance.id, models: models, caller: "ManualTestConnectionView")
                    phase = .fetched(count: models.count)
                }
            case .failure(let error):
                phase = .failure(message: ProviderConnectionTester.friendlyMessage(error))
            }
        }
    }
}
