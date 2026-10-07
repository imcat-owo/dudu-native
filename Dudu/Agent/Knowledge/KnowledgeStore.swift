import Foundation
import NaturalLanguage
import SQLiteVec

// MARK: - KnowledgeStore · D14 on-device knowledge base (RAG)
//
// End-side vector retrieval, zero network, zero extra model downloads:
//   - Storage: sqlite-vec `vec0` virtual tables via jkrukowski/SQLiteVec (SPM).
//     Vector dimension is probed at runtime from the actual embedding model —
//     never hardcoded.
//   - Embeddings: Apple NaturalLanguage NLEmbedding. Sentence embeddings for
//     English (the only language iOS ships sentence vectors for); for
//     majority-CJK text the honest fallback is averaged word vectors over
//     jieba segmentation (Shared/TextSegmenter). Two vec tables, one per
//     embedding space, so distances are never compared across spaces.
//   - Chunking: paragraph-based, ~800 chars with ~120 chars overlap
//     (mobile-rag-plan.md §3.3).
//
// Threading: `actor`, mirroring ProviderConfigDB / VoiceCorrectionDB. Every DB
// call is off the MainActor by construction. NLEmbedding is thread-safe per
// Apple docs; TextSegmenter is Sendable.
//
// Schema (knowledge.db, next to the other DuduChat databases):
//   kb_docs(id TEXT PK, name, chunkCount, createdAt)
//   kb_chunks(rowid INTEGER PK, docId, lang, chunkIndex, text)
//   kb_meta(key TEXT PK, value)              — probed vec dims per table
//   kb_vec_en  USING vec0(embedding float[N]) — English sentence space
//   kb_vec_cjk USING vec0(embedding float[M]) — CJK word-average space

private let logger = AppLogger(category: "Knowledge")

// MARK: - Public models

/// One indexed document.
public struct KnowledgeDocument: Identifiable, Sendable {
    public let id: String
    public let name: String
    public let chunkCount: Int
    public let createdAt: Date
}

/// One kNN search hit, ranked by ascending distance.
public struct KnowledgeHit: Sendable {
    public let docId: String
    public let docName: String
    public let chunkText: String
    /// sqlite-vec L2 distance over L2-normalized vectors — smaller is closer,
    /// ordering-equivalent to cosine similarity.
    public let distance: Double
    public let rank: Int
}

/// Failures surfaced honestly to the UI — never silently stubbed.
public enum KnowledgeError: Error, LocalizedError {
    case noEmbeddingModel
    case embeddingDimensionChanged
    case emptyText
    case noExtractableText
    case unexpectedDatabaseState

    public var errorDescription: String? {
        switch self {
        case .noEmbeddingModel:
            return "本机嵌入模型不可用，知识库无法索引"
        case .embeddingDimensionChanged:
            return "系统嵌入模型维度发生变化，请删除文档后重新导入"
        case .emptyText:
            return "文档内容为空，没有可索引的文本"
        case .noExtractableText:
            return "这个 PDF 提取不到文字（可能是扫描件），暂不支持"
        case .unexpectedDatabaseState:
            return "知识库数据库状态异常，请稍后重试"
        }
    }
}

// MARK: - Text chunking (paragraph-based)

enum KnowledgeChunker {
    static let targetSize = 800
    static let overlap = 120

    /// Paragraph-based chunking: blank-line paragraphs are the unit, soft
    /// line-wraps inside a paragraph (typical of PDF text extraction) are
    /// joined back with a space, paragraphs are greedily packed to
    /// ~targetSize chars, and oversized pieces are hard-split with overlap.
    /// Each chunk after the first carries the previous chunk's tail so
    /// sentence context survives the boundary.
    static func chunk(_ text: String) -> [String] {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        let paragraphs: [String] = normalized
            .components(separatedBy: "\n\n")
            .map { block in
                block.components(separatedBy: "\n")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                    .joined(separator: " ")
            }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        // Greedily pack paragraphs.
        var packed: [String] = []
        var current = ""
        for para in paragraphs {
            if current.isEmpty {
                current = para
            } else if current.count + 1 + para.count <= targetSize {
                current += " " + para
            } else {
                packed.append(current)
                current = para
            }
        }
        if !current.isEmpty { packed.append(current) }

        // Hard-split oversized pieces with overlap; carry the tail forward.
        var out: [String] = []
        var carry = ""
        for piece in packed {
            var parts = splitWithOverlap(piece)
            if !carry.isEmpty, !parts.isEmpty {
                parts[0] = carry + " " + parts[0]
            }
            if let last = parts.last {
                carry = last.count > overlap ? String(last.suffix(overlap)) : last
            }
            out.append(contentsOf: parts)
        }
        return out.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private static func splitWithOverlap(_ s: String) -> [String] {
        guard s.count > targetSize else { return [s] }
        var pieces: [String] = []
        var start = s.startIndex
        let stride = targetSize - overlap
        while start < s.endIndex {
            let end = s.index(start, offsetBy: targetSize, limitedBy: s.endIndex) ?? s.endIndex
            pieces.append(String(s[start..<end]))
            if end == s.endIndex { break }
            start = s.index(start, offsetBy: stride, limitedBy: s.endIndex) ?? s.endIndex
        }
        return pieces
    }
}

// MARK: - On-device embeddings (NaturalLanguage, no network)

enum KnowledgeEmbeddings {
    /// Embedding space. English chunks use Apple's sentence embeddings;
    /// CJK chunks use averaged word vectors (iOS ships no sentence
    /// embeddings for Chinese — this fallback is honest, not silent).
    enum Space: String, CaseIterable {
        case english
        case cjk

        var vecTable: String {
            switch self {
            case .english: return "kb_vec_en"
            case .cjk: return "kb_vec_cjk"
            }
        }
    }

    /// Route by script: ≥50% Han ideographs in the first 200 chars → CJK.
    /// (Same rule as Shared/TextSegmenter; duplicated here because that
    /// helper is internal to its module surface.)
    static func space(for text: String) -> Space {
        let sample = text.prefix(200)
        var han = 0
        var nonWhitespace = 0
        for scalar in sample.unicodeScalars {
            if scalar.properties.isWhitespace { continue }
            nonWhitespace += 1
            if scalar.value >= 0x4E00 && scalar.value <= 0x9FFF { han += 1 }
        }
        guard nonWhitespace > 0 else { return .english }
        return Double(han) / Double(nonWhitespace) >= 0.5 ? .cjk : .english
    }

    /// Dimension probed at runtime from the real model: embed a probe
    /// sentence and measure. Falls back to NLEmbedding.dimension only if
    /// the probe itself yields nothing.
    static func probeDimension(space: Space) -> Int? {
        guard let model = model(for: space) else { return nil }
        let probe: String
        switch space {
        case .english:
            probe = "The quick brown fox jumps over the lazy dog."
        case .cjk:
            probe = "敏捷的棕色狐狸跳过了懒惰的狗。"
        }
        if let v = embed(probe, space: space) {
            return v.count
        }
        return model.dimension
    }

    /// L2-normalized embedding, or nil when the text yields no vector.
    static func embed(_ text: String, space: Space) -> [Float]? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let model = model(for: space) else { return nil }
        let rawVectors: [[Double]]
        switch space {
        case .english:
            // Sentence embedding consumes the whole chunk at once.
            guard let v = model.vector(for: trimmed) else { return nil }
            rawVectors = [v]
        case .cjk:
            // Word vectors averaged over jieba segmentation (search mode —
            // finer granularity, better for retrieval).
            let tokens = TextSegmenter.shared.segmentForSearch(trimmed)
            rawVectors = tokens.compactMap { model.vector(for: $0) }
            guard !rawVectors.isEmpty else { return nil }
        }
        var sum = [Double](repeating: 0, count: model.dimension)
        for v in rawVectors {
            for i in 0..<min(v.count, sum.count) { sum[i] += v[i] }
        }
        var avg = sum.map { $0 / Double(rawVectors.count) }
        let norm = sqrt(avg.reduce(0) { $0 + $1 * $1 })
        guard norm > 0, norm.isFinite else { return nil }
        avg = avg.map { $0 / norm }
        return avg.map(Float.init)
    }

    private static func model(for space: Space) -> NLEmbedding? {
        switch space {
        case .english:
            return NLEmbedding.sentenceEmbedding(for: NLLanguage(rawValue: "en"))
        case .cjk:
            return NLEmbedding.wordEmbedding(for: NLLanguage(rawValue: "zh-Hans"))
        }
    }
}

// MARK: - Store

actor KnowledgeStore {

    // MARK: Singleton

    /// Shared instance. `nil` only if the DB cannot be opened at all, in
    /// which case callers degrade to "knowledge unavailable" rather than
    /// crashing — same pattern as VoiceCorrectionDB.
    static let shared: KnowledgeStore? = {
        do {
            return try KnowledgeStore()
        } catch {
            logger.error("[Knowledge][DBHealth] unrecoverable open failure: \(error) — knowledge disabled")
            return nil
        }
    }()

    // MARK: File locations

    /// Same DuduChat folder the other databases live in.
    static func defaultURL() -> URL {
        let library = FileManager.default
            .urls(for: .libraryDirectory, in: .userDomainMask)[0]
        let base = library.appendingPathComponent("DuduChat", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("knowledge.db")
    }

    // MARK: State

    private let db: Database
    private var schemaReady = false
    /// Probed vector dimension per vec table, cached after first probe.
    private var probedDims: [String: Int] = [:]

    init(dbURL: URL? = nil) throws {
        // Must run before any other SQLiteVec call (extension init).
        try SQLiteVec.initialize()
        let url = dbURL ?? Self.defaultURL()
        self.db = try Database(.uri(url.path))
        logger.info("[Knowledge][DBHealth] opened at \(url.path)")
    }

    // MARK: Schema

    private func ensureSchema() async throws {
        if schemaReady { return }
        try await db.execute("""
            CREATE TABLE IF NOT EXISTS kb_docs(
                id TEXT PRIMARY KEY, name TEXT NOT NULL,
                chunkCount INTEGER NOT NULL, createdAt REAL NOT NULL)
            """)
        try await db.execute("""
            CREATE TABLE IF NOT EXISTS kb_chunks(
                rowid INTEGER PRIMARY KEY, docId TEXT NOT NULL,
                lang TEXT NOT NULL, chunkIndex INTEGER NOT NULL,
                text TEXT NOT NULL)
            """)
        try await db.execute("""
            CREATE TABLE IF NOT EXISTS kb_meta(
                key TEXT PRIMARY KEY, value TEXT NOT NULL)
            """)
        for space in KnowledgeEmbeddings.Space.allCases {
            guard let dim = probedDims[space.vecTable] ?? KnowledgeEmbeddings.probeDimension(space: space) else {
                logger.warning("[Knowledge] no embedding model for space \(space.rawValue) — its vec table stays uncreated")
                continue
            }
            probedDims[space.vecTable] = dim
            let dimKey = "dim:\(space.vecTable)"
            let existing = try await db.query(
                "SELECT value FROM kb_meta WHERE key = ?", params: [dimKey])
            if let row = existing.first, let recorded = row["value"] as? String,
               let recordedDim = Int(recorded), recordedDim != dim {
                // The OS embedding model changed dimension — old vectors are
                // garbage now. Refuse to mix spaces; the user re-imports.
                throw KnowledgeError.embeddingDimensionChanged
            }
            try await db.execute(
                "CREATE VIRTUAL TABLE IF NOT EXISTS \(space.vecTable) USING vec0(embedding float[\(dim)])")
            try await db.execute(
                "INSERT OR IGNORE INTO kb_meta(key, value) VALUES (?, ?)",
                params: [dimKey, String(dim)])
        }
        schemaReady = true
    }

    // MARK: - Public API

    /// Index a document: chunk → embed → store. Returns the chunk count.
    /// `progress(done, total)` is called after each chunk is embedded.
    func addDocument(
        id: String,
        name: String,
        text: String,
        progress: (@MainActor @Sendable (Int, Int) -> Void)? = nil
    ) async throws -> Int {
        try await ensureSchema()
        let chunks = KnowledgeChunker.chunk(text)
        guard !chunks.isEmpty else { throw KnowledgeError.emptyText }
        var embedded: [(chunk: String, space: KnowledgeEmbeddings.Space, vector: [Float])] = []
        embedded.reserveCapacity(chunks.count)
        for (i, chunkText) in chunks.enumerated() {
            let space = KnowledgeEmbeddings.space(for: chunkText)
            guard let vector = KnowledgeEmbeddings.embed(chunkText, space: space) else {
                logger.warning("[Knowledge] chunk \(i) of doc \(id) produced no vector — skipped")
                await progress?(i + 1, chunks.count)
                continue
            }
            embedded.append((chunkText, space, vector))
            await progress?(i + 1, chunks.count)
        }
        guard !embedded.isEmpty else { throw KnowledgeError.noEmbeddingModel }
        try await db.transaction {
            for (idx, item) in embedded.enumerated() {
                try await db.execute(
                    "INSERT INTO kb_chunks(docId, lang, chunkIndex, text) VALUES (?, ?, ?, ?)",
                    params: [id, item.space.rawValue, idx, item.chunk])
                let rowId = try await lastInsertRowId()
                try await db.execute(
                    "INSERT INTO \(item.space.vecTable)(rowid, embedding) VALUES (?, ?)",
                    params: [rowId, item.vector])
            }
            try await db.execute(
                "INSERT OR REPLACE INTO kb_docs(id, name, chunkCount, createdAt) VALUES (?, ?, ?, ?)",
                params: [id, name, embedded.count, Date().timeIntervalSince1970])
        }
        logger.info("[Knowledge] indexed doc \(id) (\(name)): \(embedded.count) chunks")
        return embedded.count
    }

    /// Remove a document and all its chunks/vectors.
    func deleteDocument(id: String) async throws {
        try await ensureSchema()
        let rows = try await db.query(
            "SELECT rowid, lang FROM kb_chunks WHERE docId = ?", params: [id])
        try await db.transaction {
            for row in rows {
                guard let rowId = row["rowid"] as? Int,
                      let lang = row["lang"] as? String,
                      let space = KnowledgeEmbeddings.Space(rawValue: lang) else { continue }
                try await db.execute(
                    "DELETE FROM \(space.vecTable) WHERE rowid = ?", params: [rowId])
            }
            try await db.execute("DELETE FROM kb_chunks WHERE docId = ?", params: [id])
            try await db.execute("DELETE FROM kb_docs WHERE id = ?", params: [id])
        }
        logger.info("[Knowledge] deleted doc \(id) (\(rows.count) chunks)")
    }

    /// kNN search: embed the query, return the top chunks by vector distance.
    /// Returns [] when the query yields no embedding — never fake hits.
    func knnSearch(query: String, topK: Int) async throws -> [KnowledgeHit] {
        try await ensureSchema()
        let space = KnowledgeEmbeddings.space(for: query)
        guard let queryVec = KnowledgeEmbeddings.embed(query, space: space) else {
            return []
        }
        let limit = max(1, topK)
        let vecRows = try await db.query(
            "SELECT rowid, distance FROM \(space.vecTable) WHERE embedding MATCH ? ORDER BY distance LIMIT ?",
            params: [queryVec, limit])
        var hits: [KnowledgeHit] = []
        for (rank, vecRow) in vecRows.enumerated() {
            guard let rowId = vecRow["rowid"] as? Int,
                  let distance = vecRow["distance"] as? Double else { continue }
            let chunkRows = try await db.query(
                """
                SELECT c.text AS text, c.docId AS docId, d.name AS name
                FROM kb_chunks c JOIN kb_docs d ON d.id = c.docId
                WHERE c.rowid = ?
                """,
                params: [rowId])
            guard let chunk = chunkRows.first,
                  let text = chunk["text"] as? String,
                  let docId = chunk["docId"] as? String,
                  let name = chunk["name"] as? String else { continue }
            hits.append(KnowledgeHit(
                docId: docId, docName: name, chunkText: text,
                distance: distance, rank: rank + 1))
        }
        return hits
    }

    /// All indexed documents, newest first.
    func listDocuments() async throws -> [KnowledgeDocument] {
        try await ensureSchema()
        let rows = try await db.query(
            "SELECT id, name, chunkCount, createdAt FROM kb_docs ORDER BY createdAt DESC")
        return rows.compactMap { row in
            guard let id = row["id"] as? String,
                  let name = row["name"] as? String,
                  let chunkCount = row["chunkCount"] as? Int,
                  let createdAt = row["createdAt"] as? Double else { return nil }
            return KnowledgeDocument(
                id: id, name: name, chunkCount: chunkCount,
                createdAt: Date(timeIntervalSince1970: createdAt))
        }
    }

    // MARK: Helpers

    private func lastInsertRowId() async throws -> Int {
        let rows = try await db.query("SELECT last_insert_rowid() AS id")
        guard let row = rows.first, let id = row["id"] as? Int else {
            throw KnowledgeError.unexpectedDatabaseState
        }
        return id
    }
}
