import Foundation

// MARK: - D25 · SandboxRelayTransport
//
// Swift port of openmuse/apps/mobile/src/sandbox/transport-relay.ts
// (RelaySshTransport) — the REAL path Backend A uses to reach her server.
//
// Why a relay: iOS has no production SSH client the app can bundle, so the
// app talks HTTPS to the dudu sandbox relay (sandbox-relay/relay.mjs) that
// SHE installs on her server; the relay opens the REAL SSH session (real
// handshake, real key/password auth via the system ssh client) and streams
// real output back. Nothing is simulated: every byte of stdout/stderr and
// every exit code is the genuine result of the remote command.
//
// URL: https://{host}/dudu-sandbox — her Caddy on 443 terminates TLS and
// reverse-proxies to the relay on 127.0.0.1:18731 (see relay-install copy
// in SandboxSettingsView).
//
// Security (same as the old transport): the SSH credentials ARE the auth.
// They travel only in POST bodies over TLS, never in URLs, never in logs.
// The secret is passed per-call from the Keychain and never retained here.

private let relayLogger = AppLogger(category: "SandboxRelay")

/// Connection material for one relay call. `secret` is the private key PEM
/// (authType .key) or the password (authType .password).
struct SandboxRelayCredentials {
    let host: String
    let port: Int
    let username: String
    let authType: SandboxAuthType
    let secret: String
}

struct SandboxRelayResult {
    let stdout: String
    let stderr: String
    let exitCode: Int
    let durationMs: Int
}

enum SandboxRelayError: Error, LocalizedError {
    /// No usable network path to the relay (DNS / TLS / connection refused /
    /// timeout). UI pairs this with the plain-language relay-missing note.
    case unreachable(String)
    /// The relay answered but refused / failed the request.
    case requestFailed(String)
    /// The relay ran the SSH probe and it failed (bad creds, SSH refused…).
    case probeFailed(String)
    /// Host failed the allowlist (plain hostname / IPv4 / IPv6 literal only
    /// — no scheme, port, or path).
    case badHost

    var errorDescription: String? {
        switch self {
        case .unreachable(let d): return "sandbox.relay.unreachable: \(d)"
        case .requestFailed(let d): return "sandbox.relay.requestFailed: \(d)"
        case .probeFailed(let d): return "sandbox.relay.probeFailed: \(d)"
        case .badHost: return "sandbox.relay.badHost"
        }
    }

    /// True when the UI should show the "relay not installed yet" install steps.
    var isUnreachable: Bool {
        if case .unreachable = self { return true }
        return false
    }
}

/// URLSession-based relay client. Stateless: every call takes explicit
/// credentials; nothing secret is retained between calls.
enum SandboxRelayTransport {
    private static let relayPath = "/dudu-sandbox"
    private static let probeTimeout: TimeInterval = 15
    private static let execTimeout: TimeInterval = 120

    private static func baseURL(for host: String) throws -> URL {
        // Host allowlist: plain hostname / IPv4 / IPv6 literal — no scheme,
        // port, or path. The relay is always reached via
        // https://{host}/dudu-sandbox (Caddy, 443). IPv6 literals are
        // bracketed for the URL; the relay's SSH side receives the raw
        // host string, which SSH accepts as-is. A colon-bearing host that
        // is not a valid IPv6 literal fails URL parsing and throws badHost
        // with a localized message — never a silent misconnect.
        let ok = host.range(
            of: "^[A-Za-z0-9.:-]{1,253}$",
            options: .regularExpression
        ) != nil
        guard ok else {
            throw SandboxRelayError.badHost
        }
        let urlHost = host.contains(":") ? "[\(host)]" : host
        guard let url = URL(string: "https://\(urlHost)\(relayPath)") else {
            throw SandboxRelayError.badHost
        }
        return url
    }

    private static func post(
        _ base: URL,
        path: String,
        body: [String: Any],
        timeout: TimeInterval
    ) async throws -> [String: Any] {
        var request = URLRequest(url: base.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.timeoutInterval = timeout
        // The body carries the SSH secret — serialized to the wire only, never logged.
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw SandboxRelayError.unreachable(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw SandboxRelayError.unreachable("no http response")
        }
        guard http.statusCode == 200 else {
            throw SandboxRelayError.requestFailed(relayErrorText(data, status: http.statusCode))
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SandboxRelayError.requestFailed("bad json")
        }
        return json
    }

    /// Extract a relay error string without ever touching secrets.
    private static func relayErrorText(_ data: Data, status: Int) -> String {
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let e = json["error"] as? String
        {
            return String(e.prefix(300))
        }
        return "http \(status)"
    }

    private static func execRaw(
        _ creds: SandboxRelayCredentials,
        command: String,
        timeout: TimeInterval
    ) async throws -> SandboxRelayResult {
        let base = try baseURL(for: creds.host)
        var body: [String: Any] = [
            "host": creds.host,
            "port": creds.port,
            "username": creds.username,
            "authType": creds.authType.rawValue,
            "command": command,
            "timeoutMs": Int(timeout * 1000),
        ]
        switch creds.authType {
        case .key: body["privateKey"] = creds.secret
        case .password: body["password"] = creds.secret
        }
        // Log host only — the body holds the secret and is never logged.
        relayLogger.info("relay exec host=\(creds.host) commandLen=\(command.count)")
        let json = try await post(base, path: "exec", body: body, timeout: timeout + 10)
        return SandboxRelayResult(
            stdout: json["stdout"] as? String ?? "",
            stderr: json["stderr"] as? String ?? "",
            exitCode: json["exitCode"] as? Int ?? -1,
            durationMs: json["durationMs"] as? Int ?? 0
        )
    }

    /// The REAL connection test: the relay must open a genuine SSH session
    /// and run `true`. exitCode 0 = the credentials and the path both work.
    /// Anything else throws — the UI reports it honestly.
    static func probe(_ creds: SandboxRelayCredentials) async throws {
        let r = try await execRaw(creds, command: "true", timeout: probeTimeout)
        guard r.exitCode == 0 else {
            throw SandboxRelayError.probeFailed(
                String((r.stderr.isEmpty ? "ssh probe failed" : r.stderr).prefix(300))
            )
        }
    }

    static func exec(
        _ creds: SandboxRelayCredentials,
        command: String,
        timeout: TimeInterval = execTimeout
    ) async throws -> SandboxRelayResult {
        try await execRaw(creds, command: command, timeout: timeout)
    }
}
