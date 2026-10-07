//
//  P7 PORT (2026-10-07): ported from OpenMinis NativeOffloads/LocationOffload.h —
//  Minis->Dudu renames; Dudu-Swift.h for the generated interface.
//
//
//  LocationOffload.h
//  Dudu
//
//  Native offload handler for `apple-location` — CoreLocation.
//

#ifndef LocationOffload_h
#define LocationOffload_h

/// Register the apple-location native handler.
void location_offload_register(void);

#endif /* LocationOffload_h */
