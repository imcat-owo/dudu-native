import Foundation

// MARK: - D25 · SandboxLocalBackend
//
// Backend B: local Linux via in-app iSH (OpenMinis's approach).
//
// HONEST DEFERRED SEAM — DO NOT TOUCH P8 HERE.
//
// The real iSH kernel + rootfs + ISHExecutionCoordinator live on the P8
// track (separate workstream; DuduISHSeams.swift owns the hooks). Until P8
// lands, this backend reports `.unavailable` with the plain-language
// `sandbox.local.nativeRequired` detail — exactly like the old
// IshSandboxBackend did when the native module wasn't bundled. No fake
// Linux, no fake command results, no fake "connected".
//
// P8 wiring point: when ISHExecutionCoordinator exists, replace this class's
// internals (or swap the instance in SandboxManager) with the real adapter
// against DuduISHSeams — the state machine and the UI contract stay the same.

@MainActor
final class SandboxLocalBackend: ObservableObject {
    @Published private(set) var state: SandboxConnectionState = .unavailable
    @Published private(set) var detail: String? = "sandbox.local.nativeRequired"

    /// Always refuses: the native iSH module is not bundled in this build.
    func connect() async throws {
        state = .unavailable
        detail = "sandbox.local.nativeRequired"
        throw SandboxLocalError.unavailable
    }

    func disconnect() {
        state = .unavailable
        detail = "sandbox.local.nativeRequired"
    }

    /// Re-detect availability. Still unavailable until P8 assigns the real
    /// iSH implementation — never flips to disconnected/connected on its own.
    func reset() {
        // P8: consult DuduISHSeams.isKernelBooted here and set state to
        // .disconnected when the kernel is actually present.
        state = .unavailable
        detail = "sandbox.local.nativeRequired"
    }
}

enum SandboxLocalError: Error, LocalizedError {
    case unavailable

    var errorDescription: String? { "sandbox.local.nativeRequired" }
}
