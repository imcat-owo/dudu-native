//
//  P7 PORT (2026-10-07): ported from OpenMinis NativeOffloads/BluetoothOffload.h —
//  Minis->Dudu renames; Dudu-Swift.h for the generated interface.
//
//
//  BluetoothOffload.h
//  Dudu
//
//  Native offload handler for `apple-bluetooth` — CoreBluetooth BLE operations.
//

#ifndef BluetoothOffload_h
#define BluetoothOffload_h

/// Register the apple-bluetooth native handler.
void bluetooth_offload_register(void);

#endif /* BluetoothOffload_h */
