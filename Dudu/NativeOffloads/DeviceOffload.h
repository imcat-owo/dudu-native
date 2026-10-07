//
//  P7 PORT (2026-10-07): ported from OpenMinis NativeOffloads/DeviceOffload.h —
//  Minis->Dudu renames; Dudu-Swift.h for the generated interface.
//
//
//  DeviceOffload.h
//  Dudu
//
//  Native offload handler for `apple-device` — UIDevice + ProcessInfo.
//

#ifndef DeviceOffload_h
#define DeviceOffload_h

/// Register the apple-device native handler.
void device_offload_register(void);

#endif /* DeviceOffload_h */
