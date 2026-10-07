//
//  Dudu-Bridging-Header.h
//  Dudu
//
//  Bridging header for importing C/ObjC code into Swift.
//
//  P1 (Shared foundation) imports only the ObjC helpers ported in
//  Dudu/Shared/. Later parts extend this file with their own headers
//  (P8: iSH kernel + offloads, etc.) using paths relative to Dudu/.

#ifndef Dudu_Bridging_Header_h
#define Dudu_Bridging_Header_h

// Safe KVC wrapper — @try/@catch for private WebKit preference keys.
#import "Shared/SafeKVCSetTrue.h"

// NSFileHandle write wrapper that catches NSException (avoids process abort
// when the reader thread hits a closed pipe / invalid fd / full disk).
#import "Shared/FileHandleSafeWrite.h"
#import "Shared/ObjCExceptionCatcher.h"

// Reentrancy guard for -[NSTextContainer setSize:] to prevent TextKit1
// fillLayoutHole storms (0x8BADF00D scene-update watchdog).
#import "Shared/NSTextContainerSetSizeGuard.h"

// CppJieba Chinese word segmentation (ObjC++ wrapper)
#import "Shared/JiebaWrapper.h"

// P7 (Diagnostics): async-signal-safe crash signal handler (pure Darwin,
// no P8 deps). CrashReporter.swift calls CrashSignalHandler.install().
#import "Diagnostics/CrashSignalHandler.h"
#import "Diagnostics/HangDetector.h"
#import "Diagnostics/AttributeQueryRecorder.h"

// P7 (Backup/Remote): rclone Go mobile entry points. The real library
// (deps/rclone-mobile xcframework) is NOT vendored; DuduRcloneStub.m
// provides stubs that return 503 until it is. Delete the stub when the
// real library lands.
void DuduRcloneInitialize(void);
char *_Nullable DuduRcloneRPC(const char *method, const char *input, int *status);
void DuduRcloneFreeString(char *s);

#endif /* Dudu_Bridging_Header_h */
