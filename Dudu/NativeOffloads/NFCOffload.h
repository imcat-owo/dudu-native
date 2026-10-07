//
//  P7 PORT (2026-10-07): ported from OpenMinis NativeOffloads/NFCOffload.h —
//  Minis->Dudu renames; Dudu-Swift.h for the generated interface.
//
//
//  NFCOffload.h
//  Dudu
//
//  Native offload handler for `apple-nfc` — CoreNFC tag reading and writing.
//

#ifndef NFCOffload_h
#define NFCOffload_h

/// Register the apple-nfc native handler.
void nfc_offload_register(void);

#endif /* NFCOffload_h */
