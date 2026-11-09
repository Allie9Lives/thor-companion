# Connection health, runtime and Wi-Fi screenshots — 0.12.0

## Using the update

Tools now has six equally sized buttons, including Connection health and Battery insights. Connection health reports Bluetooth subscription, reading age, reconnection state and last scan signal strength. The optional authenticated network check reports host version, monitoring, Wi-Fi and advanced-controls recovery. Check timestamps distinguish the last check from live telemetry. No network credentials appear in the report.

The battery card and Battery insights show a remaining-runtime range once at least 15 minutes of continuous unplugged observations and a two-percentage-point drop are available. This is a recent-use estimate, not a calibrated battery-health measurement. Charging, long gaps or insufficient data show explanatory states. Workload changes can change the range.

Screenshots now require Wi-Fi and the existing paired, certificate-pinned HTTPS connection. Open Screenshots, link network access over Bluetooth once if needed, then Check Wi-Fi. Select Top, Bottom or Both and Capture & save. Keep the Thor open and unlocked and advanced controls ready. Allow Photos access on the phone. No image bytes are transferred over Bluetooth; older Bluetooth capture commands are rejected by this host. Storage-folder permissions are only needed for file browsing, not screenshots. Images stay temporarily in Thor RAM and are saved on the client. Existing VPN configuration is not changed.

For a Stop button in front of other apps, open Thor Monitor → Find my Thor → Allow Stop panel over apps and allow Android’s display-over-other-apps permission. The optional Show Stop button over apps switch can be changed later. A panel appears on each available internal display only while the locator sounds. Android may hide overlays on protected screens. The phone and notification Stop actions remain available. A normal Stop fades the current sound over 220 ms before releasing audio and restoring the previous alarm volume; destruction or audio-focus loss stops immediately.

## Verification

Host instrumentation on the development Thor verified authenticated HTTPS status, rejection without authentication, all three THS1 capture modes, legacy Bluetooth capture rejection, two visible Stop panels, actual Stop-button click, the fade interval, audio release and prior-volume restoration. Local on-device TLS capture took about 0.36–1.28 seconds; these are not phone-over-Wi-Fi timings. The temporary test package was removed and normal monitoring restored.

Static analysis is clean and all 93 client tests pass, including large-text Tools sizing and disabling capture without network credentials. Both client builds succeeded; the signed iPhone build was installed and launched. Phone-over-Wi-Fi save and listening checks await user confirmation.

Client tests cover contiguous discharge estimation and charging/gap handling, authenticated streamed network capture with progress, TLS pin verification before sending credentials, composition, controls and existing functionality. A real discharge-duration accuracy study has not been performed. Runtime should be treated as an estimate.

## 0.12.1 follow-up

User confirmed Wi-Fi stitched capture saves to Photos and the frontmost Stop panel/fade works. Stitched PNGs now leave unused side padding transparent while preserving screen pixels. A pixel-level composition test verifies zero alpha on both sides of the narrower screen.

Locator start, host-panel/notification Stop, automatic timeout and audio-focus loss now wake the existing authenticated live-update path. The host reports optional `locator_active` in readings, and the client reconciles its locator button from received state. This adds no sound-command replay and works independently of the Controls page polling flag. The host event queues a notification without sampling telemetry on the sound-fade handler. Old hosts omit the optional field and retain their existing readback behavior.

The 0.12.1 client passes all 94 tests with clean static analysis. The host patch was built and installed, and its foreground monitoring service resumed automatically.
