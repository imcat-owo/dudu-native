import Combine
import Foundation

// MARK: - D25 · SandboxManager
//
// Dual-mode sandbox manager — Swift port of
// openmuse/apps/mobile/src/sandbox/manager.ts (SandboxManager).
// Same semantics, same storage key names (dudu.* prefixes kept):
//
// - Active backend id persisted in UserDefaults (dudu.sandbox.activeBackend.v1),
//   default "cloud". Switching disconnects the current backend first when it
//   is connected — never silently keeps a live session on the old backend.
// - Server list: server metadata (name/host/port/user/authType, NO secrets)
//   persisted as JSON in UserDefaults (dudu.sandbox.servers.v1); each
//   server's secret lives in the Keychain (SandboxKeychain).
// - Tap-to-switch: setActiveServer(_:) disconnects, activates, persists.
// - Deleting the active server disconnects and falls back to the first
//   remaining server; deleting the last one leaves the cloud backend
//   honestly unconfigured ("no server selected").
//
// NOTE: the old React Native app kept everything (incl. secrets) in
// expo-secure-store under a different bundle id — there is no cross-app
// migration; this native app starts its own store.

private let managerLogger = AppLogger(category: "SandboxManager")

@MainActor
final class SandboxManager: ObservableObject {
    static let shared = SandboxManager()

    private static let activeBackendKey = "dudu.sandbox.activeBackend.v1"
    private static let serversKey = "dudu.sandbox.servers.v1"

    let cloudBackend = SandboxCloudBackend()
    let localBackend = SandboxLocalBackend()

    @Published private(set) var activeBackendId: SandboxBackendId = .cloud
    @Published private(set) var servers: [SandboxServer] = []
    @Published private(set) var activeServerId: String? = nil

    private var cancellables = Set<AnyCancellable>()

    init() {
        // Forward nested backend state changes so a view observing only the
        // manager still re-renders when cloud/local connection state flips.
        cloudBackend.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        localBackend.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        reloadFromDisk()
    }

    /// Re-read UserDefaults into the @Published vars. Used after a backup
    /// rollback rewrites the keys behind the store's back while a failed
    /// import may already have mutated the live vars. Mirrors init's
    /// post-load wiring; never touches live connections.
    func reloadFromDisk() {
        load()
        cloudBackend.setServer(activeServer)
    }

    // MARK: - Derived

    var activeServer: SandboxServer? {
        if let id = activeServerId {
            return servers.first(where: { $0.id == id })
        }
        return servers.first
    }

    func connectionState(for id: SandboxBackendId) -> SandboxConnectionState {
        id == .cloud ? cloudBackend.state : localBackend.state
    }

    func stateDetail(for id: SandboxBackendId) -> String? {
        id == .cloud ? cloudBackend.detail : localBackend.detail
    }

    // MARK: - Dual-mode (req 2)

    /// Switch the active backend. Disconnects whichever backend is currently
    /// connected first, then persists the choice. Matches old setActiveBackend.
    func setActiveBackend(_ id: SandboxBackendId) {
        if cloudBackend.state == .connected { cloudBackend.disconnect() }
        if localBackend.state == .connected { localBackend.disconnect() }
        activeBackendId = id
        UserDefaults.standard.set(id.rawValue, forKey: Self.activeBackendKey)
        managerLogger.info("activeBackend=\(id.rawValue)")
    }

    /// Recover a backend from a terminal error/unavailable state without an
    /// app restart. Synchronous — only flips local state.
    func resetBackend(_ id: SandboxBackendId) {
        if id == .cloud { cloudBackend.reset() } else { localBackend.reset() }
    }

    // MARK: - Server list (req 1)

    /// Add or update a server. `secret`: the new private key / password, or
    /// "" / nil to keep the already-saved secret (edit form semantics).
    /// If it is the active server and the cloud backend is connected, the
    /// live connection is dropped first — never silently keeps stale creds.
    func saveServer(_ server: SandboxServer, secret: String?) {
        let wasActive = (activeServer?.id == server.id) || servers.isEmpty
        if servers.contains(where: { $0.id == server.id }) {
            servers = servers.map { $0.id == server.id ? server : $0 }
        } else {
            servers.append(server)
        }
        if let secret, !secret.isEmpty {
            SandboxKeychain.saveSecret(secret, for: server.id)
        }
        if activeServerId == nil { activeServerId = server.id }
        if wasActive {
            if cloudBackend.state == .connected { cloudBackend.disconnect() }
            cloudBackend.setServer(activeServer)
        }
        persistServers()
        managerLogger.info("saveServer id=\(server.id.prefix(8)) name=\(server.name) host=\(server.host)")
    }

    /// Delete a server and wipe its secret. Deleting the active one
    /// disconnects and falls back to the first remaining server (or none).
    func deleteServer(id: String) {
        let wasActive = activeServer?.id == id
        servers.removeAll(where: { $0.id == id })
        SandboxKeychain.deleteSecret(for: id)
        if wasActive {
            if cloudBackend.state == .connected { cloudBackend.disconnect() }
            activeServerId = servers.first?.id
            cloudBackend.setServer(activeServer)
        } else if activeServerId == id {
            activeServerId = servers.first?.id
        }
        persistServers()
        managerLogger.info("deleteServer id=\(id.prefix(8)) wasActive=\(wasActive)")
    }

    /// Tap-to-switch: disconnect the current server, activate the new one.
    /// Throws sandbox.noServerSelected for an unknown id (old semantics).
    func setActiveServer(id: String) throws {
        guard servers.contains(where: { $0.id == id }) else {
            throw SandboxStoreError.noServerSelected
        }
        guard activeServer?.id != id else { return } // already active
        if cloudBackend.state == .connected { cloudBackend.disconnect() }
        activeServerId = id
        cloudBackend.setServer(activeServer)
        persistServers()
        managerLogger.info("setActiveServer id=\(id.prefix(8))")
    }

    // MARK: - Connect / test (real attempts)

    /// Connect the active cloud server (secret read from the Keychain).
    func connectActiveServer() async throws {
        try await cloudBackend.connect()
    }

    func disconnectActiveServer() {
        cloudBackend.disconnect()
    }

    /// Really attempt a connection with these credentials (saved server or
    /// unsaved draft from the edit form). Returns the honest outcome.
    func testConnection(server: SandboxServer, secret: String?) async -> Result<Void, Error> {
        let resolvedSecret: String
        if let secret, !secret.isEmpty {
            resolvedSecret = secret
        } else {
            resolvedSecret = SandboxKeychain.loadSecret(for: server.id) ?? ""
        }
        return await cloudBackend.testConnection(server: server, secret: resolvedSecret)
    }

    /// Container list for the active cloud server (real `docker ps`).
    func listEnvironments() async throws -> [SandboxEnvironment] {
        try await cloudBackend.listEnvironments()
    }

    // MARK: - Persistence (metadata only — never secrets)

    /// Persisted shape: server metadata + active server id (old
    /// parseServerStore semantics: corrupt data → start empty).
    private struct ServerStore: Codable {
        var servers: [SandboxServer]
        var activeServerId: String?
    }

    private func load() {
        if let raw = UserDefaults.standard.string(forKey: Self.activeBackendKey),
           let id = SandboxBackendId(rawValue: raw)
        {
            activeBackendId = id
        }
        guard let data = UserDefaults.standard.data(forKey: Self.serversKey),
              let store = try? JSONDecoder().decode(ServerStore.self, from: data)
        else { return }
        // De-dupe by id; invalid entries are dropped.
        var seen = Set<String>()
        servers = store.servers.filter { seen.insert($0.id).inserted && $0.isValid }
        if let id = store.activeServerId, servers.contains(where: { $0.id == id }) {
            activeServerId = id
        } else {
            activeServerId = servers.first?.id
        }
    }

    private func persistServers() {
        let store = ServerStore(servers: servers, activeServerId: activeServerId)
        if let data = try? JSONEncoder().encode(store) {
            UserDefaults.standard.set(data, forKey: Self.serversKey)
        }
    }

    // MARK: - Backup

    /// Every key this store owns — for backup export + restore rollback.
    ///
    /// Secrets are NEVER here: they live in the Keychain (SandboxKeychain)
    /// and the backup never touches the Keychain, so a restored server
    /// record reconnects only after she re-enters its secret — the same
    /// honesty rule as API keys in the backup footer.
    nonisolated static var backupAllKeys: [String] {
        [activeBackendKey, serversKey]
    }

    /// Snapshot as key → plist-encoded value (opaque, like
    /// OurSpaceStore.backupRecords). The servers blob is JSON Data, the
    /// active backend id a String. Note the active SERVER id rides inside
    /// the servers JSON (ServerStore), not as its own key.
    nonisolated static func backupRecords() -> [(key: String, data: Data, count: Int)] {
        let defaults = UserDefaults.standard
        return backupAllKeys.compactMap { key in
            guard let value = defaults.object(forKey: key),
                  let data = try? PropertyListSerialization.data(
                      fromPropertyList: value, format: .binary, options: 0)
            else { return nil }
            return (key, data, 1)
        }
    }

    /// Merge one backup's records into the live store. Local-wins: servers
    /// union by id (a local record keeps its fields — the backup's copy may
    /// predate a host/port edit), backup-only servers are appended; the
    /// active backend id is taken from the backup only when this device
    /// never chose one. @Published vars are assigned directly — no
    /// disconnect/reconnect side effects — then the cloud backend is
    /// re-pointed at the (possibly new) active server, like init does after
    /// load(). Returns (imported, skipped).
    @discardableResult
    func restoreBackupRecords(
        _ records: [(key: String, data: Data, count: Int)]
    ) -> (imported: Int, skipped: Int) {
        var imported = 0
        var skipped = 0
        let defaults = UserDefaults.standard
        for (key, data, _) in records {
            guard Self.backupAllKeys.contains(key),
                  let value = try? PropertyListSerialization.propertyList(
                      from: data, options: [], format: nil)
            else { skipped += 1; continue }
            switch key {
            case Self.serversKey:
                guard let d = value as? Data,
                      let incoming = try? JSONDecoder().decode(
                          ServerStore.self, from: d) else { skipped += 1; continue }
                var added = 0
                for s in incoming.servers where s.isValid {
                    guard !servers.contains(where: { $0.id == s.id }) else { continue }
                    servers.append(s)
                    added += 1
                }
                if activeServerId == nil, let id = incoming.activeServerId,
                   servers.contains(where: { $0.id == id }) {
                    activeServerId = id
                }
                guard added > 0 else { skipped += 1; continue }
                persistServers()
                cloudBackend.setServer(activeServer)
                imported += 1
            case Self.activeBackendKey:
                guard defaults.object(forKey: key) == nil,
                      let raw = value as? String,
                      let id = SandboxBackendId(rawValue: raw)
                else { skipped += 1; continue }
                activeBackendId = id
                defaults.set(raw, forKey: key)
                imported += 1
            default:
                skipped += 1
            }
        }
        return (imported, skipped)
    }
}

/// Store-level errors (all carry i18n keys — the UI translates them).
enum SandboxStoreError: Error, LocalizedError {
    case noServerSelected

    var errorDescription: String? { "sandbox.noServerSelected" }
}
