import SwiftUI

// MARK: - ModelGroupDetailView · 分组详情 / 编排
//
// Edits one ModelGroup (the real engine type): name, routing strategy,
// fallback trigger, and the ordered member list. Members are real
// ModelEntry ids ("{instanceId}/{modelId}" composite keys); availability is
// read live from ModelGroupRouter.unavailableMembers.
//
// Capability display: per-member chips from the engine's static capability
// metadata (LLMModel.capabilities / supportsReasoning / contextWindowTokens
// — provider-catalog data). The engine exposes no live network probe, so
// the page says so explicitly instead of faking probe results.

struct ModelGroupDetailView: View {
    @EnvironmentObject private var store: ProviderConfigStore
    let groupId: String

    @State private var showingMemberPicker = false

    private var group: ModelGroup? {
        store.group(for: groupId)
    }

    /// Per-entry unavailability reason, mirroring ModelGroupRouter's filter
    /// (hidden / provider gone / disabled / no credential). Computed per
    /// entry because unavailableMembers keys its tuples by display name,
    /// which is not a stable lookup key.
    private func unavailableReason(for entry: ModelEntry) -> String? {
        if entry.isHidden { return AppLocalized("orchestration.reasonHidden") }
        guard let inst = store.instance(for: entry.providerInstanceId) else {
            return AppLocalized("orchestration.reasonNoProvider")
        }
        if !inst.isEnabled { return AppLocalized("orchestration.reasonDisabled") }
        if !inst.hasAnyCredential { return AppLocalized("orchestration.reasonNoCredential") }
        return nil
    }

    var body: some View {
        Group {
            if let group {
                detailBody(group)
            } else {
                Text(AppLocalized("orchestration.groupGone"))
                    .font(DuduTheme.bodyFont())
                    .foregroundStyle(DuduTheme.duduTextDim)
            }
        }
        .navigationTitle(group?.name ?? AppLocalized("orchestration.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                // Enables edit mode so the member reorder (.onMove) is reachable.
                EditButton()
            }
        }
        .sheet(isPresented: $showingMemberPicker) {
            if let group {
                ModelGroupMemberPickerView(group: group)
            }
        }
    }

    // MARK: Body

    @ViewBuilder
    private func detailBody(_ group: ModelGroup) -> some View {
        List {
            Section {
                HStack {
                    Text(AppLocalized("orchestration.groupNamePh"))
                        .font(DuduTheme.bodyFont())
                        .foregroundStyle(DuduTheme.duduText)
                    Spacer()
                    TextField("", text: Binding(
                        get: { group.name },
                        set: { newValue in
                            var updated = group
                            updated.name = newValue
                            store.updateGroup(updated)
                        }
                    ))
                    .font(DuduTheme.bodyFont())
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(DuduTheme.duduText)
                }
            }

            Section {
                Picker(AppLocalized("orchestration.strategy"), selection: Binding(
                    get: { group.strategy },
                    set: { newValue in
                        var updated = group
                        updated.strategy = newValue
                        store.updateGroup(updated)
                    }
                )) {
                    Text(AppLocalized("orchestration.strategyFallback")).tag(RoutingStrategy.fallback)
                    Text(AppLocalized("orchestration.strategyLoadBalance")).tag(RoutingStrategy.loadBalance)
                }
                .font(DuduTheme.bodyFont())
                Text(group.strategy == .fallback
                     ? AppLocalized("orchestration.strategyFallbackDesc")
                     : AppLocalized("orchestration.strategyLoadBalanceDesc"))
                    .font(DuduTheme.captionFont())
                    .foregroundStyle(DuduTheme.duduTextDim)

                if group.strategy == .fallback {
                    Picker(AppLocalized("orchestration.fallbackMode"), selection: Binding(
                        get: { group.fallbackStrategy },
                        set: { newValue in
                            var updated = group
                            updated.fallbackStrategy = newValue
                            store.updateGroup(updated)
                        }
                    )) {
                        Text(AppLocalized("orchestration.fallbackModeLimited")).tag(FallbackStrategy.limited)
                        Text(AppLocalized("orchestration.fallbackModeAlways")).tag(FallbackStrategy.always)
                    }
                    .font(DuduTheme.bodyFont())
                }
            } header: {
                DuduSectionTitle(AppLocalized("orchestration.strategy"))
            }

            Section {
                if group.memberEntryIds.isEmpty {
                    Text(AppLocalized("orchestration.noMembers"))
                        .font(DuduTheme.captionFont())
                        .foregroundStyle(DuduTheme.duduTextDim)
                }
                ForEach(group.memberEntryIds, id: \.self) { entryId in
                    memberRow(entryId: entryId, group: group)
                }
                .onDelete { offsets in
                    var updated = group
                    updated.memberEntryIds.remove(atOffsets: offsets)
                    store.updateGroup(updated)
                }
                .onMove { from, to in
                    var updated = group
                    updated.memberEntryIds.move(fromOffsets: from, toOffset: to)
                    store.updateGroup(updated)
                }
                Button {
                    showingMemberPicker = true
                } label: {
                    Label(AppLocalized("orchestration.addMember"), systemImage: "plus")
                        .font(DuduTheme.bodyFont())
                }
            } header: {
                DuduSectionTitle(AppLocalized("orchestration.members"))
            } footer: {
                // Honest: catalog metadata, not a live probe.
                DuduSectionFooter {
                    Text(AppLocalized("orchestration.capabilityNote"))
                }
            }
        }
        .duduCardList()
    }

    // MARK: Member row

    @ViewBuilder
    private func memberRow(entryId: String, group: ModelGroup) -> some View {
        if let entry = store.entry(for: entryId) {
            let instanceLabel = store.instance(for: entry.providerInstanceId)?.label
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.model.displayName)
                            .font(DuduTheme.bodyFont(weight: .medium))
                            .foregroundStyle(DuduTheme.duduText)
                        Text(instanceLabel ?? entry.providerInstanceId)
                            .font(DuduTheme.captionFont())
                            .foregroundStyle(DuduTheme.duduTextDim)
                    }
                    Spacer()
                    if let reason = unavailableReason(for: entry) {
                        Text(reason)
                            .font(DuduTheme.captionFont(weight: .semibold))
                            .foregroundStyle(DuduTheme.duduDestructive)
                    }
                }
                capabilityChips(entry.model)
            }
            .padding(.vertical, 4)
        } else {
            HStack {
                Text(entryId)
                    .font(DuduTheme.captionFont())
                    .foregroundStyle(DuduTheme.duduTextDim)
                    .lineLimit(1)
                Spacer()
                Button(AppLocalized("orchestration.removeMember")) {
                    var updated = group
                    updated.memberEntryIds.removeAll { $0 == entryId }
                    store.updateGroup(updated)
                }
                .font(DuduTheme.captionFont())
                .foregroundStyle(DuduTheme.duduDestructive)
            }
        }
    }

    // MARK: Capability chips (engine catalog data — labelled, not probed)

    @ViewBuilder
    private func capabilityChips(_ model: LLMModel) -> some View {
        let modalities = model.capabilities.supportedModalities
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(modalityChips(modalities), id: \.self) { label in
                    capabilityChip(label)
                }
                capabilityChip(thinkingLabel(model.supportsReasoning))
                capabilityChip(String(format: AppLocalized("orchestration.context"),
                                      formatTokens(model.contextWindowTokens)))
            }
        }
    }

    private func modalityChips(_ m: ModelModality) -> [String] {
        // Text in/out is universal — only the extras earn chips.
        var chips: [String] = []
        if m.contains(.imageInput) { chips.append(AppLocalized("orchestration.modalityImage")) }
        if m.contains(.pdfInput) { chips.append(AppLocalized("orchestration.modalityPdf")) }
        if m.contains(.audioInput) { chips.append(AppLocalized("orchestration.modalityAudio")) }
        if m.contains(.videoInput) { chips.append(AppLocalized("orchestration.modalityVideo")) }
        if chips.isEmpty { chips.append(AppLocalized("orchestration.modalityTextOnly")) }
        return chips
    }

    private func thinkingLabel(_ supports: Bool?) -> String {
        let state: String
        if let s = supports {
            state = AppLocalized(s ? "orchestration.thinkingYes" : "orchestration.thinkingNo")
        } else {
            state = AppLocalized("orchestration.thinkingUnknown")
        }
        return "\(AppLocalized("orchestration.thinking")): \(state)"
    }

    private func formatTokens(_ tokens: Int) -> String {
        if tokens >= 1_000_000 {
            let v = Double(tokens) / 1_000_000
            return v.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(v))M" : String(format: "%.1fM", v)
        }
        if tokens >= 1_000 {
            let v = Double(tokens) / 1_000
            return v.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(v))K" : String(format: "%.1fK", v)
        }
        return "\(tokens)"
    }

    private func capabilityChip(_ label: String) -> some View {
        Text(label)
            .font(DuduTheme.captionFont())
            .foregroundStyle(DuduTheme.duduTextDim)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(DuduTheme.duduIconChip)
            .clipShape(Capsule())
    }
}

// MARK: - Member picker

private struct ModelGroupMemberPickerView: View {
    @EnvironmentObject private var store: ProviderConfigStore
    @Environment(\.dismiss) private var dismiss
    let group: ModelGroup

    /// All entries across instances, minus ones already in the group.
    private var candidates: [ModelEntry] {
        let inGroup = Set(group.memberEntryIds)
        return store.config.modelEntries
            .filter { !inGroup.contains($0.id) }
            .sorted { $0.model.displayName < $1.model.displayName }
    }

    var body: some View {
        NavigationStack {
            List {
                if candidates.isEmpty {
                    Text(AppLocalized("orchestration.noCandidates"))
                        .font(DuduTheme.captionFont())
                        .foregroundStyle(DuduTheme.duduTextDim)
                }
                ForEach(candidates) { entry in
                    Button {
                        var updated = store.group(for: group.id) ?? group
                        updated.memberEntryIds.append(entry.id)
                        store.updateGroup(updated)
                        dismiss()
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.model.displayName)
                                    .font(DuduTheme.bodyFont())
                                    .foregroundStyle(DuduTheme.duduText)
                                Text(store.instance(for: entry.providerInstanceId)?.label
                                     ?? entry.providerInstanceId)
                                    .font(DuduTheme.captionFont())
                                    .foregroundStyle(DuduTheme.duduTextDim)
                            }
                            Spacer()
                            DuduIcon(systemName: "plus.circle")
                                .foregroundStyle(DuduTheme.pink)
                        }
                    }
                }
            }
            .duduCardList()
            .navigationTitle(AppLocalized("orchestration.pickMember"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppLocalized("common.cancel")) { dismiss() }
                }
            }
        }
    }
}
