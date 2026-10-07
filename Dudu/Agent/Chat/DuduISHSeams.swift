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
}
