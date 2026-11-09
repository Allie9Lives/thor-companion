# Thor Monitor 0.13.0 — local Overview and locator dismissal

## Host screens

The host's landing screen now follows the companion Overview layout and current host theme: configured device name and model, battery percentage and gauge, temperature, voltage, USB input watts, measured runtime estimate, CPU and GPU usage with chip names, RAM, focused apps, internal storage with UFS version, and separate microSD capacity. Missing readings remain unavailable.

Battery insights opens directly on the Thor. It uses the existing private seven-day battery database and provides 24-hour/seven-day battery-level graphs, observed hourly battery use, recorded coverage, sampled screen-on time, time connected to power, peak temperature and raw firmware diagnostics. It does not require Bluetooth or a connected phone. Graphs leave recording gaps blank; runtime requires a contiguous unplugged segment with at least four samples, 15 minutes and a two-percentage-point drop. It is an estimate of recent usage, not a guaranteed remaining time or calibrated battery-health measurement.

The foreground screen reads telemetry on a worker every two seconds while resumed. Local history reads are cached for 30 seconds. Existing history sampling remains roughly five minutes plus power and screen-state changes, without new synthetic history or per-app probes. Monitoring, permissions, appearance, recovery, optional features and Review setup remain under gear → Host settings. All four themes, first-run color selection and launcher icons remain available. No duplicate remote Controls page was added to the host.

## Locator exit

Normal Stop animates the panel's opacity, scale and position while reducing both blur radius and backdrop dimming over 220 ms. Sound cleanup no longer removes the panel early; the sound retains its own gentle fade and prior-volume restoration. Each exit cleans up its own window, so dismissing and immediately starting again cannot remove the new panel. Interrupted entrance animations start exiting from their current visual state. Disabled system animations use immediate cleanup; a delayed fallback prevents an invisible window lingering if display frames stop. Service teardown still removes windows immediately.

## Verification

- Host 0.13.0 (20) built, APK signature verified and installed on the connected Thor.
- Pure Java battery tests cover runtime, charging, insufficient history, recording gaps, measured coverage and hourly allocation.
- Device instrumentation verified both screens' exit, falling blur and dim, duplicate Stop, early Stop and rapid restart. A deliberately slower test-only exit verified that audio completion cannot truncate the visual exit. No system animation setting was changed.
- Actual native Overview and Insights views rendered in Light, Dark, Clear Purple and Rainbow, plus narrow content at 2× text size and unavailable readings. Render fixtures did not write production history or change the selected theme.
- On-device navigation verified live readings, existing history, both graph ranges, diagnostics and Host settings. Monitoring was restored and temporary test packages removed after instrumentation.

The companion remains 0.12.3; no client protocol, pairing, Wi-Fi, VPN or remote-control behavior was changed for this host UI update.
