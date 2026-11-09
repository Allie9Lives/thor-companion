# Current verification — 0.12.3

99 Flutter tests pass; analysis is clean. Added four-theme settings renders, footer order and narrow 2× text coverage. Native envelope/palette/contrast checks and on-device themed Stop-panel rendering passed. See [settings/theme notes](../thor-settings-and-host-themes-notes.md). Client 0.12.3 was installed and launched after the phone was reconnected.

---

# Current verification — companion 0.11.2 stats copying

The device-detail values share one leading column. Long-press copying covers card padding, text and the battery gauge, and preserves full hardware names in reports. All 85 Flutter tests pass, including shared-column alignment, per-card formatting, demo labeling, clipboard method calls and card-wide gesture handling. Analyzer is clean. See [stats-copy notes](../thor-stats-copy-notes.md). Host remains 0.10.2.

---

# Current verification — companion 0.11.0 themes

Clear Purple is a dark palette based on #6B5C87; Rainbow is white with yellow/green/blue/red accents. Added actual Flutter render checks for both themes, foreground/secondary/button contrast and switching to Dark while retaining the existing controller/readings. Existing light/dark and functional tests remain. Appearance preference names preserve older saved choices. Native host remains 0.10.1; widgets retain system-managed appearance. See [theme notes](../thor-theme-notes.md).

---

# Current verification — 0.10.0, November 7, 2026

- 80 Flutter tests passed; analyzer clean. Native host, Android arm64 companion and signed iPhone builds passed.
- Native pinned-TLS upload/download byte equality passed on both drives; unauthenticated/path-escape/protected-directory requests and duplicate names were rejected. TLS identity remained stable across server restart.
- Owner confirmed real iPhone Files download/save and uploads to microSD and Internal with the Thor closed. Both uploaded test documents matched the original hash and were removed afterward. The scene-based Files-picker presentation failure was fixed and physically retested.
- Owner confirmed focused apps in the dashboard. The hall sensor reported 0 open and 1 after physical closure. Pure Java tests cover ten-minute gating, sustained load, cooldown, unknown sensor and observed drain; no real ten-minute high-load alarm was forced.
- Removing only the host UI task preserved the same monitoring process and continued sampling. Optional dismissal recovery is exposed in setup and settings; Android force-stop is not bypassed.
- Contextual WAV resources are bundled in the signed app. Locator playback passed a native resource test; configured-device notification naming is covered by a test. Tranquility attribution/license/edit details are present in both apps and source packages.
- Existing Tailscale configuration was left unchanged. Cross-network VPN routing was not separately tested; the app uses existing reachability and does not create a relay.
- Broad shared-storage access is optional and user-granted; protected app/system files remain excluded. Development builds have not been submitted to a store.

See [current network/activity notes](../thor-network-and-activity-notes.md). Earlier entries below are historical.

---

# Current verification — 0.9.0, November 7, 2026

- All **76 Flutter tests pass**; analyzer reports no issues.
- Native host 0.9.0 (11), Android companion arm64 debug and signed iPhone 0.9.0 (18) builds pass. Both physical devices were updated with saved preferences retained.
- Thor protocol-2 helper upgraded automatically through its saved local pairing. Replacing the one-time WRITE_SECURE_SETTINGS permission through on-device local ADB passed after explicitly revoking the old grant; no computer grant was issued. This did not reset/re-pair the owner's installation or perform another full reboot.
- Native locator notification stopped playback and restored volume/mute. Isolated SQLite test returned ten synthetic rows in three bounded pages and deleted its private test database; production history was not seeded.
- Owner confirmed actual iPhone test notification, locator Stop, live brightness changes from Thor and successful real battery-history sync/graph.
- Power buttons have separate rows, red shutdown style and stable enabled state during refresh. Tests verify waiting for an active read and no replay after an uncertain power acknowledgement. Actual restart/shutdown were not executed to avoid closing running apps. Shell command availability and REBOOT permission were inspected.
- Notification threshold tests cover crossing, hysteresis, persistence and no historical replay. Real threshold crossings were not tested by draining the battery. Android phone notification delivery has not been physically checked on a separate phone.
- Battery graphs preserve recording gaps. Screen time is sampled global interactivity, capacities are raw controller reports, and no calibrated maximum-capacity percentage/per-app energy claim is made.
- Private keys and recovery identities are excluded from source archives. iPhone output remains a device-limited development build, not an App Store/TestFlight submission.

See [current implementation notes](../thor-feature-notes.md) and [public setup guide](../thor-setup-guide.md). Entries below are historical and can describe behavior superseded by later versions.

---

# Companion verification — November 4, 2026

- Flutter analyzer: passed with no issues after the initial implementation and formatting fixes.
- Automated tests: **35 passed**. Coverage includes host protocol parsing, unsupported/malformed values, connection initialization, notification-triggered refresh, serialization of GATT reads, stale cached data after a disconnect/reconnect, late-response rejection, and dashboard/device layout. The dashboard render checks now cover both light and dark themes and switching between them without replacing the active controller.
- Widget render: actual Flutter dashboard rendered at 390 × 844 logical pixels, exported at 2× scale. Demo state is explicitly labeled. Device details also exercised at 320 × 640 with 1.5× text scaling; no layout exceptions.
- Web preview build: passed. Browser preview uses demo data only and never attempts Bluetooth.
- App icons: generated from the same code-native handheld mark used in the interface.
- Native Android: **debug arm64 APK build passed**, with compile SDK 37 and AGP 9.1.1 to match BLE/permission plugin requirements. APK signature verification passed. Saved as `../thor-companion-android-debug.apk`. No real Android-phone BLE session has been tested with this companion yet.
- Native iOS: **unsigned device build, signed debug device build, and signed release device build passed** with Xcode 26.5, producing `build/ios/iphoneos/Runner.app`. The release app is approximately 20.6 MB and runs without Xcode's debugger. First builds exposed missing platform support; the iOS 26.5 runtime was installed and registered. A failed duplicate image from overlapping installation requests was removed while retaining the downloadable asset.
- Physical iPhone: **signed release app installed and running** on the iPhone 17 Pro Max, running iOS 26.0.1 with Developer Mode enabled. CoreDevice installation succeeded. The signature passed `codesign --verify --deep --strict`, and the embedded provisioning profile includes this phone. After the owner trusted the development profile, the app was confirmed as running via CoreDevice process inspection.
- Real BLE companion session: **owner confirmed live battery percentage, temperature, and UFS 4.0 readings, with the Updated time refreshing about every 30 seconds inside Thor Companion**. This is a user-confirmed functional smoke test of the new app, in addition to the earlier host-only nRF Connect test. Extended iPhone background behavior and a full closed-lid endurance test with this new companion have not yet been performed.

## Development installation

The current personal-team provisioning profile expires **November 11, 2026**. The app will require signing/installing again after that profile expires. A saved development IPA uses the same device-limited profile; it is not an App Store or TestFlight package.

The host is Thor Monitor Test 0.3.1, whose CPU-awake test session stops after ten minutes. A long-running production host mode and measured battery cost remain separate work.

The owner selected a Personal Team in the local Xcode project, and Xcode created an Apple Development certificate and managed provisioning profile. The portable source ZIP clears the local development-team setting and does not include certificates, keys, or profiles. The companion has not been published or submitted to a store. No cloud/backend is used.

## Version 0.2 appearance update

- Replaced the green palette with neutral light and dark palettes, including the app icon.
- Added System default / Light / Dark appearance selection in the settings sheet, with a locally saved preference.
- Kept the dashboard card layout and BLE controller behavior; shortened headings, setup instructions, and device labels.
- Rendered and visually checked both themes at phone size; tested theme switching and the narrow-screen large-text device page.
- Flutter analyzer passed; all 16 automated checks passed. Updated Android arm64 debug APK built successfully.
- Updated signed iPhone release build passed. Version 0.2.0 (build 2) was installed over the existing app and launched successfully through CoreDevice. The app signature passed verification. The theme update has not required any host or BLE protocol changes.

## Version 0.2.1 reconnection fix

- Host logs showed stats read responses cut to 22 bytes after a host restart; the prior server used an assumed ATT MTU of 23 when no fresh MTU callback was received for the existing connection.
- Host 0.3.1 sends the remaining stable attribute value to Android, whose ATT stack applies the actual negotiated packet size. Offset handling remains in place for long reads. It also reports Passive monitoring and Stopped separately; previously the combined label obscured a running service.
- Companion explicitly rediscovers services before setup, never subscribes after a failed first stats read, preserves that read error, and allows Refresh to retry the full setup/subscription path.
- Added regression checks for failed initial reads followed by recovery and for restoring a failed notification subscription. All 18 checks pass; analyzer has no issues.
- Signed iPhone release build and Android arm64 debug build passed. Companion 0.2.1 was installed and launched successfully; host 0.3.1 was installed and passive mode was verified through UI and sample logs. Physical disconnect/reconnect confirmation is pending.

## Ongoing iPhone reconnection investigation (0.2.2–0.2.3)

- Physical attempts with companion 0.2.1 and 0.2.2 failed; the Thor remained discoverable. The earlier successful live-data session does not validate these reconnect paths.
- Version 0.2.2 connects directly to known CoreBluetooth peripherals on iOS instead of requiring another advertisement. Android retains its prescan connection path. Physical attempts still failed after this change.
- CoreDevice console captured the BLE plugin warning `No event channel set up to report a connection update`. This is a clue, not proof of the root cause; Dart connection/error messages did not appear in the release console.
- Version 0.2.3 adds an iOS-local connection diagnostic file, capped at approximately 1 MB. It records connection phases and errors, without telemetry payloads or Bluetooth identifiers. No diagnostics are uploaded. Analyzer and all 18 tests passed; physical diagnosis remains in progress.

## Service-cache mismatch and connection lifecycle (0.2.4–0.2.5)

- Host Bluetooth handle-table inspection showed the custom service with all three characteristics correctly registered. After a host Bluetooth restart, an iPhone attempt still failed before any application stats read reached the host.
- The iPhone service enumeration showed custom service `a7b31000…` with no characteristics, while all three monitoring characteristics appeared beneath unrelated audio service `184c`. This is consistent with a stale CoreBluetooth service cache. The client does not work around it by trusting characteristics under an unrelated service.
- Connection cancellation now waits for a native disconnect acknowledgement (bounded at five seconds), preventing that event from ending the next connection. Rapid repeated Connect actions are ignored while connecting. Reconnect on a still-live link retries data setup instead of replacing the connection.
- Regression tests cover delayed native disconnect acknowledgement, an already-disconnected link, duplicate Connect actions, and retrying setup on a live link.
- Version 0.2.4 was installed and its service enumeration captured the mismatch. Version 0.2.5 adds actionable cache-recovery guidance instead of the generic setup error. System Forget followed by fresh scanning restored the correct service map; the iPhone log shows a successful stats read and the owner confirmed readings returned. The owner then confirmed Disconnect → Reconnect worked. The iPhone log independently records reconnection, correct service discovery, and another successful initial stats read at 15:16:39 local time.

## Saved device control (0.2.6)

- Added **Forget Thor** to the bookmarked device card’s **⋯** menu. It uses the existing disconnect-and-forget action to remove the app’s saved device and cached readings. The iPhone system pairing remains under iOS Settings.
- Analyzer passed; all 22 automated checks passed before the final appearance-control build.

- Signed release **0.2.6 (build 8)** built successfully, passed strict code-sign verification, and was installed over the existing iPhone app. It includes the saved-card Forget control, explicit cache-recovery messaging, and the connection-lifecycle changes tested above. The physical reconnect confirmation was on 0.2.4; 0.2.5/0.2.6 add messaging and the menu without changing that connection flow.
- Version 0.2.6 Android arm64 debug APK built successfully; APK signature verification passed with the staged JDK. The updated source archive and development IPA were refreshed. Android phone BLE behavior remains untested.

## Version 0.3.0 — performance and microSD

- Added optional CPU, measurement window, GPU, available RAM and microSD state/capacity/free fields to the parser. Missing or invalid usage stays unavailable, and invalid/out-of-state storage cannot render a used-space percentage.
- Dashboard adds a neutral Performance card and places microSD immediately beneath internal storage. CPU includes its averaging window; RAM includes used/total bytes.
- Analyzer passed; all 25 tests passed, including real widget renders in both themes and a narrow layout with 1.5× text scaling. Light/dark storage previews were rendered and visually inspected; these previews use demo data.
- Host 0.4.0 is installed and app-process sampling verified all four new data sources. Signed iPhone release build and Android arm64 debug build passed. The iPhone app 0.3.0 (build 9) was installed and launched; strict code-sign verification passed, as did Android APK signature verification. Physical display confirmation is pending a system re-pair because the host upgrade again produced the previously diagnosed stale CoreBluetooth service map. The new client detected it and showed its recovery message.

## Resumed device verification — November 5, 2026

Both devices were detected by the Mac. Host monitoring had stopped at the previous ten-minute deadline; a new timed session was started through its UI. The owner confirmed the Performance and microSD readings work in the installed iPhone app. At 12:24:37 local time the phone log recorded a valid stats read with the correct service map. The host independently recorded a successful 373-byte stats response, a 246-byte hardware response, and a live notification subscription. The sample contained CPU 8.7% across 29,861 ms, GPU 2%, available RAM 10,248,302,592 bytes, and mounted microSD usable capacity/free bytes 511,801,556,992 / 260,961,730,560.

The version 0.3.0 source ZIP, development IPA and Android debug APK were refreshed. Archive version and source exclusions were verified. The host is still the bounded ten-minute test mode; long-duration production monitoring and battery cost remain future work. No new code changes were needed to resume this session.

## Version 0.4.0 — automatic reconnect and Lock Screen battery

- Analyzer passed; all 33 Flutter tests passed. New coverage includes automatic reconnection/subscription recovery, manual cancellation, background/foreground behavior, radio off/on, the preference switch, exceptional stale-cache handling, one native pending background attempt without retry timers, and widget snapshot/Forget publication.
- Standalone Swift snapshot checks passed for recent/stale/offline status and cache encoding roundtrip. These tests do not access the Mac Keychain.
- Signed iPhone release build passed with embedded native WidgetKit extension; both targets use the same shared Keychain access group. Entitlement and Info.plist group values were inspected and matched. Strict deep code-sign verification passed. Version 0.4.0 (build 10) was installed on the iPhone.
- Cold launch automatically scheduled a connection at 12:53:03 local time and received its first valid stats at 12:53:11 (8 seconds), with service validation and subscription. The native battery cache write succeeded, as confirmed by the phone log. A subsequent notification also refreshed the saved snapshot.
- Owner confirmed the compact widget displays the Thor battery on the Lock Screen. Phone logs recorded continued snapshot writes after backgrounding at 12:54:22, including 12:54:33, 12:55:03, 12:55:33 and subsequent samples.
- Controlled test: the Thor host was stopped, its Bluetooth radio was turned off/on while preserving pairing, and monitoring restarted. With the iPhone still locked, logs show disconnect and one native background connection request at 12:57:24, then validated services, successful stats read and saved widget snapshot at 12:57:40. Further notification-driven snapshots followed. No foreground event or OS unpair occurred during this recovery. Total interval includes the deliberate host/radio outage; it is not a pure reconnect latency measurement.
- Owner confirmed intentional Disconnect stays disconnected for ten seconds, then was instructed to resume manually. No long-duration or force-quit background reliability claim is made.

## Version 0.4.1 — snapshot-time clarification and Live battery

The owner reported the compact widget's percentage was correct but its displayed update time stayed old until reconnecting. Incoming phone cache writes had continued while locked. WidgetKit reload requests cannot ensure a redraw per Bluetooth sample. The compact widget now explicitly labels its time **As of**, and unchanged-value reload requests are reduced to a 15-minute fallback instead of every minute.

Added optional ActivityKit Live battery with a Lock Screen/Dynamic Island presentation, updated from each actual incoming sample. Receive time participates in content equality even when battery percentage is unchanged. Connection loss or 90-second stale content displays Last known reading. Start/Stop are explicit user controls; no server or push entitlement is used. Source cache is retained when reconnecting the same saved Thor, while Forget clears both cache and activity.

Analyzer and all 35 Flutter tests passed, including native Start/Stop method dispatch and preserving an existing saved-device cache on reconnect. Swift snapshot checks passed after adding content-equality coverage. Signed iPhone 0.4.1 (build 11), with the embedded widget/Live Activity extension, built successfully and was installed. Strict code-sign validation and matching shared-cache entitlements passed. The Android arm64 debug build and its signature verification passed. The owner confirmed the Live battery panel updates while the iPhone is locked, without disconnect/reconnect. The phone log independently shows continued receive/cache events at 13:12:42, 13:13:12 and 13:13:42 after backgrounding at 13:12:30. This validates the Live Activity path in a short foreground-to-locked test, not unlimited background runtime. The small WidgetKit widget remains a system-scheduled snapshot; the Live Activity does not remove WidgetKit refresh limits.
