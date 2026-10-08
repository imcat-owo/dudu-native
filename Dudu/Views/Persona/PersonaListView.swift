import SwiftUI

// MARK: - PersonaListView · 人设管理
//
// Wave 3 P1: the missing management UI for PersonaStore (Agent/Session).
// List / switch / create / edit / delete personas. Reached from Settings
// (SettingsRoute.personas). SillyTavern-style persona cards: compact Q萌
// rows, DuduTheme tokens only, no emoji.
//
// Tap a card = switch the active persona. Swipe for edit / duplicate /
// delete (Kelivo parity — the store already supports duplicate). Delete is
// hidden for the built-in steward, the default persona (memory anchor) and
// the last remaining persona — same guards as PersonaStore.deletePersona.

struct PersonaListView: View {
    @ObservedObject private var store = PersonaStore.shared

    @State private var creating = false
    @State private var editing: Persona?
    @State private var pendingDelete: Persona?

    var body: some View {
        List {
            Section {
                ForEach(store.personas) { persona in
                    PersonaCardRow(
                        persona: persona,
                        isCurrent: persona.id == store.currentPersonaID,
                        canDelete: canDelete(persona),
                        onSelect: { store.setCurrent(persona.id) },
                        onEdit: { editing = persona },
                        onDuplicate: { _ = store.duplicatePersona(persona.id) },
                        onDelete: { pendingDelete = persona }
                    )
                }
                .onMove { store.movePersona(from: $0, to: $1) }
            } header: {
                DuduSectionTitle("人设")
            } footer: {
                DuduSectionFooter {
                    Text("点一张卡片就切换到那个人设。左滑可以编辑、复制或删除。内置小助手和「我的小家」不能删。")
                }
            }
        }
        .duduCardList()
        .navigationTitle("人设")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                EditButton()
                Button {
                    creating = true
                } label: {
                    DuduIcon(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $creating) {
            PersonaEditView(persona: nil)
        }
        .sheet(item: $editing) { persona in
            PersonaEditView(persona: persona)
        }
        .confirmationDialog(
            "删除这个人设？",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                if let persona = pendingDelete {
                    store.deletePersona(persona.id)
                }
                pendingDelete = nil
            }
            Button("取消", role: .cancel) { pendingDelete = nil }
        } message: {
            Text("「\(pendingDelete?.name ?? "")」的记忆和聊天记录会一起删掉，无法恢复。")
        }
    }

    /// Mirrors PersonaStore.deletePersona's guards so the UI never offers
    /// a delete the store would refuse.
    private func canDelete(_ persona: Persona) -> Bool {
        !persona.isBuiltIn
            && persona.id != PersonaStore.defaultPersonaID
            && store.personas.count > 1
    }
}

// MARK: - Persona card row

private struct PersonaCardRow: View {
    let persona: Persona
    let isCurrent: Bool
    let canDelete: Bool
    let onSelect: () -> Void
    let onEdit: () -> Void
    let onDuplicate: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                SoulIconView(icon: persona.avatar ?? "", size: 38)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(persona.name)
                            .font(DuduTheme.bodyFont(weight: .medium))
                            .foregroundStyle(DuduTheme.duduText)
                            .lineLimit(1)
                        if isCurrent {
                            Text("使用中")
                                .font(DuduTheme.captionFont(weight: .semibold))
                                .foregroundStyle(DuduTheme.pink)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(DuduTheme.pinkSoft)
                                .clipShape(Capsule())
                        }
                        if persona.isBuiltIn {
                            Text("内置")
                                .font(DuduTheme.captionFont())
                                .foregroundStyle(DuduTheme.duduTextDim)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(DuduTheme.duduIconChip)
                                .clipShape(Capsule())
                        }
                    }
                    if let line = previewLine, !line.isEmpty {
                        Text(line)
                            .font(DuduTheme.captionFont())
                            .foregroundStyle(DuduTheme.duduTextDim)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 4)
                if isCurrent {
                    DuduIcon(systemName: "checkmark.circle.fill")
                        .foregroundStyle(DuduTheme.pink)
                }
            }
            .frame(minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if canDelete {
                Button(role: .destructive, action: onDelete) {
                    Label("删除", systemImage: "trash")
                }
            }
            Button(action: onDuplicate) {
                Label("复制", systemImage: "plus.square.on.square")
            }
            .tint(DuduTheme.brandBrown)
            Button(action: onEdit) {
                Label("编辑", systemImage: "pencil")
            }
            .tint(DuduTheme.pink)
        }
    }

    /// Card subtitle: the one-line description, else the first non-empty
    /// line of the persona's SOUL.md body (the system prompt preview).
    private var previewLine: String? {
        let desc = (persona.desc ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !desc.isEmpty { return desc }
        let url = PersonaStore.memoryDir(for: persona.id)
            .appendingPathComponent("SOUL.md")
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) else { return nil }
        let body = SoulMDParser.parse(text).body
        return body
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty })
    }
}
