//
//  P7 PORT (2026-10-07): ported from OpenMinis NativeOffloads/PlayerOffload.h —
//  Minis->Dudu renames; Dudu-Swift.h for the generated interface.
//
//
//  PlayerOffload.h
//  Dudu
//
//  Native offload handler for `apple-player` — AVPlayer media playback.
//

#ifndef PlayerOffload_h
#define PlayerOffload_h

/// Register the apple-player native handler.
void player_offload_register(void);

#endif /* PlayerOffload_h */
