import SwiftUI
import PhotosUI

// MARK: - PersonaEditView · 新建 / 编辑人设
//
// Wave 3 P1. Sheet over PersonaListView. Edits the registry entry
// (name / desc / avatar dataURI via PersonaStore) and the persona's
// system prompt (the SOUL.md body in memory/personas/<id>/, read and
// written with the existing SoulMDParser — one source of truth, no fork).
//
// Name changes go through PersonaStore.renamePersona so the SOUL.md
// frontmatter stays in sync; avatar/desc go through updatePersona.

struct PersonaEditView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = PersonaStore.shared

    /// nil = create mode.
    let persona: Persona?

    @State private var name: String
    @State private var desc: String
    @State private var avatar: String?
    @State private var systemPrompt: String
    @State private var photoItem: PhotosPickerItem?

    init(persona: Persona?) {
        self.persona = persona
        if let persona {
            let draft = Self.loadDraft(for: persona)
            _name = State(initialValue: persona.name)
            _desc = State(initialValue: draft.desc)
            _avatar = State(initialValue: persona.avatar)
            _systemPrompt = State(initialValue: draft.body)
        } else {
            _name = State(initialValue: "")
            _desc = State(initialValue: "")
            _avatar = State(initialValue: nil)
            _systemPrompt = State(initialValue: "")
        }
    }

    private var isNew: Bool { persona == nil }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 12) {
                        SoulIconView(icon: avatar ?? "", size: 52)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("头像")
                                .font(DuduTheme.bodyFont(weight: .medium))
                                .foregroundStyle(DuduTheme.duduText)
                            Text("不选就用默认小星星。")
                                .font(DuduTheme.captionFont())
                                .foregroundStyle(DuduTheme.duduTextDim)
                        }
                        Spacer()
                        PhotosPicker(selection: $photoItem, matching: .images) {
                            Text(avatar == nil ? "选择" : "更换")
                                .font(DuduTheme.bodyFont(weight: .medium))
                                .foregroundStyle(DuduTheme.pink)
                        }
                        if avatar != nil {
                            Button("清除") { avatar = nil }
                                .font(DuduTheme.bodyFont())
                                .foregroundStyle(DuduTheme.duduDestructive)
                        }
                    }
                    .frame(minHeight: 60)
                }
                Section {
                    TextField("名字", text: $name)
                        .font(DuduTheme.inputFont())
                    TextField("一句话介绍（可空，卡片上展示）", text: $desc, axis: .vertical)
                        .font(DuduTheme.inputFont())
                        .lineLimit(2...4)
                } header: {
                    DuduSectionTitle("基本信息")
                }
                Section {
                    TextEditor(text: $systemPrompt)
                        .font(DuduTheme.inputFont())
                        .frame(minHeight: 180)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                } header: {
                    DuduSectionTitle("系统提示词")
                } footer: {
                    DuduSectionFooter {
                        Text("写进这个人设的 SOUL.md，会作为它每轮对话的身份设定。空着也行，那就是一张白纸。")
                    }
                }
            }
            .duduCardForm()
            .navigationTitle(isNew ? "新人设" : "编辑人设")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存", action: save)
                        .disabled(trimmedName.isEmpty)
                }
            }
            .onChange(of: photoItem) { _, newItem in
                guard let newItem else { return }
                Task { @MainActor in
                    defer { photoItem = nil }
                    guard let data = try? await newItem.loadTransferable(type: Data.self),
                          let uiImage = UIImage(data: data),
                          case .success(let uri) = SoulIconImage.encode(uiImage) else { return }
                    avatar = uri
                }
            }
        }
    }

    // MARK: - Load / save

    private static func loadDraft(for persona: Persona) -> (desc: String, body: String) {
        let url = PersonaStore.memoryDir(for: persona.id)
            .appendingPathComponent("SOUL.md")
        var body = ""
        if let data = try? Data(contentsOf: url),
           let text = String(data: data, encoding: .utf8) {
            body = SoulMDParser.parse(text).body
        }
        return (persona.desc ?? "", body)
    }

    /// Write the SOUL.md body for a persona, preserving the existing
    /// frontmatter (style / lang / icon) — only name and body change.
    private func writeSoul(id: String, name: String, body: String) {
        let dir = PersonaStore.memoryDir(for: id)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("SOUL.md")
        var meta = SoulMetadata.default
        if let data = try? Data(contentsOf: url),
           let text = String(data: data, encoding: .utf8) {
            meta = SoulMDParser.parse(text).metadata
        }
        meta.name = name
        let file = SoulFile(metadata: meta, body: body)
        try? SoulMDParser.serialize(file).data(using: .utf8)?
            .write(to: url, options: .atomic)
    }

    private func save() {
        guard !trimmedName.isEmpty else { return }
        let trimmedDesc = desc.trimmingCharacters(in: .whitespacesAndNewlines)
        let targetID: String
        if let existing = persona {
            // renamePersona syncs the SOUL.md frontmatter name; updatePersona
            // persists desc/avatar (isBuiltIn is preserved by the store).
            store.renamePersona(existing.id, to: trimmedName)
            if var updated = store.personas.first(where: { $0.id == existing.id }) {
                updated.desc = trimmedDesc.isEmpty ? nil : trimmedDesc
                updated.avatar = avatar
                store.updatePersona(updated)
            }
            targetID = existing.id
        } else {
            var created = store.addPersona(name: trimmedName)
            created.desc = trimmedDesc.isEmpty ? nil : trimmedDesc
            created.avatar = avatar
            store.updatePersona(created)
            targetID = created.id
        }
        writeSoul(id: targetID, name: trimmedName, body: systemPrompt)
        if targetID == store.currentPersonaID {
            SoulStore.refreshCache()
        }
        NotificationCenter.default.post(name: .personaDidChange, object: nil)
        dismiss()
    }
}
