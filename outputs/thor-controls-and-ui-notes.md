# Thor Companion 0.5.0 — historical verification

## Interface and readings

- Larger text throughout, with 16 pt device details and a larger UFS badge. Layouts checked at 320 logical pixels and 150% text size.
- Compact battery card with temperature, battery voltage and USB input watts together.
- CPU and GPU names come from this Thor’s firmware: **Qualcomm QCS8550** and **Adreno 740**. These are reported chip identifiers; no marketing-model guess is substituted.
- USB input watts use the firmware’s USB voltage/current readings. This includes power used by the running device, differs from net battery charging power, and is not a charger’s rated output. Unavailable readings remain blank. Actual plugged-in samples included 1.73–2.21 W with the battery full.
- Existing CPU/GPU/RAM, internal storage, microSD, reconnection, small WidgetKit widget and Live Activity remain supported. WidgetKit still controls the small widget’s refresh schedule.

## Controls

Controls are available only to the Thor app’s authorized, authenticated Bluetooth owner. A separate service is appended after the existing telemetry services, preserving their layout. Commands are serialized, not automatically retried, and checked using a request ID plus current-value readback. Offline or stale readings disable changes.

| Control | Implementation / verification |
| --- | --- |
| Top / bottom brightness | Firmware display controller, without root. Bottom-only change: top stayed 39%, bottom changed to 45%. Both-screen change also checked. |
| Top / bottom volume | Android media volume and the firmware’s secondary-screen volume. Bottom-only change: top stayed 80%, bottom changed to 67%. Both-screen change also checked. Volume follows the device’s 15 discrete steps. |
| Sync brightness / sync volume | Independent switches, remembered across app launches. Linking affects the next slider adjustment; it does not immediately overwrite the other screen. |
| 60 / 120 Hz | Sets the same refresh-rate limit used by the stock FPS button. Both rates are supported by the display. It does not force a game to render at that frame rate. |
| Fan | Off, Quiet, Smart and Sports. Setting/readback tested. Firmware performance changes can also change the fan mode; refresh shows that result. |
| Performance | Standard, Performance, High performance. Standard ↔ Performance setting/readback tested. |
| Input focus | Automatic / top / bottom. This corresponds to the stock “Auto-lock” control, not a sleep timer or screen lock. |
| Direct power supply | Stock bypass setting; on/off setting and readback tested, then restored. Electrical battery-path behavior was not independently measured. |
| Vibration and LEDs | Stock on/off settings tested and restored. |
| Controller layout | Standard / Xbox / Disabled. Xbox settings and associated layout flags verified, then Standard restored. |
| Clean background apps | Explicit button uses Android’s cached/background process cleanup. This does not force-stop all applications like the stock privileged cleaner. Deliberately not invoked during development to avoid closing the user’s background work. |
| Screen-only modes | Investigated but not exposed. Setting readback changed, while display state stayed ON; full behavior and related input/keyboard routing need further verification. |

## Advanced-control setup in 0.5.0 (superseded by 0.6.0)

Brightness and top media volume do not require a privileged helper. The other firmware settings reject ordinary third-party writes, including after a trial ADB permission grant. That grant was removed; the final app requests neither WRITE_SETTINGS nor WRITE_SECURE_SETTINGS.

An optional **ADB-started helper** runs as Android’s shell user, without root. It accepts connections only from this installed Thor Monitor’s UID; the app also verifies the helper’s shell UID. Its local socket name is generated into the app’s private storage. Its command set is restricted to the controls above. No arbitrary settings, command strings, executable names, paths or Bluetooth instructions are forwarded to a shell interpreter.

The helper works after USB is unplugged, but must be started again after a Thor reboot. After updating the host app, restart it with:

```sh
python3 outputs/thor-monitor-prototype/enable-controls.py --serial YOUR_THOR_SERIAL --restart
```

Run from the workspace root. A standalone source copy can supply `--adb /path/to/adb`. Open Thor Monitor once before the initial setup. Start monitoring on the Thor, then open Controls in the companion. For the current host, use the automatic recovery setup in `thor-recovery-notes.md`; the 0.5.0 manual restart requirement below is historical.

Passive monitoring still permits CPU suspension. The existing 10-minute closed-lid test is bounded and unchanged; this release does not establish permanent closed-lid monitoring or its battery cost.

## Verification

- 42 Flutter tests passed, including command correlation, rejected writes, duplicate/overlapping request suppression, disconnected-command blocking, same-device reconnect tests and large-text layouts.
- Flutter analyzer passed.
- Java CPU counter and control allowlist tests passed. The allowlist rejects unsupported rates, modes, values and arbitrary keys.
- Normal host-app UID tests verified firmware controls through the helper and independent brightness/volume. Original user-visible settings were restored. Performance can reset fan mode, so Smart fan was restored last.
- Android host and companion builds passed. The signed iOS 0.5.0 (12) app and widget extension passed signature checks; the app was installed and launched on the connected iPhone.
- Fresh telemetry and control-service reads completed after installation. The user confirmed that a substantial bottom-brightness change in the iPhone Controls page successfully changed the Thor over Bluetooth.

## References

Implementation was checked against this device’s firmware behavior and installed stock control apps. Extracted OEM APKs and decompiled sources are not included in deliverables. Public primary references consulted:

- [Thor’s Lightning](https://github.com/HughesTechNZ/Thors-Lightning): public use of the Thor display controller. The read transaction was independently checked against this firmware; its value differs from that repository’s getter.
- [ThorVolumeLink](https://github.com/pth2000/ThorVolumeLink): secondary-screen volume setting.
- [Android BatteryManager](https://developer.android.com/reference/android/os/BatteryManager): battery current measurements and units.
