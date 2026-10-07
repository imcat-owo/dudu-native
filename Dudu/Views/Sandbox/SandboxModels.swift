import Foundation

// MARK: - D25 · Sandbox models
//
// Swift port of the old Dudu sandbox domain
// (openmuse/apps/mobile/src/sandbox/{types,servers}.ts).
// Rename map applied: Minis->Dudu, com.openminis.clone->com.dudu.ios,
// minis->dudu prefixes. iCloud refs dropped (no iCloud entitlement).
//
// Secrets are NEVER part of these models. The SSH private key / password
// lives only in the Keychain (SandboxKeychain.swift), keyed by server id;
// the persisted server record carries non-secret fields only.

// MARK: - Backend identity

/// Which sandbox backend is active. Persisted; user-switchable in-app.
/// Old key: dudu.sandbox.activeBackend.v1 (AsyncStorage) — same key here.
enum SandboxBackendId: String, Codable, CaseIterable {
    case cloud
    case local

    var nameKey: String {
        switch self {
        case .cloud: return "sandbox.backend.cloud"
        case .local: return "sandbox.backend.local"
        }
    }
}

// MARK: - Connection state

/// Connection state of a backend. Honest — never claims connected when it isn't.
enum SandboxConnectionState: String {
    case disconnected
    case connecting
    case connected
    case unavailable // backend cannot run in this build (e.g. iSH native module missing)
    case error

    var statusKey: String { "sandbox.status.\(rawValue)" }
}

// MARK: - SSH auth

enum SandboxAuthType: String, Codable {
    case key
    case password

    var authKey: String { "sandbox.authType.\(rawValue)" }
}

// MARK: - Server record (no secrets)

/// One cloud-Docker host. Non-secret fields only — persisted as JSON in
/// UserDefaults (dudu.sandbox.servers.v1). The secret (private key / password)
/// is stored separately in the Keychain under this record's id and is never
/// written to UserDefaults, never logged, never put in a URL.
struct SandboxServer: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var host: String
    var port: Int
    var username: String
    var authType: SandboxAuthType

    static func newId() -> String {
        "srv_\(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(12))"
    }

    /// Display form: user@host:port (no secret).
    var addressLine: String { "\(username)@\(host):\(port)" }

    /// Basic validation, mirroring the old SshConfigForm save() guard.
    var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (1 ... 65535).contains(port)
    }
}

// MARK: - Environment (container)

/// A Docker container (Backend A) or sandbox environment (Backend B).
struct SandboxEnvironment: Identifiable, Equatable {
    let id: String
    let name: String
    /// e.g. "running" | "exited" | "paused" (docker) or "booted" (ish).
    let status: String
    let image: String?

    var isRunning: Bool { status == "running" || status == "booted" }
}

// MARK: - Command result

struct SandboxCommandResult {
    let stdout: String
    let stderr: String
    let exitCode: Int
    let durationMs: Int
}
