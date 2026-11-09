# Thor Monitor and Thor Companion — setup guide (host 0.14.3 / client 0.14.0)

Thor Monitor runs on the AYN Thor. Thor Companion runs on your phone. They communicate over paired Bluetooth; an internet connection or account is not required. Advanced controls use an additional, on-device setup described below.

After setup, the host opens to Overview with its own live readings. Open Battery insights for locally recorded battery graphs and diagnostics; a phone connection is not required for these pages. Use the gear to open Host settings for monitoring, permissions, appearance, files and Recovery setup. The companion remains the place for remote device controls.

Settings sections expand when tapped. Battery saving is under **Monitoring**; wireless-debugging setup is under **Controls recovery → Recovery setup**. **Review setup** reopens the six-step guide with icons and progress, keeping your existing permissions, pairing and choices.

## Connect a phone

1. Open Thor Monitor on the Thor and follow its setup screens. Choose your Thor color for a matching theme and launcher icon, or continue with the default. You can change it in Appearance later. Then allow Nearby devices and enable Bluetooth.
2. Allow notifications so monitoring status and Find my Thor's Stop action can appear. Allow unrestricted background battery use when offered.
3. Choose **Start after restart** as desired. CPU keep-alive defaults to the Overnight policy described below. Keeping the CPU awake uses additional battery; pausing it may delay updates and remote commands.
4. Start monitoring. Open Thor Companion on your phone, allow Bluetooth access, scan and connect to your Thor. Confirm any system pairing prompts on both devices. Keep the Thor open and unlocked for this first connection.

The phone remembers the selected Thor and can reconnect automatically. Disconnect deliberately pauses reconnection; Reconnect resumes it. Forget Thor removes the app's saved selection, not the operating system's Bluetooth bond. Use system Bluetooth settings only if a new pairing is actually necessary.

## Automatic Bluetooth and network connection

Enable **Wi-Fi access** in the host's settings. On the phone, allow Local Network access when requested. With an authenticated Bluetooth connection, the companion can obtain the Thor's pinned network identity and current addresses automatically. In **Connection health**, Automatic connection is enabled by default and can be turned off; the page shows the selected route, live Bluetooth signal and response measurements. An existing VPN address can also be selected there.

The companion verifies the actual encrypted network endpoints before switching. Weak Bluetooth, repeated failures or consistently better network response can select Wi-Fi/VPN. Bluetooth stays connected as a fallback; restricted/public Wi-Fi can simply remain unusable while Bluetooth carries controls. Files and screenshots continue to require a network route. This does not change Wi-Fi configuration, router settings or Tailscale. Foreground use supports network handoff; iPhone background monitoring continues to rely on Bluetooth and iOS scheduling.

## Overnight battery saving and morning restore

Open **Thor Monitor → gear → Monitoring → Battery saving**. The default window is 21:00–06:00 in the Thor's local timezone, with a three-hour continuous screens-off delay. Select **Trust current Wi-Fi**, review its name and confirm it. No saved network is trusted automatically. Identifying the network uses the advanced helper; if the network identity cannot be checked, overnight saving stays off. Other networks retain CPU keep-alive. Configure automatic recovery first if the helper is unavailable.

**Pause after screens off** lets you change the default three hours using presets or a custom 1–1440-minute delay. **Keep awake while plugged in** is optional and off by default. Enabling it skips automatic Overnight/Passive pauses on external power, including at full charge. On unplug, the existing screens-off timer and schedule apply again; if the delay already elapsed, the Thor can pause immediately. Manual Stop and Allow deep sleep still take precedence.

Allow **Alarms & reminders** for precise morning restoration. The local alarm restores CPU keep-alive without needing the phone and leaves both screens off. Without exact-alarm access Android may delay restoration. Manual Stop stays stopped; this does not power on a shut-down device. The companion's Battery saving card can change the restore time while connected. Changing the restore time also changes the end of the overnight window.

**Always on · not recommended** retains the old continuous wake lock. **Passive** permits sleep at any time. **Allow deep sleep** in the companion releases this app's CPU lock and sleeps the screens until the local restore, normal use or a successful Wake screens command. Android and other apps decide whether the device actually sleeps; remote wake is not guaranteed while the CPU/radios cannot deliver requests. Battery graphs shade recorded keep-alive pauses rather than inventing battery samples or claiming continuous confirmed deep sleep.

## Set up advanced controls and automatic recovery

This is separate from Bluetooth phone pairing. It pairs Thor Monitor with Android's own debugging service **on the same Thor**. No computer or root is required for the normal setup tested on the supported Thor firmware.

1. Connect the Thor to a trusted Wi-Fi network. Enable Developer options in Android settings if needed by tapping Build number seven times and entering your device PIN when asked.
2. Open **Recovery setup** in Thor Monitor, then **Open wireless debugging**. Enable Wireless debugging. If Android asks whether to allow debugging on this network, approve your trusted network; use Always allow if appropriate.
3. Select **Pair device with pairing code** in Android's Wireless debugging page. Leave that system pairing window open. Thor Monitor opens the settings page on the other screen when available.
4. Enter the displayed **pairing port** and six-digit code in Thor Monitor. Use the port in the pairing-code window, which differs from the ordinary connection port. Codes expire; generate a fresh code if pairing fails.
5. Pair, enable automatic controls recovery, and wait for **Advanced controls ready**. The app completes the one-time permission step itself through that local pairing. Use Retry now after approving a network prompt if necessary.

After a restart, unlock the Thor once. When monitoring and Start after restart remain enabled, monitoring resumes; when trusted Wi-Fi/debugging becomes available, the app restores advanced controls. The saved local pairing and permission normally survive restarts and app updates. A computer does not perform that recovery.

Android can still require a new approval on a different network, after debugging authorizations are revoked, or after reinstalling the host. If monitoring was deliberately stopped, restart it on the Thor. A force-stopped app cannot override Android's force-stop restriction. Bluetooth-only monitoring can work while advanced controls await recovery. Do not expect the phone to wake a completely shut-down Thor or start a stopped host remotely.

Wireless debugging is a powerful developer feature. Use a trusted network and keep the paired devices list under your control. Disabling it disables automatic restoration of the advanced helper until setup is available again.

## New controls

- **Find my Thor:** Controls → Find my Thor. The Tranquility locator sound starts gently, ramps over 10 seconds, and stops after 60 seconds. Stop it from the phone or tap its Thor notification. Optionally allow **Stop panel over apps** in the host’s Find my Thor section for a single Stop button over other apps; normal Stop gently fades the sound. It temporarily raises the alarm stream to maximum and restores its prior level afterward; it does not permanently change either screen's media volume. Requires a working connection and running host; this is a nearby locator, not GPS tracking.
- **Live sliders:** While Controls is open, manually changed Thor settings are read about once a second. Brightness and volume changes are sent during a drag with throttling; the final value is sent on release. Sync switches link both screen sliders.
- **Power:** Controls → Device Power offers Sleep screens, Restart and Shut down. Restart and shutdown ask for confirmation because they close running apps. Advanced controls must be ready. Sleeping a screen does not shut down the device; shutdown cannot be undone remotely over this Bluetooth connection.
- **Keyboard and screenshots:** Optional Phone keyboard setup is on the Thor. Screenshots require Wi-Fi and linked network access (open Screenshots → link over Bluetooth once → Check Wi-Fi), plus ready advanced controls and an open, unlocked Thor. They can capture top, bottom or both; both are stitched on the phone and saved to its Photos library. Screenshot images are held temporarily in Thor RAM, not stored as image files there.

## Battery notifications and history

In the phone's settings, open **Battery notifications**, enable them and grant notification access. Each alert can be selected separately: low battery at 20%, low battery at 10%, reaching 80% while connected to power, plugged in and unplugged. Use Send test notification to verify permission. Alerts describe newly observed changes; old history is not replayed as notifications. Threshold hysteresis prevents repeated alerts around a boundary.

Notifications require incoming Thor readings. Bluetooth range, passive host sleep, phone suspension, force-quit, notification settings and Focus modes can delay delivery. This version does not use a cloud/push service to notify an unreachable phone.

Open **Battery insights** below the Overview battery card or from settings. It offers Last 24 hours and Last 7 days. Thor Monitor records approximately every five minutes plus observed power/screen-state changes while running, retaining seven days. History sync can fill phone connection gaps from the Thor's log. Gaps where the host itself did not record remain blank. The graph starts sparse after installation; only available earlier diagnostic samples can be imported.

Battery insights includes observed battery drain by hour, sampled screen-on time, time connected to power, temperature, voltage, current, remaining charge and available controller-reported full/design capacity and cycles. It does not claim per-app energy usage, exact screen-on session tracking or an iPhone-style calibrated maximum-capacity percentage. Controller capacities are raw firmware reports and can exceed the design figure.

## Lock Screen

The compact Thor Battery widget is an iOS-managed snapshot and may refresh less often than readings. Its time is As of. Optional Live battery in the phone's settings provides a Live Activity for more frequent incoming updates. Both show last-known data when fresh readings are unavailable.

## Data and distribution

There are no accounts or cloud telemetry. Battery history stays in the Thor's private database and a local phone cache. Pairing identities stay private on the Thor. Notifications are local to the phone. The current downloadable iPhone build is a signed development build, not an App Store release; public distribution needs production signing and store review. Advanced controls have been tested on the development Thor firmware, not every Thor revision.

## Wi-Fi files, focused apps and sounds (0.10)

See [the network and activity guide](thor-network-and-activity-notes.md) for setup and tested limits. The host offers optional full shared-storage permission to browse internal storage and microSD from the top level, or selected-folder access. The phone uses its Files picker for uploads/downloads and reuses reachable Wi-Fi/Tailscale addresses without changing VPN settings.

Focused-app CPU and the physical lid state appear in Performance. Optional activity notifications are enabled separately under Battery notifications. The host can keep monitoring after the UI is dismissed, with an optional recovery safety net in setup and Background monitoring. Notification titles use your Thor's configured name; contextual sounds are credited in both apps and the [sound credits](thor-sound-credits.md).

## Guided setup update (host 0.10.2)

New installations get five screens: Bluetooth, background monitoring, controls recovery, optional file/keyboard features, and phone connection. Optional permissions can be skipped and configured later. On the final page, start monitoring on the Thor before scanning from the phone. Existing installations retain their setup and can use Review setup. See [setup/layout verification](thor-setup-and-layout-notes.md).

## Connection health and remaining runtime (0.12)

See [the 0.12 guide](thor-health-runtime-wifi-notes.md) for connection checks, the recent-use battery runtime range, Wi-Fi screenshots and the optional frontmost locator Stop panel.

## Home Screen battery widget (0.12.2)

On iPhone, long-press the Home Screen → Edit → Add Widget → search Thor → choose Thor Battery. The circular ring and percentage use the latest received reading, with a plug while actively charging. Existing Lock Screen widgets also show a battery symbol matched to charge level. iOS still controls refresh timing. See [widget notes](thor-widget-and-icon-notes.md).

## Settings and host themes (0.12.3)

The host now offers the same four visual themes as the client. Client Settings uses tiles, with Connection help and Sound credits at the bottom. See [release notes](thor-settings-and-host-themes-notes.md).

## Thor color and locator panel (host 0.12.4)

The locator panel animates in over a blurred backdrop. First-run setup now has six steps, beginning with Thor color. For an existing installation, open Appearance → Thor color & icon. See [blur/color notes](thor-blur-and-color-notes.md).
