# Thor Companion 0.14.0

Flutter client for iPhone and Android. Connects to Thor Monitor for live stats, remote controls, battery tools, screenshots and file transfers.

[Setup guide](../thor-setup-guide.md) · [Sound credits](../thor-sound-credits.md)

## Build

Use Flutter 3.47.9 / Dart 3.13.7, JDK 17, Android compile SDK 37.0 and Xcode 26.5. Dependencies are pinned in `pubspec.lock`.

From this directory:

```sh
flutter pub get
flutter analyze
flutter test
flutter build apk --debug --target-platform android-arm64
flutter build ios --release
```

Build Android and iOS sequentially. For iPhone installation, open `ios/Runner.xcworkspace` and choose your own signing team for Runner and the battery widget extension. Signing credentials and local SDK paths are not included.

## Preview

```sh
flutter run --dart-define=THOR_DEMO=true
```

The iOS widget uses App Groups shared storage. Keep its entitlements aligned with the app when configuring signing. Bluetooth background updates depend on iOS scheduling and stop after force-quitting the app.
