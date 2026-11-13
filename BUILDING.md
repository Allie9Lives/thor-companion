# Build from source

## Client

The verified toolchain was Flutter 3.47.9 / Dart 3.13.7, JDK 17, Android compile SDK 37.0 and Xcode 26.5. 

```sh
cd outputs/thor-companion
flutter pub get
flutter analyze
flutter test
flutter build apk --release
# Build platform targets sequentially, then configure your Xcode signing team:
flutter build ios --release
```

The exported Xcode project clears the local development-team setting. Choose your own team for Runner and the widget extension. Build caches and local SDK path files are not committed. 

## Host

The existing host builder uses staged tools under the repository's ignored `work/` directory. Install JDK 17 and an Android SDK with platform 35 and build-tools 36.0.0, then create these local links (set JAVA_HOME and ANDROID_SDK_ROOT to your own installations):

```sh
mkdir -p work/toolchain/jdk-local/Contents
ln -s "$JAVA_HOME" work/toolchain/jdk-local/Contents/Home
ln -s "$ANDROID_SDK_ROOT/platforms/android-35" work/toolchain/android-35
ln -s "$ANDROID_SDK_ROOT/build-tools/36.0.0" work/toolchain/android-15
python3 outputs/thor-monitor-prototype/build.py
```

The `android-15` directory is the historical builder's name for its build-tools directory, not a request to use API 15. On a fresh checkout the builder generates a new local development signing key in ignored `work/thor-debug.p12` and writes `outputs/thor-monitor-test.apk`. Updating an existing installed host requires its original signing identity, which is intentionally not in Git. Do not overwrite an existing signing key.

The host verifies vendored dependency checksums before building. Dependency notices and corresponding source archives are in `third_party/`. Python and Java test sources are under the host's `tests/`; device instrumentation is development-only and must not be shipped as the host.

