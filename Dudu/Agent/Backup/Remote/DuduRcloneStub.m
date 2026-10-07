//
//  DuduRcloneStub.m
//  Dudu
//
//  P7 PORT (2026-10-07): stub implementations of the rclone Go mobile
//  library entry points (`DuduRcloneInitialize`, `DuduRcloneRPC`,
//  `DuduRcloneFreeString`).
//
//  The real implementations live in OpenMinis' `deps/rclone-mobile`
//  (Go mobile xcframework) — NOT vendored in dudu-native. These stubs let
//  Agent/Backup/Remote compile and link; at runtime every RPC returns
//  HTTP 503 with a JSON error naming the missing library, which
//  RcloneBridge surfaces as RPCError. Local backup destinations are
//  unaffected.
//
//  When the Go xcframework is vendored (P8+), DELETE this file and link
//  the real library instead.

#import <Foundation/Foundation.h>
#import <stdlib.h>
#import <string.h>

void DuduRcloneInitialize(void) {
    // No-op: nothing to initialise without the Go runtime.
}

char *_Nullable DuduRcloneRPC(const char *method, const char *input, int *status) {
    (void)input;
    if (status) *status = 503;
    const char *msg = "{\"error\":\"rclone library not bundled (deps/rclone-mobile not vendored)\"}";
    // Caller frees with DuduRcloneFreeString.
    char *out = malloc(strlen(msg) + 1);
    if (out) strcpy(out, msg);
    return out;
}

void DuduRcloneFreeString(char *s) {
    free(s);
}
