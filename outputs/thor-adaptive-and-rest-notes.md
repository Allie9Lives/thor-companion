# Thor 0.14.0 — adaptive connection and overnight keep-alive

## Connection routing

The companion wraps its existing Bluetooth transport with one logical session. Foreground health checks use connected-peripheral RSSI and measured response times. Network status and the actual telemetry endpoint must pass pinned TLS and owner-token authentication before network controls are eligible. Two successful probes plus sustained weak/slow Bluetooth can select the network; consistently faster network response can also select it. Switching has a 15-second hold to avoid oscillation; a failed network bypasses that hold. The physical Bluetooth subscription remains connected and receives live notifications while network controls are selected. If Bluetooth drops with a usable network, readings and controls remain available and Bluetooth reconnects independently. Deliberate Disconnect cancels both paths and retries.

The host exposes only allowlisted reads and controls on the existing encrypted server. Network access must already be enabled; automatic bootstrap does not turn it on or grant storage permissions. Credentials remain in the existing native secure store, associated with the paired device and certificate pin. Existing preferred VPN addresses are preserved for that same identity. No router, Wi-Fi or Tailscale configuration is changed. Background iPhone networking is not promised: background monitoring uses the existing CoreBluetooth behavior.

Commands use the same request ID and bytes when falling back. A shared, bounded host receipt cache covers both transports and rejects a reused ID with different bytes. It retains payload digests and replies, not keyboard text, with five-minute expiry and a 256-entry cap. Control exchanges are serialized in the client. Network writes return their correlated result atomically; plain network control reads cannot consume a pending Bluetooth detail reply. Files and screenshots stay network-only.

## CPU keep-alive

Default: Overnight, 21:00–06:00 local time, three continuous hours with screens off, explicitly trusted Wi-Fi only. Active screens reset the delay. Unverified, disconnected or untrusted Wi-Fi does not qualify. Trusted identities combine the network name and current security type; a bounded fixed shell probe obtains them through the existing authenticated advanced helper. It neither scans for nearby networks nor modifies network settings. Trust is an explicit host confirmation, separate from Android's debugging-network approval. No network was added to the user's trusted list during verification.

The host retains its foreground service but releases its own partial wake lock during a pause. It does not force Android's global Doze mode or stop other apps. Always on and Passive remain selectable. Opening the screens, the configured local restore alarm, or a successful Wake screens command can resume monitoring. Manual Allow deep sleep pauses the app lock regardless of network; its notification/history record describes an allowed sleep interval rather than guaranteed hardware sleep.

An on-device AlarmManager wake-up restores keep-alive at the end of the window with the screens off. Exact timing uses Alarms & reminders permission; an allow-while-idle inexact alarm is the fallback. Timezone/clock and alarm-permission changes reschedule it. Boot/package recovery schedules it again while monitoring is wanted. Manual Stop cancels it and the receiver will not restart a deliberately stopped host. The phone can change the restore/end time while connected. This cannot boot a shut-down device or bypass Android force-stop.

When the host reports a pause, the client suppresses routine control/activity/link probes and stale-link repair. A foreground network-only session checks again around the saved restore time; iOS background limits still apply. Explicit user operations can try a connection, but radio/CPU availability can delay or prevent delivery.

## Battery history

Database version 2 preserves existing samples and adds bounded, timestamped keep-alive pause/resume events plus Android idle-mode observations. These sync through a separate paged, correlated request and are cached per device on the client. Both native and client battery graphs shade keep-alive pause intervals. Sampling gaps stay blank; graph shading does not assert uninterrupted deep sleep. Existing runtime calculations still require measured contiguous battery data.

## Verification

- Native tests cover night boundaries, the three-hour dwell, trusted-network and active-screen guards, Always on/Passive modes, local-clock daylight-saving restoration, fixed Wake key action and command-receipt expiry/collision/bounds.
- Client tests cover isolated Wi-Fi, successful handoff without Bluetooth cancellation, Bluetooth loss with network continuity, network failure fallback, identical-request retry, explicit disconnect, immediate cancellation, background behavior, pause-aware probing and morning rechecks. An actual TLS fixture verifies certificate pinning, bearer authentication, command bytes and old-host rejection.
- A device instrumentation check exercised authenticated network reads/controls, unauthorized rejection, input bounds and shared cross-transport receipts.
- A separate check on the Thor verified automatic helper protocol-5 recovery, read-only Wi-Fi identity detection, default settings, actual CPU wake-lock release, restoration by a short local exact alarm with screens remaining off, and the Wake screens action. The short alarm exercises the same receiver used by the daily restore; no full three-hour overnight battery-drain measurement is claimed.
- Temporary verification packages are removed and normal monitoring restored after testing. The iPhone was unplugged, so physical iPhone handoff verification remains for installation.

Platform references: [Android alarms](https://developer.android.com/develop/background-work/services/alarms), [Doze](https://developer.android.com/training/monitoring-device-state/doze-standby), [Wi-Fi information privacy](https://developer.android.com/reference/android/net/wifi/WifiInfo).

## Host 0.14.1 — charger exception and custom delay

An off-by-default host preference (`rest_keep_plugged`) bypasses automatic Overnight and Passive pauses while the sticky battery broadcast reports any plugged-in power source. This uses the plugged field rather than charging status, so full-charge and firmware bypass states still qualify. Plug/unplug events and changing the switch immediately re-evaluate the app wake lock. State transitions are recorded in battery history and announced through the existing live update channel. Manual sleep and manual Stop retain priority. Screens-off elapsed time continues while plugged in; unplugging reapplies the original timer.

The host's delay picker retains presets and adds a validated custom value from 1 to 1440 minutes, with readable duration labels. Default remains 180 minutes. No client binary or protocol update is required; client 0.14.0 remains compatible. Native policy tests cover the enabled/disabled charger exception, unplugging, manual sleep priority, Passive mode, and a non-default delay.

## Host 0.14.2 — Bluetooth control-status size regression

The added power-policy fields increased the real control snapshot to 604 bytes with the active request acknowledgement. ATT attributes are limited to 512 bytes, so Bluetooth could fail while ordinary telemetry and the full network control snapshot still worked. The GATT callback now creates a bounded, stable control-read packet: it omits host-only policy configuration and unused/obsolete capability hints, preserves all control fields consumed by current clients, and shortens oversized errors by Unicode code point. Network snapshots retain the full metadata. History and network-link detail replies keep their original schema.

Device instrumentation measured a 590-byte fresh full snapshot versus a 429-byte Bluetooth packet, verified every client-used capability, maximum-length request IDs and long Unicode errors, and unchanged history/link detail replies. The connected iPhone reconnected and the user confirmed Controls loaded without the error. No pairing reset or client reinstall was needed.

The device regression test is at `thor-monitor-prototype/tests/device/ControlPacketDeviceTest.java`; build/run it as an Android instrumentation test targeting the host. It is separate from the pure-Java tests because it exercises the Android JSON implementation and actual host snapshot.
