# 0.9.0 implementation and verification

The public setup instructions are in [thor-setup-guide.md](thor-setup-guide.md). Historical notes describe earlier builds and may contain superseded USB setup instructions.

## Recovery: what previously needed the computer

The original development setup used authorized USB ADB once to grant `android.permission.WRITE_SECURE_SETTINGS` and start the shell-privileged controls helper. That grant let the host re-enable Android Wireless debugging later. A separate six-digit, on-device wireless-debugging pairing saved the host's own local ADB identity. The computer was not a background dependency: the earlier full-reboot verification restored monitoring and the helper automatically after boot, without a computer starting the helper.

Version 0.9 removes that initial computer permission step from the normal setup. The user enables Wireless debugging and completes local pairing on the Thor. `Recovery.attempt` connects only to `127.0.0.1`, executes a fixed `pm grant` for this app's own validated package name, checks the actual permission, then starts the fixed helper. The one-time grant and helper launch have deadlines. Saved pairing and permission are reused. Monitoring boot recovery remains `BOOT_COMPLETED` / `MY_PACKAGE_REPLACED` plus `START_STICKY`, gated by saved monitoring intent, start-after-restart and required permissions. Android credential-encrypted storage requires the first unlock after boot. Manual Stop remains stopped.

Verified on the connected Thor in this version: USB was used to install test code, revoke the previous permission and collect results. With that permission absent, the app's own already-paired local TLS ADB connection restored it; no computer `pm grant` or helper-start command was run. Diagnostic event `recovery_permission_ready` recorded the on-device grant. This tests replacing the old computer grant, not a destructive uninstall/re-pair of the owner's existing installation. The host also automatically replaced the old protocol helper with protocol 2 after APK update. A new full reboot/shutdown was not performed for 0.9; the previous full-reboot evidence is historical, not a new claim.

The encrypted identity is wrapped by an Android Keystore AES-GCM key and stays in private app storage. Loopback discovery accepts only this device's addresses; fallback reads adbd's own TLS port. The random abstract socket accepts only the app UID; the app verifies shell UID 2000. Protocol migration kills only the PID obtained from that verified peer. BLE cannot supply a shell command, executable path or arbitrary setting name. Keep GATT service order and UUIDs stable to avoid the earlier iOS service-cache problem.

Trusted Wi-Fi, network approval, saved authorizations and firmware support remain prerequisites. The development device's separately approved 5 GHz access-point pin remains intact; it is not a general installation requirement. Its undo tooling remains in `thor-wifi-workaround`. Do not export its passwords, pairing identity or signing keys.

## Locator and power

`FindThor` creates a looping PCM chirp in memory. Alarm stream maximum is combined with a quadratic amplitude ramp from 0.02 to 1 over 20 seconds. Speaker routing is requested, playback is bounded to 60 seconds, and its wake lock to 65 seconds. Phone Stop, tapping/deleting the host notification and audio-focus loss stop playback. Prior alarm volume/mute are restored unless the user changed the volume during playback. A small private restoration marker handles an interrupted process on the next host start. No phone-side location service or Internet finding is implied.

`DevicePower` permits exactly Sleep (keyevent 223), Restart (`svc power reboot`) and Shutdown (`svc power shutdown`). No user-provided shell text is executed. The helper replies before executing its fixed command after a short delay; the client requires a correlated acknowledgement and never auto-replays an uncertain power request. Restart and shutdown have confirmation dialogs. Shell REBOOT permission and command availability were inspected; actual restart/shutdown execution was deliberately not tested during this update to avoid closing the owner's apps.

Physical host probe passed: locator started; the notification Stop action ended playback; the previous alarm volume and mute were restored. Only the gentle initial portion was played automatically. Pure Java checks cover ramp values and fixed power allowlist. The owner separately confirmed the phone locator/stop works.

## Live controls

The foreground Controls page reads the control snapshot once per second when no existing transaction is active. Polling stops in background or while keyboard/screenshots cover the page. Settings remain serialized and coalesced by key/target, optimistic screen links remain visible, and normal control widgets remain interactive during updates. A drag sends its first value immediately, the latest intermediate value at most every 150 ms, and the final value on release. No per-value unbounded backlog is retained. Normal stats subscriptions are unchanged.

The owner confirmed changing brightness on the Thor moves the phone slider. Tests cover sending before release, linked previews, external values and background polling pause.

## Battery notifications

A persisted Dart tracker evaluates only fresh received battery samples. Individual 10/20/80/plug/unplug options are opt-in through a master switch and native notification permission. First observation establishes a baseline. Hysteresis and persisted latches suppress threshold duplicates across reconnects/relaunches. History sync never emits alerts. A drop crossing both low thresholds produces the lowest enabled warning. Power-source broadcasts trigger host capture/notification without waiting for the normal 30-second sample.

Native iOS uses UserNotifications; native Android uses its notification permission and a battery channel. There is no APNs/server fallback. Force-quit, phone suspension, radio range and host sleep can delay events. Owner confirmed the test notification appears on the actual iPhone; threshold crossings and duplicate suppression are covered in Dart tests, not by draining the real battery.

## History and diagnostics

The private SQLite table retains seven days, capped at 10,000 rows. A sample stores timestamp, percentage, power connection, temperature, voltage, raw current, charge counter, input watts and interactive state. It records on a five-minute cadence or observed power/screen transition. Available bounded diagnostic samples can be imported once. No per-app usage access is requested.

The authenticated control characteristic returns at most four history rows per page, <=500 UTF-8 bytes, ordered by timestamp with an advancing cursor and request ID. Exclusive client transactions prevent settings, screenshot or telemetry reads consuming a pending history reply. Client cache is per Thor and bounded to seven days/10,000 rows. Integration includes only adjacent observations <=10 minutes apart: wider gaps remain blank. Screen-on time is sampled global interactivity, not exact tracking of each display. Connected-to-power duration is not necessarily active charging (bypass/full battery exist). Hourly bars sum observed percentage-point loss while unplugged; there is no fabricated continuous power estimate.

Available health, charge_full, charge_full_design and cycle_count are shown as reported. This Thor reported full 6330 mAh, design 5938 mAh and one cycle at inspection. No >100% maximum-capacity claim is derived from those values. Unsupported sensors stay unavailable.

An isolated on-device SQLite database test inserted ten synthetic records, read all ten in three pages and deleted the test database. It did not insert test data in the real history. The owner confirmed real Bluetooth history sync and the graph work. Tests cover gaps, deduplication, malformed samples, non-advancing cursors and history transaction cleanup. A narrow-screen render with larger text covers diagnostics layout.

## Power section refresh refinement

The Device Power section uses one full-width row per action, with red shutdown styling and a matching confirmation action. Background snapshot reads do not disable these buttons. A confirmed user action waits for the current read/transaction to finish, pauses new control polling and sends exactly once. A ten-second wait bound and session checks reject stale/disconnected requests. Buttons disable only for the actual power request, unavailable capability or unusable connection. Regression tests cover enabled buttons during telemetry refresh, separate rows/red style and one command after an active read completes.

## Builds and preserved behavior

Host 0.9.0 (11); companion 0.9.0 (18), including matching widget extension version. Native host, Android companion and signed iPhone builds pass. All 76 Flutter tests pass and the analyzer reports no issues. Existing reconnect intent, phone keyboard, live battery and screenshot protocols are preserved. The Android phone's new native alert delivery is build-verified, not physically tested on a separate Android phone. The iPhone development build remains device-limited and is not a store submission.
