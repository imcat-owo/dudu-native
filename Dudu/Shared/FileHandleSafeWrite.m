//
//  FileHandleSafeWrite.m
//  DuduApp
//

#import "FileHandleSafeWrite.h"

BOOL DuduFileHandleSafeWrite(NSFileHandle *handle, NSData *data, NSString *_Nullable *_Nullable errorMessage) {
    if (!handle || !data) {
        if (errorMessage) { *errorMessage = @"handle or data is nil"; }
        return NO;
    }
    @try {
        [handle writeData:data];
        return YES;
    } @catch (NSException *ex) {
        if (errorMessage) {
            *errorMessage = [NSString stringWithFormat:@"%@: %@", ex.name, ex.reason ?: @"(no reason)"];
        }
        return NO;
    }
}
