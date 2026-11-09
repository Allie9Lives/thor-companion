# Thor monitoring feasibility — November 4, 2026

## Observed through authorized USB debugging

- Device: AYN Thor; Android 13, API 33.
- Build: Thor_V1.0.0.377_20260206_165408_user.
- RAM: MemTotal 15,621,188 kB, consistent with a marketed 16 GB device.
- Internal storage: Samsung KLUGGARHHD-B0G1; approximately 1 TB raw storage. The data filesystem reports approximately 942 GiB total, 221 GiB used, 721 GiB available (rounded by Android df).
- UFS specification_version: 0x0400, identifying UFS 4.0 directly from the device descriptor.
- Configuration is consistent with Thor Max (16 GB / 1 TB); firmware model string itself only says AYN Thor.
- Battery snapshot: 56%, charging, 29.0 °C, approximately 3.964 V. These values change over time.
- Additional battery sysfs readings available to the ADB shell: current, charge counter, full/design charge, cycle count, health. Accuracy and access from a normal app remain unverified. Both full/design capacity reported 5,938,000 µAh; cycle count reported zero. These alone do not establish battery wear or health accuracy.
- Firmware settings include percent_80_charge_limit=0 and fan settings. No settings were changed; write access or functionality from an ordinary app has not been established.
- Bluetooth and Bluetooth LE declared as hardware features. Bluetooth was ON. BLE advertising/peripheral functionality has not been tested.

## Closed-lid observations

The owner physically closed the lid during inspection. Power service reported:

```
mWakefulness=Asleep
mLastSleepReason=lid_switch
mHalAutoSuspendModeEnabled=true
mHalInteractiveModeEnabled=false
```

Wi-Fi remained associated, Bluetooth remained ON, and battery information could still be read over USB. The device was charging over USB throughout. This does not establish app-level background communication while unplugged or during extended suspend.

DeviceIdle reported mLightEnabled=false and mDeepEnabled=false at inspection. This is a snapshot, not a guarantee about other firmware or future states. Normal hardware suspend still applies.

A three-packet ping from the Mac to the Thor received no replies. Cause is undetermined: network routing, guest client isolation, ICMP filtering, or power behavior could contribute. Wi-Fi association alone does not prove peer reachability.

## Recommended next validation

1. Build a minimal ordinary Android app that reads public battery APIs and tests access to storage descriptors; distinguish shell-only data from app-accessible data.
2. Test BLE advertising, a GATT connection, and authenticated telemetry with a phone.
3. Test Wi-Fi telemetry on a network known to allow device-to-device connections.
4. Test lid closed while charging, then unplugged for an extended period, with no ADB traffic. Record telemetry age, reconnect behavior, and battery cost.
5. Decide update interval and whether user-enabled background/battery permissions are necessary based on measured results.

No app was installed. No root, bootloader, firmware, charging, network, or sleep settings were changed. Google platform-tools were downloaded into the workspace's work/android-tools directory, and an ADB server was started on the Mac.
