//
//  P7 PORT (2026-10-07): ported from OpenMinis NativeOffloads/RemindersOffload.h —
//  Minis->Dudu renames; Dudu-Swift.h for the generated interface.
//
//
//  RemindersOffload.h
//  Dudu
//
//  Native offload handler for `apple-reminders` — EventKit reminders.
//

#ifndef RemindersOffload_h
#define RemindersOffload_h

/// Register the apple-reminders native handler.
void reminders_offload_register(void);

#endif /* RemindersOffload_h */
