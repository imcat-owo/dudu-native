import Combine
import SwiftUI
import UIKit

// MARK: - TaskCardStore · task progress cards
//
// iOS-widget-style small cards in 我们的空间 show background task progress.
// Any part of the app (knowledge indexer, AI tools, downloads) reports
// progress here via the upsert hook; the UI subscribes and renders live.
//
// Ported from the old Dudu spec (openmuse/apps/mobile/src/our-space/
// task-progress.ts): same semantics — progress clamped 0...1, progress
// hitting 1 auto-completes, a "running" task silent for 24h is presumed
// abandoned and auto-marked "stuck" (so a crashed task can never leave a
// stale "running" card), done tasks sink below active ones.
//
// Card accent palette is curated from DuduTheme only — zero hardcoded hex.
// Card background: optional user photo (JPEG under Application Support).

enum TaskStatus: String, Codable {
    case running
    case stuck
    case done

    var label: String {
        switch self {
        case .running: return "进行中"
        case .stuck: return "卡住了"
        case .done: return "已完成"
        }
    }
}

/// Curated card accent palette — keys, never raw colors.
/// null (nil) = theme default pink.
enum TaskCardAccent: String, Codable, CaseIterable {
    case pink
    case pinkSoft
    case brown
    case chip
    case dim

    var label: String {
        switch self {
        case .pink: return "樱粉"
        case .pinkSoft: return "浅粉"
        case .brown: return "可可棕"
        case .chip: return "奶咖"
        case .dim: return "灰棕"
        }
    }

    @MainActor
    var color: Color {
        switch self {
        case .pink: return DuduTheme.pink
        case .pinkSoft: return DuduTheme.pinkSoft
        case .brown: return DuduTheme.brandBrown
        case .chip: return DuduTheme.duduIconChip
        case .dim: return DuduTheme.duduTextDim
        }
    }
}

struct BackgroundTask: Codable, Identifiable, Equatable {
    var id: String
    /// Display name, e.g. "知识库索引".
    var name: String
    /// 0...1.
    var progress: Double
    /// Current stage text, e.g. "正在读第 3/10 个文件".
    var stage: String
    var status: TaskStatus
    /// Curated accent key. nil = theme default (pink).
    var accent: TaskCardAccent?
    /// JPEG filename under Application Support/TaskCards. nil = theme default.
    var backgroundFile: String?
    var updatedAt: Date
    var createdAt: Date

    @MainActor
    var accentColor: Color { accent?.color ?? DuduTheme.pink }
}

@MainActor
final class TaskCardStore: ObservableObject {
    static let shared = TaskCardStore()

    /// A "running" task silent this long is presumed abandoned → "stuck".
    static let stuckAfter: TimeInterval = 24 * 60 * 60

    @Published private(set) var tasks: [BackgroundTask] = []

    private let defaults = UserDefaults.standard
    private let indexKey = "dudu.taskcards.v1.index"
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .secondsSince1970
        return e
    }()
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .secondsSince1970
        return d
    }()

    private func itemKey(_ id: String) -> String { "dudu.taskcards.v1.\(id)" }

    private var cardsDir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("TaskCards", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    init() {
        load()
        sweepStale()
    }

    // MARK: Engine hook

    /// Create or update a task. Progress is clamped to 0...1.
    /// Callers: knowledge indexer, downloads, AI tools — anything with progress.
    @discardableResult
    func upsert(
        id: String,
        name: String,
        progress: Double,
        stage: String,
        status: TaskStatus = .running,
        accent: TaskCardAccent? = nil
    ) -> BackgroundTask? {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty else { return nil }
        sweepStale()
        let now = Date()
        let prev = tasks.first(where: { $0.id == id })
        let clamped: Double = progress.isNaN ? 0 : min(1, max(0, progress))
        var task = BackgroundTask(
            id: id,
            name: n,
            progress: clamped,
            stage: stage,
            status: status,
            accent: accent ?? prev?.accent,
            backgroundFile: prev?.backgroundFile,
            updatedAt: now,
            createdAt: prev?.createdAt ?? now
        )
        // Auto-complete: progress hit 1 → done (unless explicitly stuck).
        if task.progress >= 1, task.status == .running {
            task.status = .done
        }
        persist(task)
        saveIndex()
        resort()
        return task
    }

    /// Manual task, created from the Our Space UI.
    @discardableResult
    func createManual(name: String, stage: String) -> BackgroundTask? {
        upsert(id: UUID().uuidString, name: name, progress: 0, stage: stage)
    }

    func remove(id: String) {
        if let task = tasks.first(where: { $0.id == id }), let file = task.backgroundFile {
            try? FileManager.default.removeItem(at: cardsDir.appendingPathComponent(file))
        }
        tasks.removeAll { $0.id == id }
        defaults.removeObject(forKey: itemKey(id))
        saveIndex()
    }

    func setAccent(id: String, accent: TaskCardAccent?) {
        guard var task = tasks.first(where: { $0.id == id }) else { return }
        task.accent = accent
        task.updatedAt = Date()
        persist(task)
        resort()
    }

    func markDone(id: String) {
        mutate(id: id) { task in
            task.status = .done
            task.progress = 1
        }
    }

    func reopen(id: String) {
        mutate(id: id) { task in
            if task.status == .done {
                task.status = .running
                task.progress = 0
            } else {
                task.status = .running
            }
        }
    }

    /// Store a user-picked photo as the card background (JPEG, aspect kept).
    /// Returns false when the data is not a decodable image.
    @discardableResult
    func setBackgroundJPEG(id: String, data: Data) -> Bool {
        guard var task = tasks.first(where: { $0.id == id }),
              let image = UIImage(data: data),
              let jpeg = image.jpegData(compressionQuality: 0.8) else { return false }
        let filename = "task_\(id).jpg"
        do {
            try jpeg.write(to: cardsDir.appendingPathComponent(filename), options: .atomic)
        } catch {
            return false
        }
        if let old = task.backgroundFile, old != filename {
            try? FileManager.default.removeItem(at: cardsDir.appendingPathComponent(old))
        }
        task.backgroundFile = filename
        task.updatedAt = Date()
        persist(task)
        resort()
        return true
    }

    func clearBackground(id: String) {
        guard var task = tasks.first(where: { $0.id == id }) else { return }
        if let file = task.backgroundFile {
            try? FileManager.default.removeItem(at: cardsDir.appendingPathComponent(file))
        }
        task.backgroundFile = nil
        task.updatedAt = Date()
        persist(task)
        resort()
    }

    func backgroundUIImage(for task: BackgroundTask) -> UIImage? {
        guard let file = task.backgroundFile else { return nil }
        let url = cardsDir.appendingPathComponent(file)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    var activeTasks: [BackgroundTask] { tasks.filter { $0.status != .done } }
    var doneTasks: [BackgroundTask] { tasks.filter { $0.status == .done } }

    // MARK: Internals

    private func mutate(id: String, _ change: (inout BackgroundTask) -> Void) {
        guard var task = tasks.first(where: { $0.id == id }) else { return }
        change(&task)
        task.updatedAt = Date()
        persist(task)
        resort()
    }

    /// Active first (running/stuck), then done; newest first inside each band.
    private func resort() {
        tasks.sort { a, b in
            let rank: (BackgroundTask) -> Int = { $0.status == .done ? 1 : 0 }
            if rank(a) != rank(b) { return rank(a) < rank(b) }
            return a.updatedAt > b.updatedAt
        }
    }

    /// Mark long-silent running tasks as stuck (persisted). Any upsert
    /// refreshes updatedAt, so only truly abandoned tasks trip this.
    private func sweepStale(now: Date = Date()) {
        var changed = false
        for i in tasks.indices where tasks[i].status == .running {
            if now.timeIntervalSince(tasks[i].updatedAt) > Self.stuckAfter {
                tasks[i].status = .stuck
                tasks[i].updatedAt = now
                persist(tasks[i])
                changed = true
            }
        }
        if changed { resort() }
    }

    private func persist(_ task: BackgroundTask) {
        if let data = try? encoder.encode(task) {
            defaults.set(data, forKey: itemKey(task.id))
        }
        if !tasks.contains(where: { $0.id == task.id }) {
            tasks.append(task)
        } else if let i = tasks.firstIndex(where: { $0.id == task.id }) {
            tasks[i] = task
        }
    }

    private func saveIndex() {
        if let data = try? encoder.encode(tasks.map(\.id)) {
            defaults.set(data, forKey: indexKey)
        }
    }

    private func load() {
        guard let data = defaults.data(forKey: indexKey),
              let ids = try? decoder.decode([String].self, from: data) else { return }
        var loaded: [BackgroundTask] = []
        for id in ids {
            guard let raw = defaults.data(forKey: itemKey(id)),
                  var task = try? decoder.decode(BackgroundTask.self, from: raw) else { continue }
            // Old persisted tasks may carry an unknown accent string —
            // the Codable enum decode already failed those; normalize.
            if task.backgroundFile?.isEmpty == true { task.backgroundFile = nil }
            loaded.append(task)
        }
        tasks = loaded
        resort()
    }
}
