# Thor Companion 0.12.3

Current additions: secure Wi-Fi/VPN file browsing for selected folders or full shared storage, focused-app CPU/lid diagnostics, optional closed-lid alerts, service-dismissal recovery and contextual Tranquility sounds. See [0.10 setup and implementation](../thor-network-and-activity-notes.md) and [sound credits](../thor-sound-credits.md).

Flutter companion for iPhone and Android, paired with Thor Monitor on the AYN Thor. The shared interface provides battery, CPU/GPU/RAM, internal and microSD storage, hardware details and remote controls.

Start with [the public setup guide](../thor-setup-guide.md). [0.9 implementation and verification](../thor-feature-notes.md) documents the new features, recovery design and test limits. Historical release notes describe earlier versions.

## Features

- Light/dark/system, Clear Purple (#6B5C87) and Rainbow appearance, readable device name and model, remembered connection and automatic recovery of missed readings.
- Live brightness and media volume for both screens, with linked sliders. Manual Thor changes appear while Controls is open; dragging sends intermediate values.
- Supported stock refresh-rate, fan, performance, direct power, input focus, vibration, LED and controller-layout settings, plus cached-app cleanup. The host's advanced helper must be ready where indicated.
- Find my Thor ramps a nearby speaker tone; Stop is available on the phone and Thor notification. Sleep, restart and shutdown are under Device power; restart/shutdown require confirmation.
- Optional phone keyboard and top/bottom/stitched screenshots saved on the client.
- Battery notification options for 10%, 20%, reaching 80% while plugged in, plugged and unplugged. Permission and live incoming readings are required.
- Battery insights: 24-hour/7-day graphs, observed hourly drain, sampled screen-on/power connection time and controller-reported battery diagnostics. No fabricated per-app usage or calibrated maximum-capacity percentage.
- Compact iOS Lock Screen battery widget and optional Live battery activity. WidgetKit controls the small widget's refresh schedule; a Live Activity does not change that limit.

## Connection behavior

Only one connection/cleanup path runs at a time. Every new connection validates services, reads fresh telemetry and rebuilds subscriptions. Foreground failures retry with backoff. Background iPhone recovery submits one native pending connection request managed by iOS, without polling timers. Bluetooth unavailability pauses attempts. Disconnect and Forget cancel connection intent; Reconnect resumes it. A specifically detected stale system service cache pauses retries and explains the system pairing repair instead of looping.

Cached data is visibly stale after disconnect or 90 seconds without fresh stats. Forget removes the companion's saved Thor and widget/activity state; it cannot erase an OS Bluetooth bond. Force-quit and OS process termination restoration are not promised. Monitoring must already be running on the Thor. Passive host sleep and either device's OS background rules can delay updates and alerts.

## Privacy and protocol

No account, server, advertising or cloud analytics. Saved device selection, appearance, alert settings/state and seven-day battery cache remain local. Small widget snapshots use the existing native shared cache. Debug builds keep a bounded local connection log without telemetry payloads or Bluetooth identifiers. Screenshots are saved to the client's Photos library with permission; host image buffers are temporary RAM only.

The host's authenticated Bluetooth services are unchanged: telemetry `a7b31000…`, stats `a7b31001…`, live `a7b31002…`, hardware `a7b31003…`, and controls `a7b32001…` under `a7b32000…` (all end `-8427-4c35-9d6a-9af7b6729e01`). Settings/history/power commands use bounded allowlisted JSON and correlated acknowledgements. Power actions and keyboard input are never automatically replayed.

## Build

Toolchain used in this workspace: Flutter **3.47.9**, Dart **3.13.7**, JDK 17, Android compile SDK 37.0, Android Gradle Plugin 9.1.1, and Xcode 26.5. Dependencies are pinned in `pubspec.yaml` and `pubspec.lock`. Android minimum is API 31 (Android 12), target SDK is 35, and iOS deployment target is 15. Flutter's Swift Package Manager integration is enabled for the native iOS plugins. AGP 9.1.1 supports the SDK's `android-37.0` naming; the generated Flutter template's 9.1.0 needed upgrading.

From this directory with Flutter on PATH:

```sh
flutter pub get
flutter analyze
flutter test
flutter build apk --debug --target-platform android-arm64
flutter build ios --debug --no-codesign
```

Build platform targets sequentially. If opening Xcode after an Android build, run `flutter build ios --release --config-only` first to regenerate iOS plugin configuration.

In this chat's workspace, the Flutter executable is `../../work/flutter/bin/flutter`. Its Android SDK and JDK are staged under `../../work/`; local paths and generated build caches are not part of the source archive.

### Run on an iPhone

Install/open Xcode and finish its license and platform component setup. Connect/unlock the iPhone, trust the Mac, and enable iPhone Developer Mode when required. Add your Apple account in **Xcode → Settings → Accounts**. For personal device testing a free personal development team can be used; a paid membership is needed for App Store distribution. See [Flutter's iOS setup guide](https://docs.flutter.dev/platform-integration/ios/setup).

Open `ios/Runner.xcworkspace`, select **Runner → Signing & Capabilities**, enable automatic signing, choose your development team, and select the connected iPhone as destination. Press Run. The portable source archive clears the local development-team setting. An unsigned build verifies compilation but cannot be installed on the phone until signed. For a standalone install that opens independently of Xcode's debugger, build a signed release configuration (`flutter build ios --release`). If iOS requests it, trust your development account under **Settings → General → VPN & Device Management → Developer App**. The current personal-team profile is valid through November 11, 2026; it will need re-signing afterward.

The native iOS app declares `NSBluetoothAlwaysUsageDescription`. It declares `bluetooth-central` background operation. While the process remains available, iOS can deliver BLE events in the background; force-quit and OS termination are not covered by CoreBluetooth state restoration in this build. Android requests Nearby devices permissions and restricts BLE scan permission to non-location use; it does not request location on its supported Android 12+ range.

### Preview without a Thor

```sh
flutter run -d chrome
# Or run the native app with sample data:
flutter run --dart-define=THOR_DEMO=true
```

The preview always displays **Demo data — No device connected**. It is not evidence that the new companion has completed a real BLE test. Icons are generated from a code-native handheld mark; regenerate with `flutter test tool/render_icons.dart`.

## Verification

See `VALIDATION.md` and the current feature notes. Tests cover transport lifecycle, stale data, serialization, live slider writes, linked controls, notifications, bounded history, gap-aware summaries, uncertain power acknowledgement and layout with enlarged text. Physical iPhone confirmation covers notifications, locator stop, live manual brightness sync and history graphs. Actual shutdown/restart were not executed for this release. The downloadable IPA is a development build, not an App Store submission.

## Client themes (0.11.0)

The gear menu → Appearance adds Clear Purple and Rainbow while retaining previous choices and saved preferences. See [theme notes](../thor-theme-notes.md).

Current setup/layout refinements: [notes](../thor-setup-and-layout-notes.md).

Long-press stats-card copying and value-column alignment: [notes](../thor-stats-copy-notes.md).

## 0.12 update

See [connection health, runtime and Wi-Fi screenshots](../thor-health-runtime-wifi-notes.md) for current setup and verification. Screenshots now require Wi-Fi. The optional locator Stop panel appears over apps and normal Stop fades out.

## 0.12.2 icons and widgets

See [host icon and battery widgets](../thor-widget-and-icon-notes.md) for the new host launcher icon, percentage-aware widget battery symbols, charging plug and circular Home Screen widget.

## 0.12.3 settings and host themes

See [settings and host themes](../thor-settings-and-host-themes-notes.md) for the client tile menu, shared host/popup themes and the louder-starting 10-second locator ramp.
