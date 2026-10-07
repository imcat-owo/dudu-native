import Foundation

// MARK: - D23 · computer terminal backend contract
//
// BACKEND PENDING: computer container engine (P8 track).
//
// The old RN app talked to a Docker Linux container over its API
// (openmuse/docs/COMPUTER.md: /api/computer — start/stop, bounded commands,
// /workspace file ops). In the native app the container is the iSH sandbox,
// whose coordinator is P8's track (Agent/ISH) and is NOT ported yet.
//
// This file is the clearly-defined protocol the terminal UI is genuinely
// wired to — not an invented backend. ISHComputerBackend is the real adapter
// over DuduISHSeams (Agent/Chat/DuduISHSeams.swift): every seam is nil
// pre-P8, so the adapter throws DuduKernelBootError.sandboxUnavailable —
// honest, never simulated. The moment P8 assigns the seams at startup, this
// UI lights up with zero changes here.

/// Lifecycle state of the computer backend, mirroring the old app's
/// ComputerSnapshot.status vocabulary (running / stopped) plus an honest
/// pending state for pre-P8 builds.
enum ComputerBackendStatus: Equatable {
    /// iSH sandbox not available in this build (all DuduISHSeams are nil).
    case pending
    /// Seams assigned, kernel not booted.
    case stopped
    /// Kernel booted, commands can run.
    case running
}

/// One command launched from the terminal UI — the native equivalent of the
/// old app's ComputerCommand domain type (command, cwd, status, stdout/stderr,
/// exit code, startedAt). Kept in-memory for the session; the agent's own
/// shell runs are recorded separately in ShellCommandRingBuffer.
struct ComputerCommandRecord: Identifiable {
    enum RunStatus: Equatable {
        case running
        case succeeded
        case failed
    }

    let id: UUID
    let command: String
    var status: RunStatus
    /// Combined stdout+stderr (the seam surfaces one output channel).
    var output: String
    var exitCode: Int?
    var truncated: Bool
    let startedAt: Date

    init(command: String) {
        self.id = UUID()
        self.command = command
        self.status = .running
        self.output = ""
        self.exitCode = nil
        self.truncated = false
        self.startedAt = Date()
    }
}

/// The contract the terminal UI programs against. Implemented once, by
/// ISHComputerBackend below; P8's arrival is a seam assignment, not a UI
/// change.
protocol ComputerBackend {
    /// True when a real execution seam is assigned (post-P8).
    var isAvailable: Bool { get }
    func currentStatus() -> ComputerBackendStatus
    /// Runs one bounded, non-interactive command (same contract as the old
    /// app: no PTY, no full-screen apps). Lines stream via onLine; the return
    /// carries the full output plus exit code.
    func runCommand(
        command: String,
        timeout: TimeInterval,
        onLine: @escaping (String) -> Void
    ) async throws -> (output: String, exitCode: Int)
    func start() async throws
    func stop()
}

/// BACKEND PENDING: real adapter over DuduISHSeams; every path degrades to
/// DuduKernelBootError.sandboxUnavailable while the seams are nil (pre-P8).
struct ISHComputerBackend: ComputerBackend {
    /// Session id the interactive terminal uses. Deliberately distinct from
    /// chat session ids so the terminal's guest working state never collides
    /// with the agent's.
    static let terminalSessionId = "computer-terminal"

    var isAvailable: Bool { DuduISHSeams.execute != nil }

    func currentStatus() -> ComputerBackendStatus {
        // Nil seam = P8 not landed = backend pending (honest, not "error").
        guard let isBooted = DuduISHSeams.isKernelBooted else { return .pending }
        return isBooted() ? .running : .stopped
    }

    func runCommand(
        command: String,
        timeout: TimeInterval,
        onLine: @escaping (String) -> Void
    ) async throws -> (output: String, exitCode: Int) {
        guard let execute = DuduISHSeams.execute else {
            throw DuduKernelBootError.sandboxUnavailable
        }
        return try await execute(
            Self.terminalSessionId, command, timeout, onLine, { _ in }
        )
    }

    func start() async throws {
        guard let bootKernel = DuduISHSeams.bootKernel else {
            throw DuduKernelBootError.sandboxUnavailable
        }
        try await bootKernel()
    }

    func stop() {
        // Nil pre-P8 is a no-op (0 killed); post-P8 stops the terminal session.
        _ = DuduISHSeams.stopAllNonisolated?(nil)
    }
}
