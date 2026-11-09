# Thor Monitor 0.14.3 — host UI polish

The host's six setup steps now use consistent icon badges, short titles and descriptions, a six-segment progress indicator and numbered phone-pairing instructions. Back and Continue remain in a fixed footer. The scrolling content has a separate viewport above that footer, including at large text sizes. Step transitions respect Android's animation setting. Granted permissions display a compact status instead of duplicate disabled buttons.

Optional features expand individually. Settings uses matching expandable sections for Appearance, Monitoring, Find my Thor, Wi-Fi access, Controls recovery and Phone keyboard. Longer explanations remain under setup help or About battery saving. Attribution and linked sound-pack/license details are in Sound credits at the bottom. Content widths, card spacing, icons and button styling follow the existing themes.

Recovery opened from setup returns to the same step, including Review setup on an existing install. Its origin is retained through activity recreation. Permission checks, user choices, pairing, host monitoring, control packets, power policy and file access retain their existing behavior. The companion remains 0.14.0.

Verification:

- Native build and signature checks passed.
- Device render checks covered all six steps in Light, Dark, Clear Purple and Rainbow, plus narrow content with 1.8× text and the Settings, Recovery and Battery saving pages. The fixture intercepted preference writes and restored resource configuration; it did not change system text settings, permissions, theme or pairing.
- A separate fresh-install copy verified the initial color screen and Bluetooth permission action with no permissions granted. The fixed footer remained visible. The temporary copy was removed.
- Review setup navigation checks covered all six steps, the return from Recovery and optional-feature expansion. Normal monitoring was restored after checks.

The render regression source is `tests/device/HostSetupRenderTest.java`. Android instrumentation is required for the actual native layout and resources.
