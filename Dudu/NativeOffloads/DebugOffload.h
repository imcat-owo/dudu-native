//
//  P7 PORT (2026-10-07): ported from OpenMinis NativeOffloads/DebugOffload.h —
//  Minis->Dudu renames; Dudu-Swift.h for the generated interface.
//
//
//  DebugOffload.h
//  Dudu
//
//  Native offload handler for `dudu-debug`. RPC-backed subcommands are
//  Debug-build-only (they route through DebugLocalDispatch, compiled out in
//  Release). The `logs` subcommand reads the app's own runtime log in-process
//  and is available in ALL builds (T-ios-dudu-debug-logs-oslogstore), so the
//  handler is registered unconditionally.
//

#ifndef DebugOffload_h
#define DebugOffload_h

/// Register the dudu-debug native handler. Registered in every build so the
/// Release-safe `logs` subcommand is reachable; RPC subcommands self-report as
/// DEBUG-only at dispatch time.
void debug_offload_register(void);

#endif /* DebugOffload_h */
