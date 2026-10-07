//
//  P7 PORT (2026-10-07): ported from OpenMinis NativeOffloads/VisionOffload.h —
//  Minis->Dudu renames; Dudu-Swift.h for the generated interface.
//
//
//  VisionOffload.h
//  Dudu
//
//  Native offload handler for `apple-vision` — Vision framework.
//

#ifndef VisionOffload_h
#define VisionOffload_h

/// Register the apple-vision native handler.
void vision_offload_register(void);

#endif /* VisionOffload_h */
