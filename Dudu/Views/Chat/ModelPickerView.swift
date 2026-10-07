import SwiftUI

/// Phase C2 — model picker sheet.
///
/// Lists every enabled provider instance's visible model entries. Picking
/// writes a real per-session binding (ProviderConfigStore.setBinding) when
/// a session exists, and always primes the draft path (cachedSessionModelId
/// + selectedModel) so a not-yet-created session sends with the picked model.
struct ModelPickerView: View {
    @EnvironmentObject private var vm: AIChatViewModel
    @EnvironmentObject private var store: ProviderConfigStore
    @Environment(\.dismiss) private var dismiss

    private var enabledInstances: [ProviderInstance] {
        store.config.instances.filter { $0.isEnabled }
    }

    var body: some View {
        NavigationStack {
            Group {
                if enabledInstances.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "cpu")
                            .font(DuduTheme.titleFont())
                            .foregroundStyle(DuduTheme.duduTextDim)
                        Text("还没有可用的模型服务")
                            .font(DuduTheme.bodyFont())
                            .foregroundStyle(DuduTheme.duduTextDim)
                        Text("先去设置里添加一个模型服务，回来就能选模型。")
                            .font(DuduTheme.captionFont())
                            .foregroundStyle(DuduTheme.duduTextDim)
                    }
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(enabledInstances) { instance in
                            let entries = store.visibleEntries(for: instance.id)
                            if !entries.isEmpty {
                                Section(header: Text(instance.label).font(DuduTheme.captionFont())) {
                                    ForEach(entries) { entry in
                                        modelRow(entry, instance: instance)
                                    }
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("选择模型")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭") { dismiss() }
                        .font(DuduTheme.bodyFont())
                        .foregroundStyle(DuduTheme.duduText)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Rows

    private func modelRow(_ entry: ModelEntry, instance: ProviderInstance) -> some View {
        Button {
            select(entry)
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.model.displayName)
                        .font(DuduTheme.bodyFont(weight: .medium))
                        .foregroundStyle(DuduTheme.duduText)
                        .lineLimit(1)
                    Text(instance.label)
                        .font(DuduTheme.captionFont())
                        .foregroundStyle(DuduTheme.duduTextDim)
                        .lineLimit(1)
                }
                Spacer()
                if isSelected(entry) {
                    Image(systemName: "checkmark")
                        .font(DuduTheme.bodyFont(weight: .semibold))
                        .foregroundStyle(DuduTheme.pink)
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Selection

    /// Mirrors AIChatViewModel.resolveCurrentEntry()'s precedence:
    /// session binding first, then the cached/draft model id, then the
    /// view model's fallback.
    private func isSelected(_ entry: ModelEntry) -> Bool {
        if let sid = vm.sessionId,
           let binding = store.binding(for: sid),
           case .directEntry(let entryId, _) = binding.primarySource,
           let resolved = store.entry(for: entryId) {
            return resolved.id == entry.id
        }
        if !vm.cachedSessionModelId.isEmpty {
            return entry.model.id == vm.cachedSessionModelId
        }
        return entry.model.id == vm.selectedModel.id
    }

    private func select(_ entry: ModelEntry) {
        // Draft path: the next send() resolves through cachedSessionModelId
        // (and selectedModel as the final fallback).
        vm.cachedSessionModelId = entry.model.id
        vm.selectedModel = entry.model

        // Persisted session: pin a real per-session binding so the choice
        // survives reloads and iCloud sync.
        // Phase D4 — 隐身会话只走内存（cachedSessionModelId / selectedModel），
        // 不写任何持久化绑定。
        if let sid = vm.sessionId, !vm.isIncognito {
            let binding = SessionModelBinding(
                sessionId: sid,
                primarySource: .directEntry(
                    modelEntryId: entry.uuid,
                    compositeKey: entry.compositeKey
                ),
                subModelSource: nil
            )
            store.setBinding(binding, for: sid)
            Task {
                await ChatStore.shared.updateSessionModelId(sid, modelId: entry.model.id)
            }
        }
        dismiss()
    }
}
