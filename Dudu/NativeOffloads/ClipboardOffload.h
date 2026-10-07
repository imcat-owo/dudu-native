//
//  P7 PORT (2026-10-07): ported from OpenMinis NativeOffloads/ClipboardOffload.h —
//  Minis->Dudu renames; Dudu-Swift.h for the generated interface.
//
//
//  ClipboardOffload.h
//  Dudu
//
//  Native offload handler for `apple-clipboard` — read/write UIPasteboard.
//

#ifndef ClipboardOffload_h
#define ClipboardOffload_h

/// Register the apple-clipboard native handler.
void clipboard_offload_register(void);

#endif /* ClipboardOffload_h */
