import SwiftUI

// MARK: - GardenSection · 记忆花园
//
// Memory cards in three states (ported from the old Dudu memory system):
//   盛放 blooming   — confident, remembered well
//   萌芽 sprouting  — unsure, waits for her confirmation ("记对了" blooms it)
//   想问她 ask       — he wants to ask her; she answers in the sheet
// Add-only history discipline: nothing is silently overwritten; deleting a
// card removes it only at her explicit request.

private enum GardenFilter: String, CaseIterable, Identifiable {
    case all
    case blooming
    case sprouting
    case ask

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "全部"
        case .blooming: return "盛放"
        case .sprouting: return "萌芽"
        case .ask: return "想问她"
        }
    }

    func matches(_ seed: MemorySeed) -> Bool {
        switch self {
        case .all: return true
        case .blooming: return seed.confidence == .blooming
        case .sprouting: return seed.confidence == .sprouting
        case .ask: return seed.confidence == .ask
        }
    }
}

struct GardenSection: View {
    @ObservedObject private var store = OurSpaceStore.shared
    @State private var filter: GardenFilter = .all
    @State private var showingEditor = false
    @State private var answeringSeed: MemorySeed?

    private var visibleSeeds: [MemorySeed] {
        store.seeds.filter { filter.matches($0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            OurSpaceSectionHeader(title: "记忆花园", actionTitle: "种一颗") {
                showingEditor = true
            }
            filterRow
            if store.seeds.isEmpty {
                OurSpaceEmptyState(
                    systemImage: "leaf",
                    title: "花园空空的",
                    message: "多跟我聊聊，值得记住的我都种下来。",
                    actionTitle: "种一颗"
                ) {
                    showingEditor = true
                }
            } else if visibleSeeds.isEmpty {
                OurSpaceEmptyState(
                    systemImage: filter == .ask ? "questionmark.circle" : "leaf",
                    title: "这里还没有",
                    message: "换个状态看看，或种下新的一颗。"
                )
            } else {
                ForEach(visibleSeeds) { seed in
                    seedCard(seed)
                }
            }
        }
        .sheet(isPresented: $showingEditor) {
            SeedEditorSheet(store: store)
        }
        .sheet(item: $answeringSeed) { seed in
            AnswerSheet(store: store, seed: seed)
        }
    }

    // MARK: Filter row

    private var filterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(GardenFilter.allCases) { f in
                    let count = store.seeds.filter { f.matches($0) }.count
                    let selected = f == filter
                    Button {
                        filter = f
                    } label: {
                        HStack(spacing: 4) {
                            Text(f.title)
                            Text("\(count)")
                                .monospacedDigit()
                        }
                        .font(DuduTheme.captionFont(weight: selected ? .semibold : .regular))
                        .foregroundStyle(selected ? DuduTheme.duduText : DuduTheme.duduTextDim)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(
                            selected ? DuduTheme.pinkSoft : DuduTheme.duduCard,
                            in: Capsule()
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: Seed card

    private func seedCard(_ seed: MemorySeed) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: seed.confidence.systemImage)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DuduTheme.duduText)
                OurSpaceChip(text: seed.confidence.label, color: seed.confidence.chipColor)
                OurSpaceChip(text: seed.category.label, color: DuduTheme.duduIconChip)
                Spacer()
                Text(ourSpaceRelativeTime(from: seed.updatedAt))
                    .font(DuduTheme.captionFont())
                    .foregroundStyle(DuduTheme.duduTextDim)
            }
            Text(seed.content)
                .font(DuduTheme.bodyFont())
                .foregroundStyle(DuduTheme.duduText)
            if seed.confidence != .blooming {
                Text(seed.confidence.hint)
                    .font(DuduTheme.captionFont())
                    .foregroundStyle(DuduTheme.duduTextDim)
            }
            HStack(spacing: 8) {
                switch seed.confidence {
                case .sprouting:
                    Button {
                        store.confirmSeed(id: seed.id)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .semibold))
                            Text("记对了")
                                .font(DuduTheme.captionFont(weight: .semibold))
                        }
                        .foregroundStyle(DuduTheme.duduText)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(DuduTheme.pinkSoft, in: Capsule())
                    }
                case .ask:
                    Button {
                        answeringSeed = seed
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "bubble.left")
                                .font(.system(size: 11, weight: .semibold))
                            Text("我来回答")
                                .font(DuduTheme.captionFont(weight: .semibold))
                        }
                        .foregroundStyle(DuduTheme.duduText)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(DuduTheme.pinkSoft, in: Capsule())
                    }
                case .blooming:
                    EmptyView()
                }
                Spacer()
                Button(role: .destructive) {
                    store.deleteSeed(id: seed.id)
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
}

// MARK: - SeedEditorSheet

private struct SeedEditorSheet: View {
    @ObservedObject var store: OurSpaceStore
    @Environment(\.dismiss) private var dismiss

    @State private var content = ""
    @State private var confidence: MemoryConfidence = .sprouting
    @State private var category: MemoryCategory = .other

    private var canSave: Bool {
        !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        OurSpaceSheet(title: "种一颗记忆", saveTitle: "种下", canSave: canSave) {
            store.addMemorySeed(content: content, category: category, confidence: confidence)
        } content: {
            VStack(alignment: .leading, spacing: 6) {
                Text("记什么")
                    .font(DuduTheme.captionFont(weight: .semibold))
                    .foregroundStyle(DuduTheme.duduTextDim)
                TextEditor(text: $content)
                    .font(DuduTheme.bodyFont())
                    .foregroundStyle(DuduTheme.duduText)
                    .frame(minHeight: 110)
                    .padding(8)
                    .background(DuduTheme.duduCard, in: RoundedRectangle(cornerRadius: DuduTheme.radiusChip))
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("记得有多牢")
                    .font(DuduTheme.captionFont(weight: .semibold))
                    .foregroundStyle(DuduTheme.duduTextDim)
                HStack(spacing: 8) {
                    ForEach(MemoryConfidence.allCases, id: \.self) { c in
                        confidenceButton(c)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("分类")
                    .font(DuduTheme.captionFont(weight: .semibold))
                    .foregroundStyle(DuduTheme.duduTextDim)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 64))], spacing: 8) {
                    ForEach(MemoryCategory.allCases, id: \.self) { cat in
                        let selected = cat == category
                        Button {
                            category = cat
                        } label: {
                            Text(cat.label)
                                .font(DuduTheme.captionFont(weight: selected ? .semibold : .regular))
                                .foregroundStyle(selected ? DuduTheme.duduText : DuduTheme.duduTextDim)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(
                                    selected ? DuduTheme.pinkSoft : DuduTheme.duduCard,
                                    in: Capsule()
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    @MainActor private func confidenceButton(_ c: MemoryConfidence) -> some View {
        let selected = c == confidence
        return Button {
            confidence = c
        } label: {
            VStack(spacing: 4) {
                Image(systemName: c.systemImage)
                    .font(.system(size: 14, weight: selected ? .semibold : .regular))
                Text(c.label)
                    .font(DuduTheme.captionFont(weight: selected ? .semibold : .regular))
            }
            .foregroundStyle(selected ? DuduTheme.duduText : DuduTheme.duduTextDim)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                selected ? c.chipColor : DuduTheme.duduCard,
                in: RoundedRectangle(cornerRadius: DuduTheme.radiusChip)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - AnswerSheet · she answers a question seed

private struct AnswerSheet: View {
    @ObservedObject var store: OurSpaceStore
    let seed: MemorySeed
    @Environment(\.dismiss) private var dismiss

    @State private var answer = ""

    private var canSave: Bool {
        !answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        OurSpaceSheet(title: "回答他", saveTitle: "记下来", canSave: canSave) {
            store.answerSeed(id: seed.id, answer: answer)
        } content: {
            VStack(alignment: .leading, spacing: 6) {
                Text("他想问")
                    .font(DuduTheme.captionFont(weight: .semibold))
                    .foregroundStyle(DuduTheme.duduTextDim)
                Text(seed.content)
                    .font(DuduTheme.bodyFont())
                    .foregroundStyle(DuduTheme.duduText)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(DuduTheme.duduCard, in: RoundedRectangle(cornerRadius: DuduTheme.radiusChip))
            }
            OurSpaceField(label: "你的回答", placeholder: "告诉他答案", text: $answer, axis: .vertical)
            Text("回答会被记下来，这颗记忆会盛放。")
                .font(DuduTheme.captionFont())
                .foregroundStyle(DuduTheme.duduTextDim)
        }
    }
}
