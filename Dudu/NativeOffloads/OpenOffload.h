//
//  P7 PORT (2026-10-07): ported from OpenMinis NativeOffloads/OpenOffload.h —
//  Minis->Dudu renames; Dudu-Swift.h for the generated interface.
//
//
//  OpenOffload.h
//  Dudu
//
//  Native offload handler for `apple-open` — open URLs via UIApplication.
//

#ifndef OpenOffload_h
#define OpenOffload_h

/// Register the apple-open native handler.
void open_offload_register(void);

#endif /* OpenOffload_h */
