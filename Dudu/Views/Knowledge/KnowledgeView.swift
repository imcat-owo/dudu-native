import SwiftUI
import UniformTypeIdentifiers

// MARK: - KnowledgeView · D14 on-device knowledge base UI
//
// Minimal, honest: document list, add-document (PDF / txt / md file picker),
// per-document delete, and a search box running real kNN over the sqlite-vec
// store. Every button is wired to a real function — no dead controls, no
// fake results. Indexing/searching runs off the MainActor inside the actor
// store; this view only renders state.
//
// Hook point for the coordinator: present KnowledgeView() from wherever the
// 知识库 entry point should live (Settings / 我们的空间).

// MARK: - View model

/// Drives the knowledge UI against the real KnowledgeStore. Observed by
/// KnowledgeView. All store calls are async off-main; published state is
/// set back on the MainActor.
@MainActor
final class KnowledgeCenterModel: ObservableObject {
    @Published var documents: [KnowledgeDocument] = []
    @Published var hits: [KnowledgeHit] = []
    @Published var query = ""
    @Published var isBusy = false
    @Published var busyText = ""
    @Published var notice: String?
    @Published var showPicker = false
    @Published var didSearch = false

    private var store: KnowledgeStore? { KnowledgeStore.shared }

    // MARK: - Documents

    func refresh() {
        guard let store else {
            notice = KnowledgeError.noEmbeddingModel.localizedDescription
            return
        }
        Task {
            do {
                let docs = try await store.listDocuments()
                await MainActor.run { self.documents = docs }
            } catch {
                await MainActor.run { self.notice = error.localizedDescription }
            }
        }
    }

    /// Full pipeline: extract text from the picked file → chunk → embed →
    /// index → refresh the list. Shows live progress while embedding.
    func importFile(url: URL) {
        guard let store else {
            notice = KnowledgeError.noEmbeddingModel.localizedDescription
            return
        }
        guard !isBusy else { return }
        isBusy = true
        notice = nil
        Task {
            do {
                // PDF parsing can take a moment on large files — keep it off
                // the main thread. (Embedding itself already runs on the
                // KnowledgeStore actor.)
                let text: String = try await Task.detached(priority: .userInitiated) {
                    try KnowledgePDFImport.extractText(from: url)
                }.value
                let name = url.deletingPathExtension().lastPathComponent
                let docId = UUID().uuidString
                let count = try await store.addDocument(
                    id: docId, name: name, text: text
                ) { done, total in
                    self.busyText = "正在索引 \(done)/\(total) 段"
                }
                await MainActor.run {
                    self.isBusy = false
                    self.busyText = ""
                    self.notice = "已导入《\(name)》，共 \(count) 段"
                }
                self.refresh()
            } catch {
                await MainActor.run {
                    self.isBusy = false
                    self.busyText = ""
                    self.notice = error.localizedDescription
                }
            }
        }
    }

    func delete(_ doc: KnowledgeDocument) {
        guard let store, !isBusy else { return }
        Task {
            do {
                try await store.deleteDocument(id: doc.id)
                await MainActor.run {
                    self.documents.removeAll { $0.id == doc.id }
                    // A deleted doc's hits are stale — drop them too.
                    self.hits.removeAll { $0.docId == doc.id }
                }
            } catch {
                await MainActor.run { self.notice = error.localizedDescription }
            }
        }
    }

    // MARK: - Search

    /// Runs real kNN against the vector store. Empty query clears results.
    func search() {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let store else {
            notice = KnowledgeError.noEmbeddingModel.localizedDescription
            return
        }
        guard !q.isEmpty else {
            hits = []
            didSearch = false
            return
        }
        guard !isBusy else { return }
        isBusy = true
        busyText = "正在检索"
        notice = nil
        Task {
            do {
                let results = try await store.knnSearch(query: q, topK: 8)
                await MainActor.run {
                    self.isBusy = false
                    self.busyText = ""
                    self.hits = results
                    self.didSearch = true
                }
            } catch {
                await MainActor.run {
                    self.isBusy = false
                    self.busyText = ""
                    self.didSearch = true
                    self.notice = error.localizedDescription
                }
            }
        }
    }

    func clearSearch() {
        query = ""
        hits = []
        didSearch = false
    }
}

// MARK: - View

struct KnowledgeView: View {
    @StateObject private var model = KnowledgeCenterModel()

    var body: some View {
        ZStack {
            DuduTheme.duduBackground.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: DuduTheme.groupSpacing) {
                    searchSection
                    resultsSection
                    documentsSection
                }
                .padding(DuduTheme.pagePadding)
            }
        }
        .navigationTitle("知识库")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    model.showPicker = true
                } label: {
                    Image(systemName: "plus")
                        .foregroundStyle(DuduTheme.pink)
                }
                .accessibilityLabel("导入文档")
            }
        }
        .fileImporter(
            isPresented: $model.showPicker,
            allowedContentTypes: [.pdf, .plainText, UTType(filenameExtension: "md") ?? .plainText],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first { model.importFile(url: url) }
            case .failure(let error):
                model.notice = error.localizedDescription
            }
        }
        .onAppear { model.refresh() }
        .overlay {
            if model.isBusy {
                KnowledgeBusyOverlay(text: model.busyText)
            }
        }
    }

    // MARK: - Sections

    private var searchSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                TextField("搜知识库", text: $model.query)
                    .font(DuduTheme.bodyFont())
                    .foregroundStyle(DuduTheme.duduText)
                    .padding(10)
                    .background(DuduTheme.duduCard)
                    .clipShape(RoundedRectangle(cornerRadius: DuduTheme.radiusChip, style: .continuous))
                    .submitLabel(.search)
                    .onSubmit { model.search() }
                Button("搜索") { model.search() }
                    .font(DuduTheme.bodyFont(weight: .semibold))
                    .foregroundStyle(DuduTheme.pink)
                    .disabled(model.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if model.didSearch {
                    Button("清除") { model.clearSearch() }
                        .font(DuduTheme.bodyFont())
                        .foregroundStyle(DuduTheme.duduTextDim)
                }
            }
            if let notice = model.notice {
                Text(notice)
                    .font(DuduTheme.captionFont())
                    .foregroundStyle(DuduTheme.duduTextDim)
            }
        }
    }

    @ViewBuilder
    private var resultsSection: some View {
        if model.didSearch {
            VStack(alignment: .leading, spacing: 8) {
                Text(model.hits.isEmpty ? "没有找到相关内容" : "检索结果")
                    .font(DuduTheme.titleFont())
                    .foregroundStyle(DuduTheme.duduText)
                ForEach(model.hits, id: \.rank) { hit in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("#\(hit.rank) 《\(hit.docName)》")
                                .font(DuduTheme.captionFont(weight: .semibold))
                                .foregroundStyle(DuduTheme.duduText)
                            Spacer()
                            Text(String(format: "距离 %.3f", hit.distance))
                                .font(DuduTheme.captionFont())
                                .foregroundStyle(DuduTheme.duduTextDim)
                                .monospacedDigit()
                        }
                        Text(hit.chunkText)
                            .font(DuduTheme.bodyFont())
                            .foregroundStyle(DuduTheme.duduText)
                            .lineLimit(4)
                    }
                    .padding(10)
                    .background(DuduTheme.duduCard)
                    .clipShape(RoundedRectangle(cornerRadius: DuduTheme.radiusChip, style: .continuous))
                }
            }
        }
    }

    private var documentsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("文档")
                    .font(DuduTheme.titleFont())
                    .foregroundStyle(DuduTheme.duduText)
                Spacer()
                Text("\(model.documents.count) 篇")
                    .font(DuduTheme.captionFont())
                    .foregroundStyle(DuduTheme.duduTextDim)
            }
            if model.documents.isEmpty {
                Text("还没有文档，点右上角 + 导入 PDF 或文本开始")
                    .font(DuduTheme.bodyFont())
                    .foregroundStyle(DuduTheme.duduTextDim)
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 0) {
                    ForEach(model.documents) { doc in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(doc.name)
                                    .font(DuduTheme.bodyFont(weight: .medium))
                                    .foregroundStyle(DuduTheme.duduText)
                                    .lineLimit(1)
                                Text("\(doc.chunkCount) 段 · \(doc.createdAt.formatted(date: .numeric, time: .omitted))")
                                    .font(DuduTheme.captionFont())
                                    .foregroundStyle(DuduTheme.duduTextDim)
                            }
                            Spacer()
                            Button {
                                model.delete(doc)
                            } label: {
                                Image(systemName: "trash")
                                    .foregroundStyle(DuduTheme.duduDestructive)
                            }
                            .accessibilityLabel("删除《\(doc.name)》")
                        }
                        .padding(.vertical, 10)
                        Divider()
                            .background(DuduTheme.duduDivider)
                    }
                }
                .padding(.horizontal, 12)
                .background(DuduTheme.duduCard)
                .clipShape(RoundedRectangle(cornerRadius: DuduTheme.radiusCard, style: .continuous))
            }
        }
    }
}

// MARK: - Busy overlay

private struct KnowledgeBusyOverlay: View {
    let text: String
    var body: some View {
        ZStack {
            DuduTheme.duduBackground.opacity(0.6).ignoresSafeArea()
            VStack(spacing: 10) {
                ProgressView()
                Text(text.isEmpty ? "处理中" : text)
                    .font(DuduTheme.bodyFont())
                    .foregroundStyle(DuduTheme.duduText)
            }
            .padding(20)
            .background(DuduTheme.duduCard)
            .clipShape(RoundedRectangle(cornerRadius: DuduTheme.radiusCard, style: .continuous))
        }
    }
}
