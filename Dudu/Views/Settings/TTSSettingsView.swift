import SwiftUI
import UIKit

// MARK: - TTSSettingsView · 语音（Phase D1）

/// Voice settings: auto-read toggle, system-voice opt-in, playback speed,
/// built-in voice presets (free, no key), and the TTS service list
/// (custom URL + key, one service selected as the read-aloud target).
///
/// Engine note (verified against the ported voice engine): the native port
/// has no edge-tts vendor — the read-aloud chain resolves
/// selected TTS service → built-in preset → chat model's voice group →
/// system voice (system voice is opt-in here, OFF by default). The built-in
/// preset is selected by default so read-aloud works out of the box.
struct TTSSettingsView: View {
    @ObservedObject private var voiceState = VoiceOutputState.shared
    @State private var systemVoiceAllowed: Bool = VoiceOutputPreferences.systemVoiceAllowed
    @State private var speed: Float = VoiceOutputPreferences.speedMultiplier
    @State private var services: [TTSServiceOptions] = TTSServiceStore.shared.services
    @State private var selectedId: String? = TTSServiceStore.shared.selectedServiceId
    @State private var selectedPresetId: String = TTSBuiltInPresetStore.shared.selectedPresetId
    @State private var showingAdd = false
    @ObservedObject private var testPlayer = TTSVoiceTestPlayer.shared

    var body: some View {
        List {
            Section {
                Toggle(isOn: $voiceState.isEnabled) {
                    Label {
                        Text("自动朗读 AI 回复")
                            .font(DuduTheme.bodyFont())
                            .foregroundStyle(DuduTheme.duduText)
                    } icon: {
                        DuduIcon(systemName: "speaker.wave.2.fill")
                            .foregroundStyle(DuduTheme.pink)
                    }
                }

                Toggle(isOn: $systemVoiceAllowed) {
                    Text("系统语音")
                        .font(DuduTheme.bodyFont())
                        .foregroundStyle(DuduTheme.duduText)
                }
                .onChange(of: systemVoiceAllowed) { _, value in
                    VoiceOutputPreferences.systemVoiceAllowed = value
                }

                HStack {
                    Text("语速")
                        .font(DuduTheme.bodyFont())
                        .foregroundStyle(DuduTheme.duduText)
                    Spacer()
                    Picker("语速", selection: $speed) {
                        ForEach(VoiceOutputPreferences.speedSteps, id: \.self) { step in
                            Text(stepLabel(step))
                                .tag(step)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 200)
                }
                .onChange(of: speed) { _, value in
                    VoiceOutputPreferences.speedMultiplier = value
                    VoiceOutputPlayer.shared.setRate(value)
                }
            } header: {
                DuduSectionTitle("朗读")
            } footer: {
                DuduSectionFooter {
                    Text("关闭自动朗读后，仍可随时点消息下面的“朗读”单独读一条。")
                }
            }

            Section {
                ForEach(TTSBuiltInPresetStore.shared.presets) { preset in
                    presetRow(preset)
                }
            } header: {
                DuduSectionTitle("内置音色")
            } footer: {
                DuduSectionFooter {
                    Text("不用配密钥，开箱就能听。选了之后，朗读默认用它；哪天想换自己配的服务，回来点下面的就行。")
                }
            }

            Section {
                ForEach(services) { service in
                    NavigationLink {
                        TTSServiceEditor(existing: service) {
                            reload()
                        }
                    } label: {
                        HStack(spacing: 10) {
                            Button {
                                TTSServiceStore.shared.setSelectedServiceId(service.id)
                                reload()
                            } label: {
                                DuduIcon(systemName: selectedId == service.id
                                      ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selectedId == service.id
                                                     ? DuduTheme.pink : DuduTheme.duduTextDim)
                            }
                            .buttonStyle(.plain)
                            .frame(minWidth: 44, minHeight: 44)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(service.name.isEmpty ? service.kind.displayName : service.name)
                                    .font(DuduTheme.bodyFont())
                                    .foregroundStyle(DuduTheme.duduText)
                                Text("\(service.kind.displayName) · \(service.voice)")
                                    .font(DuduTheme.captionFont())
                                    .foregroundStyle(DuduTheme.duduTextDim)
                                let failed = testPlayer.failedReason(forKey: TTSVoiceTestPlayer.serviceKey(service))
                                if !failed.isEmpty {
                                    Text(failed)
                                        .font(DuduTheme.captionFont())
                                        .foregroundStyle(DuduTheme.duduTextDim)
                                }
                            }
                            Spacer()
                            if TTSServiceStore.shared.hasAPIKey(for: service) {
                                Text("已配密钥")
                                    .font(DuduTheme.captionFont())
                                    .foregroundStyle(DuduTheme.duduTextDim)
                            }
                            serviceTestButton(service)
                        }
                    }
                }

                Button {
                    showingAdd = true
                } label: {
                    HStack {
                        DuduIcon(systemName: "plus.circle.fill")
                            .foregroundStyle(DuduTheme.pink)
                        Text("添加语音服务")
                            .font(DuduTheme.bodyFont())
                            .foregroundStyle(DuduTheme.duduText)
                    }
                }
            } header: {
                DuduSectionTitle("语音服务")
            } footer: {
                DuduSectionFooter {
                    Text("朗读按顺序尝试：你选定的语音服务 → 内置音色 → 当前聊天模型的语音分组 → 系统语音（需在上方开启）。没选服务时，内置音色开箱就能读；服务配了密钥但连不上时，会如实告诉你。")
                }
            }
        }
        .duduCardList()
        .navigationTitle("语音")
        .onAppear { reload() }
        .onDisappear { testPlayer.stop() }
        .sheet(isPresented: $showingAdd) {
            NavigationStack {
                TTSServiceEditor(existing: nil) {
                    reload()
                }
            }
        }
    }

    private func reload() {
        services = TTSServiceStore.shared.services
        selectedId = TTSServiceStore.shared.selectedServiceId
        selectedPresetId = TTSBuiltInPresetStore.shared.selectedPresetId
    }

    // MARK: - Built-in preset rows

    /// A preset row is the active target only when no custom service is
    /// explicitly selected AND this preset is the selected one. Picking a
    /// preset releases the service selection (mutually exclusive); tapping a
    /// service row re-selects there.
    private func presetRow(_ preset: TTSBuiltInPreset) -> some View {
        let active = selectedId == nil && selectedPresetId == preset.id
        let key = TTSVoiceTestPlayer.presetKey(preset)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Button {
                    TTSBuiltInPresetStore.shared.setSelectedPresetId(preset.id)
                    reload()
                } label: {
                    DuduIcon(systemName: active ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(active ? DuduTheme.pink : DuduTheme.duduTextDim)
                }
                .buttonStyle(.plain)
                .frame(minWidth: 44, minHeight: 44)

                VStack(alignment: .leading, spacing: 2) {
                    Text(preset.title)
                        .font(DuduTheme.bodyFont())
                        .foregroundStyle(DuduTheme.duduText)
                    Text(preset.detail)
                        .font(DuduTheme.captionFont())
                        .foregroundStyle(DuduTheme.duduTextDim)
                }
                Spacer()
                presetTestButton(preset, key: key)
            }
            let failed = testPlayer.failedReason(forKey: key)
            if !failed.isEmpty {
                Text(failed)
                    .font(DuduTheme.captionFont())
                    .foregroundStyle(DuduTheme.duduTextDim)
                    .padding(.leading, 54)
            }
        }
    }

    /// 试听 button for a preset row. The "off" row has no sound to play —
    /// its button is honestly disabled with the plain reason, never a fake.
    @ViewBuilder
    private func presetTestButton(_ preset: TTSBuiltInPreset, key: String) -> some View {
        if preset.previewable {
            let playing = testPlayer.state(forKey: key) == .playing
            Button {
                testPlayer.testPreset(preset)
            } label: {
                Text(playing ? "停止" : "试听")
                    .font(DuduTheme.captionFont(weight: .medium))
                    .foregroundStyle(DuduTheme.pink)
                    .frame(minWidth: 44, minHeight: 44)
            }
            .buttonStyle(.plain)
        } else {
            VStack(alignment: .trailing, spacing: 0) {
                Text("试听")
                    .font(DuduTheme.captionFont(weight: .medium))
                    .foregroundStyle(DuduTheme.duduTextDim)
                Text("关了就没声音可试")
                    .font(DuduTheme.captionFont())
                    .foregroundStyle(DuduTheme.duduTextDim)
            }
            .frame(minWidth: 44, minHeight: 44)
        }
    }

    /// 试听 button for a custom service row. No key → disabled with the plain
    /// reason (never fake playback); with a key → real vendor synthesis.
    @ViewBuilder
    private func serviceTestButton(_ service: TTSServiceOptions) -> some View {
        let test = testPlayer.serviceTestability(service)
        if test.ok {
            let playing = testPlayer.state(forKey: TTSVoiceTestPlayer.serviceKey(service)) == .playing
            Button {
                testPlayer.testService(service)
            } label: {
                Text(playing ? "停止" : "试听")
                    .font(DuduTheme.captionFont(weight: .medium))
                    .foregroundStyle(DuduTheme.pink)
                    .frame(minWidth: 44, minHeight: 44)
            }
            .buttonStyle(.plain)
        } else {
            VStack(alignment: .trailing, spacing: 0) {
                Text("试听")
                    .font(DuduTheme.captionFont(weight: .medium))
                    .foregroundStyle(DuduTheme.duduTextDim)
                Text(test.reason)
                    .font(DuduTheme.captionFont())
                    .foregroundStyle(DuduTheme.duduTextDim)
            }
            .frame(minWidth: 44, minHeight: 44)
        }
    }

    private func stepLabel(_ step: Float) -> String {
        step.truncatingRemainder(dividingBy: 1) == 0
            ? "\(Int(step))x"
            : String(format: "%.2gx", step)
    }
}

// MARK: - Service editor (add / edit one TTS service)

/// One TTS service's URL + model + voice + API key. The key is stored in the
/// Keychain (never in the backup / repo); services are saved to UserDefaults.
private struct TTSServiceEditor: View {
    let existing: TTSServiceOptions?
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var kind: TTSServiceKind
    @State private var name: String
    @State private var baseURL: String
    @State private var model: String
    @State private var voice: String
    @State private var apiKey: String = ""
    @State private var showDeleteConfirm = false
    @State private var prevKind: TTSServiceKind

    init(existing: TTSServiceOptions?, onSaved: @escaping () -> Void) {
        self.existing = existing
        self.onSaved = onSaved
        let resolvedKind = existing?.kind ?? .minimax
        _kind = State(initialValue: resolvedKind)
        _prevKind = State(initialValue: resolvedKind)
        _name = State(initialValue: existing?.name ?? "")
        _baseURL = State(initialValue: existing?.baseURL ?? "")
        _model = State(initialValue: existing?.model ?? "")
        _voice = State(initialValue: existing?.voice ?? "")
    }

    private var hasExistingKey: Bool {
        guard let existing else { return false }
        return TTSServiceStore.shared.hasAPIKey(for: existing)
    }

    var body: some View {
        List {
            Section {
                Picker("服务商", selection: $kind) {
                    ForEach(TTSServiceKind.allCases) { k in
                        Text(k.displayName).tag(k)
                    }
                }
                .onChange(of: kind) { _, newKind in
                    // Refresh the blanks to the vendor defaults — only for
                    // fields the user hasn't typed in yet.
                    if baseURL.isEmpty || baseURL == prevKind.defaultBaseURL {
                        baseURL = newKind.defaultBaseURL
                    }
                    if model.isEmpty || model == prevKind.defaultModel { model = newKind.defaultModel }
                    if voice.isEmpty || voice == prevKind.defaultVoice { voice = newKind.defaultVoice }
                    if name.isEmpty || name == prevKind.displayName { name = newKind.displayName }
                    prevKind = newKind
                }

                fieldRow("名称", text: $name, placeholder: kind.displayName)
                fieldRow("URL", text: $baseURL, placeholder: kind.defaultBaseURL, keyboard: .URL)
                fieldRow("模型", text: $model, placeholder: kind.defaultModel)
                fieldRow("音色", text: $voice, placeholder: kind.defaultVoice)
            } header: {
                DuduSectionTitle("服务")
            } footer: {
                DuduSectionFooter {
                    Text("选服务商会自动填默认 URL / 模型 / 音色，也可以自己改。")
                }
            }

            Section {
                SecureField(hasExistingKey ? "密钥（已配置，留空则不变）" : "密钥", text: $apiKey)
                    .font(DuduTheme.bodyFont())
                    .foregroundStyle(DuduTheme.duduText)
            } header: {
                DuduSectionTitle("密钥")
            } footer: {
                DuduSectionFooter {
                    Text("密钥只存进系统钥匙串，不进备份也不进仓库。")
                }
            }

            if existing != nil {
                Section {
                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        Text("删除这个服务")
                            .font(DuduTheme.bodyFont())
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                }
            }
        }
        .duduCardList()
        .navigationTitle(existing == nil ? "添加语音服务" : "编辑语音服务")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") { save() }
                    .font(DuduTheme.bodyFont(weight: .semibold))
            }
        }
        .alert("删除这个语音服务？", isPresented: $showDeleteConfirm) {
            Button("删除", role: .destructive) {
                if let id = existing?.id {
                    TTSServiceStore.shared.remove(id: id)
                    onSaved()
                    dismiss()
                }
            }
            Button("取消", role: .cancel) {}
        }
    }

    private func fieldRow(_ title: String, text: Binding<String>, placeholder: String,
                         keyboard: UIKeyboardType = .default) -> some View {
        HStack {
            Text(title)
                .font(DuduTheme.bodyFont())
                .foregroundStyle(DuduTheme.duduText)
                .frame(width: 52, alignment: .leading)
            TextField(placeholder, text: text)
                .font(DuduTheme.bodyFont())
                .foregroundStyle(DuduTheme.duduText)
                .keyboardType(keyboard)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
        }
    }

    private func save() {
        let store = TTSServiceStore.shared
        let service = TTSServiceOptions(
            id: existing?.id ?? UUID().uuidString,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            kind: kind,
            enabled: true,
            baseURL: baseURL.trimmingCharacters(in: .whitespacesAndNewlines),
            model: model.trimmingCharacters(in: .whitespacesAndNewlines),
            voice: voice.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        store.upsert(service)
        if !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            store.saveAPIKey(apiKey.trimmingCharacters(in: .whitespacesAndNewlines), for: service)
        }
        if existing == nil {
            // A freshly added service becomes the active one immediately.
            store.setSelectedServiceId(service.id)
        }
        onSaved()
        dismiss()
    }
}
