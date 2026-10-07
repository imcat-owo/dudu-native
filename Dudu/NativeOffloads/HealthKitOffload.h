//
//  P7 PORT (2026-10-07): ported from OpenMinis NativeOffloads/HealthKitOffload.h —
//  Minis->Dudu renames; Dudu-Swift.h for the generated interface.
//
//
//  HealthKitOffload.h
//  Dudu
//
//  Native offload handler for `apple-healthkit` — HealthKit queries.
//

#ifndef HealthKitOffload_h
#define HealthKitOffload_h

/// Register the apple-healthkit native handler.
void healthkit_offload_register(void);

#endif /* HealthKitOffload_h */
