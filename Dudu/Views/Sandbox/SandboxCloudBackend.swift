import Foundation

// MARK: - D25 · SandboxCloudBackend
//
// Swift port of openmuse/apps/mobile/src/sandbox/backend-ssh-docker.ts
// (SshDockerBackend). Backend A: her cloud server's Docker, reached over
// SSH via the relay (SandboxRelayTransport) — the same real path the old
// app used.
//
// Honesty contract (same as the old backend):
// - connect() probes a REAL SSH session before claiming connected, then
//   verifies Docker is actually there (`docker info`).
// - No config / no saved secret → connect() fails with a real error,
//   never pretends.
// - stateDetail() carries an i18n key or the raw relay error (which never
//   contains secrets — the transport strips them).

private let cloudBackendLogger = AppLogger(category: "SandboxCloud")

@MainActor
final class SandboxCloudBackend: ObservableObject {
    @Published private(set) var state: SandboxConnectionState = .disconnected
    @Published private(set) var detail: String? = nil

    /// The server whose config is currently loaded (nil = unconfigured).
    private(set) var activeServer: SandboxServer?

    func setServer(_ server: SandboxServer?) {
        activeServer = server
    }

    // MARK: - Test connection (the real thing)

    /// Really attempts the connection: the relay opens a genuine SSH
    /// session with these credentials and runs `true`. Returns the honest
    /// outcome — success, or the relay/SSH error to show her.
    /// Does not change backend state and does not require the server to be
    /// saved first (used by the edit form's "test" button).
    func testConnection(server: SandboxServer, secret: String) async -> Result<Void, Error> {
        guard !secret.isEmpty else {
            return .failure(SandboxRelayError.probeFailed("sandbox.cloud.noConfig"))
        }
        do {
            try await SandboxRelayTransport.probe(credentials(for: server, secret: secret))
            cloudBackendLogger.info("testConnection host=\(server.host) ok=true")
            return .success(())
        } catch {
            cloudBackendLogger.info("testConnection host=\(server.host) ok=false")
            return .failure(error)
        }
    }

    // MARK: - Connect / disconnect

    /// Connect using the server set via setServer(_:). The secret is read
    /// from the Keychain at connect time (never cached in memory longer
    /// than the call needs).
    func connect() async throws {
        guard let server = activeServer else {
            state = .error
            detail = "sandbox.cloud.noConfig"
            throw SandboxRelayError.probeFailed("sandbox.cloud.noConfig")
        }
        guard let secret = SandboxKeychain.loadSecret(for: server.id), !secret.isEmpty else {
            state = .error
            detail = "sandbox.cloud.noConfig"
            throw SandboxRelayError.probeFailed("sandbox.cloud.noConfig")
        }
        state = .connecting
        detail = nil
        do {
            let creds = credentials(for: server, secret: secret)
            // 1. Real SSH probe.
            try await SandboxRelayTransport.probe(creds)
            // 2. Verify Docker is actually there before claiming connected.
            let info = try await SandboxRelayTransport.exec(
                creds,
                command: "docker info --format '{{json .ServerVersion}}'"
            )
            guard info.exitCode == 0 else {
                throw SandboxRelayError.probeFailed(
                    String((info.stderr.isEmpty ? "docker not available" : info.stderr).prefix(300))
                )
            }
            state = .connected
            detail = nil
            cloudBackendLogger.info("connect host=\(server.host) ok=true")
        } catch {
            state = .error
            detail = (error as? SandboxRelayError)?.errorDescription ?? error.localizedDescription
            cloudBackendLogger.info("connect host=\(server.host) ok=false")
            throw error
        }
    }

    func disconnect() {
        state = .disconnected
        detail = nil
    }

    /// Recover from a terminal "error" state without an app restart.
    /// Synchronous: only flips local state, never touches the network.
    func reset() {
        state = .disconnected
        detail = nil
    }

    // MARK: - Environments (real `docker ps`)

    func listEnvironments() async throws -> [SandboxEnvironment] {
        guard state == .connected, let server = activeServer else {
            throw SandboxRelayError.probeFailed("sandbox.notConnected")
        }
        guard let secret = SandboxKeychain.loadSecret(for: server.id), !secret.isEmpty else {
            throw SandboxRelayError.probeFailed("sandbox.cloud.noConfig")
        }
        let r = try await SandboxRelayTransport.exec(
            credentials(for: server, secret: secret),
            command: "docker ps -a --format '{{json .}}'"
        )
        guard r.exitCode == 0 else {
            throw SandboxRelayError.requestFailed(
                String((r.stderr.isEmpty ? "docker ps failed" : r.stderr).prefix(300))
            )
        }
        return r.stdout.split(separator: "\n").compactMap(Self.parseDockerPsLine)
    }

    func startEnvironment(id: String) async throws {
        _ = try await runDockerCommand("docker start \(shellEscape(id))", failureKey: "sandbox.docker.startFailed")
    }

    func stopEnvironment(id: String) async throws {
        _ = try await runDockerCommand("docker stop \(shellEscape(id))", failureKey: "sandbox.docker.stopFailed")
    }

    private func runDockerCommand(_ command: String, failureKey: String) async throws -> SandboxRelayResult {
        guard state == .connected, let server = activeServer else {
            throw SandboxRelayError.probeFailed("sandbox.notConnected")
        }
        guard let secret = SandboxKeychain.loadSecret(for: server.id), !secret.isEmpty else {
            throw SandboxRelayError.probeFailed("sandbox.cloud.noConfig")
        }
        let r = try await SandboxRelayTransport.exec(credentials(for: server, secret: secret), command: command)
        guard r.exitCode == 0 else {
            throw SandboxRelayError.requestFailed(
                String((r.stderr.isEmpty ? failureKey : r.stderr).prefix(300))
            )
        }
        return r
    }

    // MARK: - Helpers

    private func credentials(for server: SandboxServer, secret: String) -> SandboxRelayCredentials {
        SandboxRelayCredentials(
            host: server.host,
            port: server.port,
            username: server.username,
            authType: server.authType,
            secret: secret
        )
    }

    /// Parse one `docker ps --format '{{json .}}'` line (stable Docker CLI
    /// format templates — same as the old parseDockerPsLine).
    private static func parseDockerPsLine(_ line: Substring) -> SandboxEnvironment? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let data = trimmed.data(using: .utf8),
              let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = o["ID"] as? String,
              let name = o["Names"] as? String
        else { return nil }
        return SandboxEnvironment(
            id: id,
            name: name,
            status: o["State"] as? String ?? "unknown",
            image: o["Image"] as? String
        )
    }

    /// Shell-escape a single argument for safe inclusion in a remote command.
    private func shellEscape(_ arg: String) -> String {
        "'\(arg.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}
