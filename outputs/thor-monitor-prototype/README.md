# Thor Monitor 0.14.3

Android host for the AYN Thor. Provides local stats, battery history, paired Bluetooth monitoring and authenticated network controls for Thor Companion.

[Setup guide](../thor-setup-guide.md) · [Sound credits](../thor-sound-credits.md)

## Build

From the repository root:

```sh
python3 outputs/thor-monitor-prototype/build.py
```

Use JDK 17, Android platform 35 and build-tools 36.0.0. See the repository's `BUILDING.md` for tool paths. The build creates `outputs/thor-monitor-test.apk` and uses a local development signing key under ignored `work/`. Keep the original signing key to update an existing installation.

Pinned dependencies, checksums, licenses and corresponding dependency source archives are in `third_party/`. Tests are in `tests/`; device instrumentation is for development only.

## Device setup

Allow Bluetooth, notifications and unrestricted battery use in onboarding. Advanced controls require the host's on-device wireless-debugging recovery setup. No computer is needed for normal setup. Pairing identities, private logs and signing keys are excluded from the source.
