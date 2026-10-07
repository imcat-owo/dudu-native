//
//  DuduISHSeams.swift
//  Dudu
//
//  P6 ISH EXECUTION SEAMS (2026-10-07): nil-able hooks for the five
//  ISHExecutionCoordinator APIs that P4's chat core calls. The real
//  coordinator is an actor in Agent/ISH (P8); until P8 lands, these stay nil
//  and every call site degrades to its documented fallback (see each site).
//
//  Signatures mirror the real ones, read from
//  OpenMinis Agent/ISH/ISHExecutionCoordinator.swift:
//    - execute:              func execute(sessionId:command:timeout:lineCallback:pidCallback:) async throws -> ISHCommandResult
//    - ensureMounted:        func ensureMounted(for:)            (SYNC upstream; seam is async so P8 can wrap it)
//    - debugMountSnapshot:   #if DEBUG func debugMountSnapshot() -> (sessionId:paths:)
//    - hostURL:               func hostURL(for:sessionId:) -> URL? (SYNC upstream; seam is async so P8 can wrap it)
//    - stopAllNonisolated:   nonisolated static func stopAllNonisolated(sessionId:) -> Int
//
//  SYNC->ASYNC ADAPTATION (documented, intentional): ensureMounted and hostURL
//  are synchronous in the real coordinator, but the P4 call sites await them
//  (they were async in the chat-core context). The seam exposes them as async
//  closures; P8 assigns `{ await-ish wrapper }` around the sync implementation.
//
//  DEVIATION (documented, unavoidable): execute's real return type is
//  ISHCommandResult, a P8 struct that does not exist in this target yet, so the
//  seam returns an anonymous tuple carrying the struct's EXACT two fields
//  (output: String, exitCode: Int) — every field both P4 call sites consume is
//  preserved (an Int-only seam would have deleted `output`). P8 assigns the
//  real implementation and maps field-for-field. Parameter list and
//  async/throws shape match exactly for execute; see SYNC->ASYNC ADAPTATION
//  above for ensureMounted/hostURL.
//
//  P8 assigns the real implementations at startup; until then the call sites
//  below treat nil as "iSH unavailable". Do NOT re-implement the coordinator
//  here — assign, don't duplicate.

import Foundation

/// iSH execution hooks owned by P8 (Agent/ISH). Nil until P8 assigns the real
/// ISHExecutionCoordinator-backed implementations.
enum DuduISHSeams {
    /// P8: ISHExecutionCoordinator.shared.execute(sessionId:command:timeout:lineCallback:pidCallback:)
    /// Returns (output, exitCode) — the full ISHCommandResult surface (see DEVIATION above).
    /// Parameter order: sessionId, command, timeout, lineCallback, pidCallback.
    static var execute: ((
        String,
        String,
        TimeInterval?,
        @escaping (String) -> Void,
        @escaping (Int32) -> Void
    ) async throws -> (output: String, exitCode: Int))? = nil

    /// P8: ISHExecutionCoordinator.shared.ensureMounted(for:)
    static var ensureMounted: ((String) async -> Void)? = nil

    #if DEBUG
    /// P8: ISHExecutionCoordinator.shared.debugMountSnapshot() — DEBUG-only upstream.
    static var debugMountSnapshot: (() async -> (sessionId: String?, paths: [String: URL]))? = nil
    #endif

    /// P8: ISHExecutionCoordinator.shared.hostURL(for:sessionId:)
    /// Parameter order: linuxPath, sessionId.
    static var hostURL: ((String, String?) async -> URL?)? = nil

    /// P8: ISHExecutionCoordinator.stopAllNonisolated(sessionId:)
    static var stopAllNonisolated: ((String?) -> Int)? = nil

    // MARK: - P7 additions (2026-10-07)
    //
    //  Hooks for the P8 APIs that P7's ported files (NativeOffloads bridges,
    //  Sync/SessionFileChangeTracker, Agent/BrowserUse) call. Same contract as
    //  above: nil until P8 assigns the real implementations; every call site
    //  degrades to its documented fallback. P8 assigns these at startup.
    //
    //  Signatures mirror the real ones, read from
    //  OpenMinis Agent/ISH/ISHExecutionCoordinator.swift,
    //  Agent/ISH/MinisFsRouter.swift, and the iSH kernel fakefs handler:
    //    - mountedSessionIdSnapshot: nonisolated static var on
    //      ISHExecutionCoordinator (SYNC upstream — read without hopping to the
    //      coordinator actor, deliberately, to avoid deadlocks under shell
    //      pressure; see BrowserUseOffloadBridge).
    //    - isKernelBooted:          ISHKernel.shared.isBooted (SYNC Bool).
    //    - rootfsDataPath:          RootfsManager.shared.dataPath (SYNC URL).
    //    - installFakefsChangeHandler: ISHKernel.installFakefsChangeHandler —
    //      installs the fakefs write/unlink/rename callback. The event struct
    //      carries exactly the four fields SessionFileChangeTracker consumes
    //      (fsContext, linuxPath, op, timestampNs); P8 maps its kernel event
    //      type field-for-field when assigning.
    //    - fsRouterSid:             MinisFsRouter.shared.sid(for:) — maps a
    //      fakefs fs_context back to the owning session id.

    /// P8: ISHExecutionCoordinator.mountedSessionIdSnapshot (nonisolated, sync).
    static var mountedSessionIdSnapshot: (() -> String?)? = nil

    /// P8: ISHKernel.shared.isBooted (sync Bool).
    static var isKernelBooted: (() -> Bool)? = nil

    /// P8: RootfsManager.shared.dataPath (sync URL).
    static var rootfsDataPath: (() -> URL?)? = nil

    /// P8: ISHKernel.installFakefsChangeHandler — see DuduFakefsChangeEvent.
    static var installFakefsChangeHandler: ((@escaping ([DuduFakefsChangeEvent]) -> Void) -> Void)? = nil

    // MARK: - P8 external mounts (MountedFolderManager)

    /// P8: a mount spec for the iSH guest. Mirrors
    /// ISHExecutionCoordinator.ExternalMountSpec (P8).
    struct DuduExternalMountSpec {
        let linuxDir: String
        let hostPath: String
        let readOnly: Bool
    }

    /// P8 (not yet): push external mount snapshot to the iSH coordinator.
    /// Until then nil (no-op).
    static var setExternalMountSnapshot: (([DuduExternalMountSpec]) -> Void)?

    /// P8 (not yet): ask the iSH coordinator to reconcile mounts.
    /// Until then nil (no-op).
    static var applyExternalMountSnapshot: (() async -> Void)?

    /// P8: MinisFsRouter.shared.sid(for:) — fs_context -> owning session id.
    static var fsRouterSid: ((UInt64) -> String?)? = nil

    /// P8: RootfsManager.shared.rootfsPath (sync URL; dataPath = rootfsPath/data).
    static var rootfsPath: (() -> URL?)? = nil

    /// P8: RootfsManager.shared.removeFakefsPath(_:) — best-effort fakefs
    /// meta.db cleanup. Nil skips it (canonical state is the Library copy).
    static var removeFakefsPath: ((String) -> Void)? = nil

    /// P8: ISHExecutionCoordinator.shared.mountForSession(_:) — bind-mounts a
    /// session's dudu directories into iSH-visible /var/dudu/.
    static var mountForSession: ((String) async -> Void)? = nil

    /// P8: ISHKernel.shared.refreshDns() — rewrites the guest resolv.conf.
    /// Nil skips it (pre-P8 there is no guest network stack to refresh).
    static var refreshDns: (() -> Void)? = nil

    /// P8: ISHKernel.shared.beginBackgroundCPUGovernor() — clamps the iSH
    /// guest CPU when the app backgrounds. Nil skips it (pre-P8 there is no
    /// guest CPU to govern). Begin is idempotent upstream.
    static var beginBackgroundCPUGovernor: (() -> Void)? = nil

    /// P8: ISHKernel.shared.endBackgroundCPUGovernor() — releases the clamp
    /// on foreground return. Nil skips it.
    static var endBackgroundCPUGovernor: (() -> Void)? = nil

    /// P8: the full iSH kernel boot sequence — RootfsManager.installIfNeeded,
    /// ISHKernel.boot(withRootPath:), installSessionFileChangeTracker,
    /// DuduFsRouter.installHook, applyDefaultMountOverlay, and the mirror
    /// speed auto-detect. Nil pre-P8; callers must surface the unavailability
    /// honestly (see DuduKernelBootError) instead of hanging on .booting.
    static var bootKernel: (() async throws -> Void)? = nil
}

/// P7 (2026-10-07): thrown when code needs the iSH sandbox before P8 lands.
enum DuduKernelBootError: Error, LocalizedError {
    case sandboxUnavailable
    var errorDescription: String? {
        switch self {
        case .sandboxUnavailable:
            return "Sandbox (iSH) is not available in this build yet."
        }
    }
}

/// P7 (2026-10-07): minimal fakefs change event for the
/// `DuduISHSeams.installFakefsChangeHandler` seam. Carries exactly the fields
/// `SessionFileChangeTracker` consumes; P8 maps the real kernel event type
/// onto this struct field-for-field when assigning the seam.
struct DuduFakefsChangeEvent {
    var fsContext: UInt64
    var linuxPath: String
    var op: Int32
    var timestampNs: Int64
}
