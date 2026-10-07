//
//  P7 PORT (2026-10-07): ported from OpenMinis NativeOffloads/ConfigOffload.h —
//  Minis->Dudu renames; Dudu-Swift.h for the generated interface.
//
//
//  ConfigOffload.h
//  Dudu
//
//  Native offload handler for `dudu-config` — read and change app
//  settings via the ConfigRegistry.
//

#ifndef ConfigOffload_h
#define ConfigOffload_h

/// Register the dudu-config native handler.
void config_offload_register(void);

#endif /* ConfigOffload_h */
