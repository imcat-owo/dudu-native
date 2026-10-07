//
//  P7 PORT (2026-10-07): ported from OpenMinis NativeOffloads/SpeechOffload.h —
//  Minis->Dudu renames; Dudu-Swift.h for the generated interface.
//
//
//  SpeechOffload.h
//  Dudu
//
//  Native offload handler for `apple-speech` — SFSpeechRecognizer.
//

#ifndef SpeechOffload_h
#define SpeechOffload_h

/// Register the apple-speech native handler.
void speech_offload_register(void);

#endif /* SpeechOffload_h */
