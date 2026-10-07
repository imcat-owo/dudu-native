import SwiftUI

// MARK: - ModelGroupListView · 模型分组
//
// Native edition of old Dudu's model-group orchestration (D4/D28):
//   - the model-group switcher: default primary / secondary group pickers,
//     bound to the real engine pointers (ProviderConfigStore
//     defaultPrimaryGroupId / defaultSubGroupId — both are consumed by the
//     chat and voice engines, so the switcher is real, not decorative)
//   - the group list: name, member count, routing strategy, and an honest
//     unavailable-member count from ModelGroupRouter.unavailableMembers
//   - create / rename (in detail) / delete groups; the detail page edits
//     members and routing strategy on the real ModelGroup engine type
//
// Capability probing: the engine exposes static capability metadata
// (LLMModel.capabilities from the provider catalog) but no live network
// probe — the detail page shows the catalog data labelled as such and says
// so. No fake probe results.

struct ModelGroupListView: View {
    @EnvironmentObject private var store: ProviderConfigStore
    @State private var pendingDelete: ModelGroup?

    var body: some View {
        List {
            defaultsSection
            groupsSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle(AppLocalized("orchestration.title"))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    let group = ModelGroup(name: AppLocalized("orchestration.newGroupName"),
                                           memberEntryIds: [])
                    store.addGroup(group)
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .confirmationDialog(
            AppLocalized("orchestration.deleteGroupConfirm"),
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            )
        ) {
            Button(AppLocalized("common.delete"), role: .destructive) {
                if let group = pendingDelete {
                    store.removeGroup(group.id)
                    pendingDelete = nil
                }
            }
            Button(AppLocalized("common.cancel"), role: .cancel) {
                pendingDelete = nil
            }
        } message: {
            if let group = pendingDelete {
                Text(String(format: AppLocalized("orchestration.deleteGroupMessage"), group.name))
            }
        }
    }

    // MARK: - Default group switcher

    private var defaultsSection: some View {
        Section {
            defaultPicker(
                title: AppLocalized("orchestration.primary"),
                selection: Binding(
                    get: { store.defaultPrimaryGroupId },
                    set: { store.defaultPrimaryGroupId = $0 }
                )
            )
            defaultPicker(
                title: AppLocalized("orchestration.sub"),
                selection: Binding(
                    get: { store.defaultSubGroupId },
                    set: { store.defaultSubGroupId = $0 }
                )
            )
        } header: {
            Text(AppLocalized("orchestration.defaults"))
        } footer: {
            Text(AppLocalized("orchestration.subtitle"))
        }
    }

    private func defaultPicker(title: String, selection: Binding<String?>) -> some View {
        Picker(title, selection: selection) {
            Text(AppLocalized("orchestration.none")).tag(nil as String?)
            ForEach(store.modelGroups) { group in
                Text(group.name).tag(group.id as String?)
            }
        }
        .font(DuduTheme.bodyFont())
    }

    // MARK: - Group list

    private var groupsSection: some View {
        Section {
            if store.modelGroups.isEmpty {
                Text(AppLocalized("orchestration.noMembers"))
                    .font(DuduTheme.captionFont())
                    .foregroundStyle(DuduTheme.duduTextDim)
            }
            ForEach(store.modelGroups) { group in
                NavigationLink(value: SettingsRoute.modelGroupDetail(group.id)) {
                    ModelGroupRowView(group: group)
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        pendingDelete = group
                    } label: {
                        Label(AppLocalized("common.delete"), systemImage: "trash")
                    }
                }
            }
            .onMove { from, to in
                var order = store.modelGroups.map(\.id)
                order.move(fromOffsets: from, toOffset: to)
                store.reorderGroups(order)
            }
        } header: {
            Text(AppLocalized("orchestration.groups"))
        }
    }
}

// MARK: - Row

private struct ModelGroupRowView: View {
    @EnvironmentObject private var store: ProviderConfigStore
    let group: ModelGroup

    private var unavailableCount: Int {
        ModelGroupRouter.unavailableMembers(group: group, store: store).count
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "square.stack.3d.up")
                .font(.system(size: 15))
                .foregroundStyle(DuduTheme.pink)
                .frame(width: 30, height: 30)
                .background(DuduTheme.pinkSoft)
                .clipShape(RoundedRectangle(cornerRadius: DuduTheme.radiusChip))

            VStack(alignment: .leading, spacing: 2) {
                Text(group.name)
                    .font(DuduTheme.bodyFont(weight: .medium))
                    .foregroundStyle(DuduTheme.duduText)
                HStack(spacing: 6) {
                    Text(String(format: AppLocalized("orchestration.memberCount"),
                                "\(group.memberEntryIds.count)"))
                        .font(DuduTheme.captionFont())
                        .foregroundStyle(DuduTheme.duduTextDim)
                    Text("·")
                        .font(DuduTheme.captionFont())
                        .foregroundStyle(DuduTheme.duduTextDim)
                    Text(strategyLabel(group.strategy))
                        .font(DuduTheme.captionFont())
                        .foregroundStyle(DuduTheme.duduTextDim)
                    if unavailableCount > 0 {
                        Text("·")
                            .font(DuduTheme.captionFont())
                            .foregroundStyle(DuduTheme.duduTextDim)
                        Text(String(format: AppLocalized("orchestration.unavailableSuffix"),
                                    "\(unavailableCount)"))
                            .font(DuduTheme.captionFont())
                            .foregroundStyle(DuduTheme.duduDestructive)
                    }
                }
            }
            Spacer()
            if store.defaultPrimaryGroupId == group.id {
                Text(AppLocalized("orchestration.primary"))
                    .font(DuduTheme.captionFont(weight: .semibold))
                    .foregroundStyle(DuduTheme.pink)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(DuduTheme.pinkSoft)
                    .clipShape(Capsule())
            }
        }
        .frame(minHeight: 44)
    }

    private func strategyLabel(_ strategy: RoutingStrategy) -> String {
        switch strategy {
        case .fallback: return AppLocalized("orchestration.strategyFallback")
        case .loadBalance: return AppLocalized("orchestration.strategyLoadBalance")
        }
    }
}
