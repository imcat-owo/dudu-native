//
//  P7 PORT (2026-10-07): ported from OpenMinis NativeOffloads/SpeakOffload.h —
//  Minis->Dudu renames; Dudu-Swift.h for the generated interface.
//
//
//  SpeakOffload.h
//  Dudu
//
//  Native offload handler for `apple-speak` — AVSpeechSynthesizer.
//

#ifndef SpeakOffload_h
#define SpeakOffload_h

/// Register the apple-speak native handler.
void speak_offload_register(void);

#endif /* SpeakOffload_h */
