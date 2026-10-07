import SwiftUI

// MARK: - PersonaEvolutionView · 成长记录
//
// She owns every note: read / edit / delete live here (Our Space wiring).
// One pattern per note, ≤200 chars, source required, max 1 new note per day —
// enforced by PersonaEvolutionStore.

/// Init: PersonaEvolutionView(personaID: String)
@MainActor
struct PersonaEvolutionView: View {
    let personaID: String

    @ObservedObject private var store = PersonaEvolutionStore.shared
    @State private var showingAdd = false
    @State private var editingNote: EvolutionNote?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerRow
            if store.notes.isEmpty {
                emptyState
            } else {
                ForEach(store.notes) { note in
                    noteCard(note)
                }
            }
            if !store.isEnabled {
                Text("性格进化已暂停：不再写新记录，提示词里也不再带这些。")
                    .font(DuduTheme.captionFont())
                    .foregroundStyle(DuduTheme.duduTextDim)
            }
        }
        .onAppear {
            store.open(personaID: personaID)
        }
        .sheet(isPresented: $showingAdd) {
            EvolutionNoteSheet(store: store, existing: nil)
        }
        .sheet(item: $editingNote) { note in
            EvolutionNoteSheet(store: store, existing: note)
        }
    }

    // MARK: Header

    private var headerRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("成长记录")
                    .font(DuduTheme.titleFont())
                    .foregroundStyle(DuduTheme.duduText)
                Text("他留意到的、反复出现的样子")
                    .font(DuduTheme.captionFont())
                    .foregroundStyle(DuduTheme.duduTextDim)
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { store.isEnabled },
                set: { store.setEnabled($0) }
            ))
            .labelsHidden()
            .tint(DuduTheme.pink)
            Button {
                showingAdd = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .semibold))
                    Text("记一条")
                        .font(DuduTheme.captionFont(weight: .semibold))
                }
                .foregroundStyle(DuduTheme.duduText)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(DuduTheme.pinkSoft, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(!store.canAddToday || !store.isEnabled)
            .opacity((!store.canAddToday || !store.isEnabled) ? 0.4 : 1)
        }
    }

    // MARK: Empty state

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("还没有记录")
                .font(DuduTheme.bodyFont(weight: .semibold))
                .foregroundStyle(DuduTheme.duduText)
            Text("当他在你身上发现反复出现的小习惯，就会记下一条。一天最多一条，只记真正新的发现。")
                .font(DuduTheme.captionFont())
                .foregroundStyle(DuduTheme.duduTextDim)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DuduTheme.duduCard, in: RoundedRectangle(cornerRadius: DuduTheme.radiusCard))
    }

    // MARK: Note card

    private func noteCard(_ note: EvolutionNote) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(note.text)
                .font(DuduTheme.bodyFont())
                .foregroundStyle(DuduTheme.duduText)
            HStack(spacing: 6) {
                Text(note.sourceKind.label)
                    .font(DuduTheme.captionFont(weight: .semibold))
                    .foregroundStyle(DuduTheme.duduText)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(DuduTheme.duduIconChip, in: Capsule())
                Text(note.sourceRef)
                    .font(DuduTheme.captionFont())
                    .foregroundStyle(DuduTheme.duduTextDim)
                    .lineLimit(1)
                Spacer()
                Text(sourceDateString(note))
                    .font(DuduTheme.captionFont())
                    .foregroundStyle(DuduTheme.duduTextDim)
            }
            HStack(spacing: 8) {
                Spacer()
                Button {
                    editingNote = note
                } label: {
                    Text("改一改")
                        .font(DuduTheme.captionFont(weight: .semibold))
                        .foregroundStyle(DuduTheme.duduText)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(DuduTheme.pinkSoft, in: Capsule())
                }
                .buttonStyle(.plain)
                Button(role: .destructive) {
                    store.deleteNote(id: note.id)
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 12))
                        .foregroundStyle(DuduTheme.duduTextDim)
                        .frame(width: 30, height: 30)
                }
            }
        }
        .padding(12)
        .background(DuduTheme.duduCard, in: RoundedRectangle(cornerRadius: DuduTheme.radiusCard))
    }

    private func sourceDateString(_ note: EvolutionNote) -> String {
        let d = Date(timeIntervalSince1970: Double(note.sourceDateMs) / 1000)
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: d)
    }
}

// MARK: - EvolutionNoteSheet · add / edit one note

private struct EvolutionNoteSheet: View {
    @ObservedObject var store: PersonaEvolutionStore
    let existing: EvolutionNote?

    @Environment(\.dismiss) private var dismiss

    @State private var text: String
    @State private var sourceKind: EvolutionSourceKind
    @State private var sourceDate: Date
    @State private var sourceRef: String
    @State private var errorMessage: String?

    init(store: PersonaEvolutionStore, existing: EvolutionNote?) {
        self.store = store
        self.existing = existing
        _text = State(initialValue: existing?.text ?? "")
        _sourceKind = State(initialValue: existing?.sourceKind ?? .chat)
        let d = existing.map { Date(timeIntervalSince1970: Double($0.sourceDateMs) / 1000) } ?? Date()
        _sourceDate = State(initialValue: d)
        _sourceRef = State(initialValue: existing?.sourceRef ?? "")
    }

    private var canSave: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && text.trimmingCharacters(in: .whitespacesAndNewlines).count <= PersonaEvolutionStore.maxNoteChars
            && !sourceRef.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("他发现了什么")
                            .font(DuduTheme.captionFont(weight: .semibold))
                            .foregroundStyle(DuduTheme.duduTextDim)
                        TextEditor(text: $text)
                            .font(DuduTheme.bodyFont())
                            .foregroundStyle(DuduTheme.duduText)
                            .frame(minHeight: 90)
                            .padding(8)
                            .background(DuduTheme.duduCard, in: RoundedRectangle(cornerRadius: DuduTheme.radiusChip))
                        HStack {
                            Spacer()
                            Text("\(text.count)/\(PersonaEvolutionStore.maxNoteChars)")
                                .font(DuduTheme.captionFont())
                                .foregroundStyle(DuduTheme.duduTextDim)
                                .monospacedDigit()
                        }
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("在哪看到的")
                            .font(DuduTheme.captionFont(weight: .semibold))
                            .foregroundStyle(DuduTheme.duduTextDim)
                        Picker("来源", selection: $sourceKind) {
                            ForEach(EvolutionSourceKind.allCases, id: \.self) { k in
                                Text(k.label).tag(k)
                            }
                        }
                        .pickerStyle(.segmented)
                        DatePicker("哪一天", selection: $sourceDate, displayedComponents: .date)
                            .font(DuduTheme.bodyFont())
                            .foregroundStyle(DuduTheme.duduText)
                        TextField("哪次对话，比如：昨晚的晚安聊天", text: $sourceRef)
                            .font(DuduTheme.bodyFont())
                            .foregroundStyle(DuduTheme.duduText)
                            .padding(10)
                            .background(DuduTheme.duduCard, in: RoundedRectangle(cornerRadius: DuduTheme.radiusChip))
                    }
                    if let msg = errorMessage {
                        Text(msg)
                            .font(DuduTheme.captionFont())
                            .foregroundStyle(DuduTheme.duduDestructive)
                    }
                    Text("只记反复出现的样子，不记单次的事。来源必填，没有来源就不记。")
                        .font(DuduTheme.captionFont())
                        .foregroundStyle(DuduTheme.duduTextDim)
                }
                .padding(DuduTheme.pagePadding)
            }
            .background(DuduTheme.duduBackground)
            .navigationTitle(existing == nil ? "记一条" : "改一改")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("存下") { save() }
                        .disabled(!canSave)
                }
            }
        }
    }

    private func save() {
        do {
            if let e = existing {
                try store.editNote(id: e.id, text: text, sourceKind: sourceKind,
                                   sourceDate: sourceDate, sourceRef: sourceRef)
            } else {
                try store.addNote(text: text, sourceKind: sourceKind,
                                  sourceDate: sourceDate, sourceRef: sourceRef)
            }
            dismiss()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "没存上，再试一次。"
        }
    }
}
