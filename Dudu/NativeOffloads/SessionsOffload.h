//
//  P7 PORT (2026-10-07): ported from OpenMinis NativeOffloads/SessionsOffload.h —
//  Minis->Dudu renames; Dudu-Swift.h for the generated interface.
//
//
//  SessionsOffload.h
//  Dudu
//
//  Native offload handler for `dudu-sessions-cli` — query chat sessions and messages.
//

#ifndef SessionsOffload_h
#define SessionsOffload_h

/// Register the dudu-sessions-cli native handler.
void sessions_offload_register(void);

#endif /* SessionsOffload_h */
