//
//  DuduSessionCleanupSeams.swift
//  Dudu
//
//  P6/P8 CLEANUP SEAMS (2026-10-07): no-op hooks for session-termination
//  calls owned by later parts. These are fire-and-forget calls issued when a
//  chat session is torn down (clearChat):
//
//    - ishSessionDidTerminate:      ISHExecutionCoordinator.shared.sessionDidTerminate (P8, Agent/ISH)
//    - browserReleasePool:          BrowserUseOffloadBridge.releasePool (P6, Agent/BrowserUse)
//    - browserDeletePersistedData:  BrowserTabPool.deletePersistedData (P6, Agent/BrowserUse)
//
//  Each defaults to a no-op so the chat core (P4) compiles and runs before
//  those parts land. P6/P8 assign the real implementations at startup
//  (e.g. in their assembly/bootstrap), after which these forward to the real
//  engines. Do NOT duplicate the engines here — assign, don't re-implement.

import Foundation

/// Session-teardown hooks owned by P6 (BrowserUse) / P8 (iSH). No-op until
/// the owning part assigns the real implementation.
enum DuduSessionCleanupSeams {
    /// P8: ISHExecutionCoordinator.shared.sessionDidTerminate(sessionId:)
    static var ishSessionDidTerminate: (String) async -> Void = { _ in }

    /// P6: BrowserUseOffloadBridge.releasePool(forSession:)
    static var browserReleasePool: (String) -> Void = { _ in }

    /// P6: BrowserTabPool.deletePersistedData(for:)
    static var browserDeletePersistedData: (String) -> Void = { _ in }
}
