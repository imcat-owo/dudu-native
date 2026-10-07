//
//  P7 PORT (2026-10-07): ported from OpenMinis NativeOffloads/AlarmOffload.h —
//  Minis->Dudu renames; Dudu-Swift.h for the generated interface.
//
//
//  AlarmOffload.h
//  Dudu
//
//  Native offload handler for `apple-alarm` — AlarmKit (iOS 26+).
//

#ifndef AlarmOffload_h
#define AlarmOffload_h

/// Register the apple-alarm native handler.
void alarm_offload_register(void);

#endif /* AlarmOffload_h */
