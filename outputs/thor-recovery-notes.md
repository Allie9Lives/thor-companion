# Thor Monitor / Thor Companion 0.6.0

The Thor host now includes guided setup and rootless automatic recovery. The companion’s switches have contrasting thumbs in both on/off states, in light and dark themes.

## Host setup

The four-step guide covers Nearby devices, Bluetooth, notifications, background battery use, optional monitoring with the lid closed, startup after restart, controls recovery and phone pairing. Completed permissions show their current state. Continue/Back stay visible while the content scrolls. Setup and recovery remain accessible from the device screen. System, Light and Dark appearances use the companion’s neutral palette; Android accessibility preferences are preserved.

## Recovery requirements

- Monitoring must be enabled. Manual Stop saves the stopped state and prevents automatic boot startup.
- Start after restart must remain enabled for boot startup. Android may require the first unlock after reboot.
- Advanced controls require one-time local wireless-debugging pairing and the USB-granted recovery permission. Both are already configured on this development Thor.
- On a trusted Wi-Fi network, approve Android’s wireless-debugging prompt with **Always allow on this network**, then Allow. New networks/access points or revoked authorizations can require approval again.
- After startup, the helper runs independently of the Mac. Wi-Fi is needed to restore a missing helper; an already running helper continues serving Bluetooth controls after USB is unplugged.
- Passive monitoring can be delayed by suspend. Monitor while closed keeps the CPU awake and uses additional battery. The resumed session preserves the user’s enabled closed-lid setting.

Recovery runs at monitoring startup, on Wi-Fi availability and alongside the 30-second monitoring schedule. It checks the helper before starting another instance. Android’s own wireless-debugging service handles network readiness; the app does not require a validated/default Internet connection.

The Thor does not reliably announce its local ADB connection port through mDNS. Recovery reads adbd’s own port first, with local mDNS as a fallback. The connection is restricted to 127.0.0.1. The startup command detaches the helper using setsid/nohup and verifies that its private socket answers before reporting success. Expected ADB stream closure is not treated as failure if the helper is ready.

The local ADB identity is encrypted at rest with an Android Keystore AES-GCM key. No private identity, pairing code or development signing key is included in deliverables. Control writes remain authenticated to the saved Bluetooth owner and restricted to a fixed allowlist; recovery does not expose an arbitrary shell endpoint to the companion.

## Verification

- 44 Flutter tests passed, including light/dark switch toggling, control write correlation and rejection, reconnect behavior, and narrow-screen layouts with larger text. Light/dark switch screenshots were visually inspected.
- Flutter analysis passed. Java CPU-counter and control-allowlist tests passed.
- Android host and companion builds passed. The signed iPhone app and embedded widget extension passed signature verification and were installed on the paired iPhone.
- Earlier reboot checks confirmed that Android resumed the foreground monitoring service and retained local pairing and the recovery permission. Testing exposed network approval, startup timing and service-discovery issues, which were addressed in the current build.
- In the resumed session, the latest saved host was installed while preserving completed onboarding, saved phone, continuous monitoring and recovery preferences. Stopping the helper was followed by automatic recovery through local TLS ADB in **20.7 seconds**, with a new helper process and a host `controls_recovered` log entry. No Mac helper-start command was used for that test.

### Final reboot result

The current build passed a complete reboot test after the approved network workaround. Android restarted monitoring at approximately 26 seconds of uptime, preserved the continuous-monitoring choice, and the host logged `controls_recovered` at approximately **28.1 seconds of uptime** after starting its helper through local TLS ADB. Wi-Fi rejoined automatically at 5745 MHz with WPA3. No Mac helper-start command or fresh network-approval prompt was required during this test.

### Saved-network workaround

The Thor’s automatic network selection repeatedly chose a 7015 MHz (6 GHz) access point and timed out during WPA3 authentication. The connection that worked before reboot was on 5745 MHz (5 GHz), also using WPA3. With the user’s approval, that saved network was pinned to its previously working 5 GHz access point. Only its BSSID was changed; the password and security mode were preserved.

This trades roaming between access points on that saved network for reliable connection to the chosen access point. The original pin was unset. `thor-wifi-workaround/restore-roaming.py --network-id 3` removes the pin through authorized ADB. See that folder’s README and source; the setup-only tool is separate from Bluetooth controls.

The final development session preserves completed onboarding, the saved phone, automatic recovery and continuous monitoring. Manual Stop was verified for 35 seconds: the foreground service stayed stopped, saved monitoring intent remained false, and the continuous-monitoring preference remained true. Monitoring was then restored for handoff. The final iPhone logs confirm a successful fresh stats read, resumed live readings and updated widget snapshots.

## Deliverables

- `thor-monitor-test.apk`: Thor host 0.6.0.
- `thor-monitor-source.zip`: host source, build script, pinned dependencies, checksums, notices and relevant library sources.
- `thor-companion-iphone-development.ipa`: device-limited development build, including the battery widget and Live Activity.
- `thor-companion-android-debug.apk`: Android companion build.
- `thor-companion-source.zip`: companion source with signing-team selections removed.

The existing small WidgetKit battery widget still follows iOS’s refresh budget. Live Activity is the option for frequent visible updates. Screen-only display modes remain outside the current controls because full display/input-routing behavior has not been verified.
