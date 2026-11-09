# Thor Monitor 0.14.3

Version 0.14.3 refreshes the host UI: shorter setup copy, an icon and progress bar for each onboarding step, fixed navigation buttons, and expandable Settings sections. Recovery returns to the setup step that opened it. Open **Settings → Review setup** to see the new onboarding without resetting permissions or pairing. See [host UI polish notes](../thor-host-ui-polish-notes.md).

Version 0.14.2 bounds Bluetooth control-status packets to the 512-byte ATT attribute limit. Host-only metadata stays in the full network snapshot; existing client controls and capabilities are retained. Long errors are safely shortened. Device regression checks and the connected iPhone confirmed the fix.

Version 0.14.1 adds an optional **Keep awake while plugged in** switch and a preset/custom **Pause after screens off** delay (1–1440 minutes; default 180). Charger changes re-evaluate the policy immediately; full batteries count as plugged in. Manual Stop and manual sleep still take precedence. Unplugging reapplies the existing screens-off timer.

Version 0.14 adds authenticated network controls with retained Bluetooth fallback, configurable overnight CPU keep-alive pauses on explicitly trusted Wi-Fi, local morning restore alarms, Wake screens and battery-history pause markers. See [adaptive connection and battery saving](../thor-adaptive-and-rest-notes.md).

The host now opens to a local Overview matching the companion: battery, runtime, CPU/GPU/RAM, focused apps, internal storage and microSD. Battery insights provides 24-hour and seven-day graphs and diagnostics from the Thor's existing private history. Monitoring, permissions, appearance and recovery setup are under the gear → Host settings. Remote device controls remain in the companion. See [host Overview and exit-animation notes](../thor-host-overview-notes.md).

Current additions: secure Wi-Fi/VPN file browsing for selected folders or full shared storage, focused-app CPU/lid diagnostics, optional closed-lid alerts, service-dismissal recovery and contextual Tranquility sounds. See [0.10 setup and implementation](../thor-network-and-activity-notes.md) and [sound credits](../thor-sound-credits.md).

Android host for the AYN Thor. It shares battery, performance, internal storage, microSD and hardware readings with Thor Companion over authenticated Bluetooth Low Energy, and accepts a restricted set of device-control commands.

Follow [the public setup guide](../thor-setup-guide.md) for onboarding, phone pairing and on-device automatic recovery. See [0.9 implementation and verification](../thor-feature-notes.md) for how recovery works and exactly what was tested. Earlier version notes are historical; their computer-assisted permission setup is superseded.

## Monitoring and recovery

Allow Nearby devices, Bluetooth, notifications and unrestricted battery use through onboarding. Choose Start after restart as desired. Start monitoring, connect from the phone and approve system pairing. Appearance supports Light, Dark, Clear Purple and Rainbow.

Battery saving defaults to Overnight: after three continuous hours with screens off, pause this app's CPU wake lock between 21:00 and 06:00 on Wi-Fi you explicitly trust. Configure the window, delay, trusted networks and alarm permission under Host settings → Battery saving. No network is trusted automatically. Always on is available and marked not recommended; Passive allows Android to sleep at any time. Stop monitoring saves the stopped state. Start after restart and scheduled restore do not override a manual Stop. After reboot, Android's first unlock and required permissions must be available before recovery can finish.

Advanced controls use a shell-privileged helper. Pair Wireless debugging locally once on trusted Wi-Fi. Version 0.9 completes its one-time permission grant on-device, then restores the helper after restart or upgrade. No computer is needed for normal operation or the tested on-device grant. See the setup guide for network approval and recovery limits. The optional `enable-controls.py` is a development/repair tool, not a required end-user setup step.

## New in 0.9

- Find my Thor: generated speaker tone, gentle 10-second ramp, automatic 60-second stop, notification/phone Stop, prior alarm volume restoration.
- Live control snapshots and intermediate slider writes from the companion.
- Fixed sleep/restart/shutdown commands, with destructive-action confirmation in the companion.
- Immediate battery/power-change notifications to the phone and optional health/capacity/cycle telemetry.
- Private seven-day battery history recorded independently of the phone connection and paged over the authenticated control characteristic.

## Controls and telemetry

Brightness and media volume can be adjusted separately for the two screens. The companion supplies independent sync switches. Advanced controls include the 60/120 Hz refresh limit, stock fan and performance modes, input focus, direct power supply, vibration, LEDs and controller layout. Clean background apps clears cached processes; it does not force-stop every app like the OEM cleaner.

CPU/GPU names come from the firmware. CPU usage is an aggregate counter delta; GPU usage comes from the firmware’s GPU busy reading. USB input watts use USB voltage/current readings and differ from net battery charging power or a charger’s rated output. Missing readings stay unavailable. microSD detection distinguishes SD storage from USB disks.

Screen-only display modes remain unexposed because full display/input-routing behavior has not been verified. See `../thor-controls-and-ui-notes.md` and `../thor-recovery-notes.md` for detailed verification and limitations.

## BLE services

- Battery service: `180F`, level `2A19` (read, notify).
- Telemetry service: `a7b31000-8427-4c35-9d6a-9af7b6729e01`.
- Stats: `a7b31001-8427-4c35-9d6a-9af7b6729e01` (UTF-8 JSON).
- Live sequence/battery: `a7b31002-8427-4c35-9d6a-9af7b6729e01` (read, notify).
- Hardware: `a7b31003-8427-4c35-9d6a-9af7b6729e01` (UTF-8 JSON).
- Control service: `a7b32000-8427-4c35-9d6a-9af7b6729e01`; characteristic `a7b32001-8427-4c35-9d6a-9af7b6729e01` (read/write with response).

Telemetry and controls require an authenticated, bonded phone matching the app’s saved owner. Forget saved phone clears the app’s owner selection, not Android’s system Bluetooth bond. Reads support stable long-read snapshots and let Android enforce the actual MTU. Control writes are bounded, allowlisted and acknowledged with request IDs; the client reads back current settings.

## Build

```sh
python3 outputs/thor-monitor-prototype/build.py
```

The manual build uses the workspace’s JDK 17 and Android SDK tools under `work/`. The host currently targets the Thor’s Android 13 and arm64 architecture. Pinned AAR/JAR dependencies, checksums, third-party notices and relevant source archives are under `third_party/`. No OEM APKs, extracted OEM source, private recovery identities or signing keys are included in source deliverables.

Private logs can be retrieved with authorized ADB:

```sh
adb shell run-as com.alan.thormonitor cat files/diagnostics.jsonl
```

First-install setup includes six guided screens, including Thor color and optional file/keyboard features. See [setup verification and layout notes](../thor-setup-and-layout-notes.md) and [color onboarding notes](../thor-blur-and-color-notes.md).

## 0.12 update

See [connection health, runtime and Wi-Fi screenshots](../thor-health-runtime-wifi-notes.md) for current setup and verification. Screenshots now require Wi-Fi. The optional locator Stop panel appears over apps and normal Stop fades out.

## 0.12.2 icons and widgets

See [host icon and battery widgets](../thor-widget-and-icon-notes.md) for the new host launcher icon, percentage-aware widget battery symbols, charging plug and circular Home Screen widget.

## 0.12.3 settings and host themes

See [settings and host themes](../thor-settings-and-host-themes-notes.md) for the client tile menu, shared host/popup themes and the louder-starting 10-second locator ramp.

## 0.12.4 blur and color

See [locator blur and Thor color](../thor-blur-and-color-notes.md) for the animated blurred Stop panel, first-run color selection and matching launcher icons.
