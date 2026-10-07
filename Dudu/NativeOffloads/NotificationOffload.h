//
//  P7 PORT (2026-10-07): ported from OpenMinis NativeOffloads/NotificationOffload.h —
//  Minis->Dudu renames; Dudu-Swift.h for the generated interface.
//
//
//  NotificationOffload.h
//  Dudu
//
//  Native offload handler for `apple-notification` — UNUserNotificationCenter.
//

#ifndef NotificationOffload_h
#define NotificationOffload_h

/// Register the apple-notification native handler.
void notification_offload_register(void);

#endif /* NotificationOffload_h */
