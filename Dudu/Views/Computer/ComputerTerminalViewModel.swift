import Combine
import Foundation

// MARK: - D23 · computer terminal view model
//
// Drives ComputerTerminalView against the ComputerBackend protocol —
// genuinely wired, no simulated output. Pre-P8 every backend call throws
// DuduKernelBootError.sandboxUnavailable and the UI surfaces that honestly.
//
// Two history sources (both real):
//   1. `records` — commands launched from this terminal, in-memory, with
//      streamed output (the old app's command receipts).
//   2. `agentHistory` — ShellCommandRingBuffer.syncSnapshot: the shell
//      commands the agent itself ran (the old COMPUTER.md promise: "inspect
//      what the agent ran").

@MainActor
final class ComputerTerminalViewModel: ObservableObject {
    /// Display cap for one command's output (old app had a truncated note).
    private static let maxOutputChars = 64_000
    /// Matches the old app's 5s status poll while the view is visible.
    private static let pollInterval: TimeInterval = 5
    private static let commandTimeout: TimeInterval = 120

    @Published private(set) var status: ComputerBackendStatus = .pending
    @Published private(set) var records: [ComputerCommandRecord] = []
    @Published private(set) var agentHistory: [ShellCommandEntry] = []
    @Published private(set) var commandRunning = false
    @Published private(set) var busy = false
    @Published private(set) var errorMessage: String?
    @Published var commandText = ""

    private let backend: ComputerBackend
    private var pollTimer: Timer?

    init(backend: ComputerBackend = ISHComputerBackend()) {
        self.backend = backend
        refresh()
    }

    // MARK: - Lifecycle

    func startPolling() {
        stopPolling()
        pollTimer = Timer.scheduledTimer(withTimeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }
    }

    func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    func refresh() {
        status = backend.currentStatus()
        agentHistory = ShellCommandRingBuffer.syncSnapshot
            .sorted { $0.startedAt > $1.startedAt }
    }

    // MARK: - Computer control (old app's Start/Stop computer)

    func startComputer() {
        guard !busy else { return }
        busy = true
        errorMessage = nil
        Task {
            do {
                try await backend.start()
            } catch {
                errorMessage = Self.describe(error)
            }
            busy = false
            refresh()
        }
    }

    func stopComputer() {
        backend.stop()
        refresh()
    }

    func clearError() {
        errorMessage = nil
    }

    // MARK: - Run a command

    var canRun: Bool {
        status == .running && !commandRunning && !busy
            && !commandText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func run() {
        let command = commandText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty, !commandRunning else { return }
        errorMessage = nil
        commandRunning = true
        commandText = ""

        let record = ComputerCommandRecord(command: command)
        records.insert(record, at: 0)
        let recordId = record.id

        Task {
            // Real bookkeeping: the terminal's runs join the same ring buffer
            // the agent's shell runs land in (visible in agent history).
            let ringIndex = await ShellCommandRingBuffer.shared.didStart(
                command: command, sessionId: ISHComputerBackend.terminalSessionId
            )
            do {
                let result = try await backend.runCommand(
                    command: command,
                    timeout: Self.commandTimeout
                ) { [weak self] line in
                    // lineCallback may fire off the main actor — hop back.
                    Task { @MainActor [weak self] in
                        self?.appendOutput(recordId: recordId, line: line)
                    }
                }
                await ShellCommandRingBuffer.shared.didExit(index: ringIndex, exitCode: result.exitCode)
                update(recordId: recordId) { r in
                    r.status = result.exitCode == 0 ? .succeeded : .failed
                    r.exitCode = result.exitCode
                    if !result.output.isEmpty { r.output = Self.capped(result.output, truncated: &r.truncated) }
                }
            } catch {
                await ShellCommandRingBuffer.shared.didAbort(index: ringIndex)
                let message = Self.describe(error)
                update(recordId: recordId) { r in
                    r.status = .failed
                    r.output = message
                }
                errorMessage = message
            }
            commandRunning = false
            refresh()
        }
    }

    // MARK: - Helpers

    private func appendOutput(recordId: UUID, line: String) {
        update(recordId: recordId) { r in
            guard !r.truncated else { return }
            r.output = Self.capped(r.output + line + "\n", truncated: &r.truncated)
        }
    }

    private func update(recordId: UUID, _ mutate: (inout ComputerCommandRecord) -> Void) {
        guard let i = records.firstIndex(where: { $0.id == recordId }) else { return }
        mutate(&records[i])
    }

    private static func capped(_ text: String, truncated: inout Bool) -> String {
        guard text.count > maxOutputChars else { return text }
        truncated = true
        return String(text.prefix(maxOutputChars))
    }

    /// Honest error text: the sandbox-unavailable case keeps its dedicated
    /// localized description; anything else surfaces verbatim (never a
    /// generic "something went wrong").
    private static func describe(_ error: Error) -> String {
        if let local = error as? LocalizedError, let d = local.errorDescription { return d }
        return error.localizedDescription
    }
}
