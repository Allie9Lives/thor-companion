# Companion 0.11.2 — aligned values and long-press copy

Device details now use a shared left-aligned value column, including Model detection. The CPU display uses the compact chip name (for example Snapdragon 8 Gen 2) to keep it on one line; the copied report and accessibility label retain the full vendor/model name.

Long-press anywhere in a main stats card to copy that card's readings as readable text. Supported cards are Overview Battery, Performance, Internal storage and microSD, plus Device information, Firmware and Battery diagnostics. Card padding, the battery gauge and text values all respond. A short confirmation appears after copying. Button/slider behavior is unchanged.

Reports include the device name, units, full field values and, for live readings, sample time and last-known status where applicable. Demo reports are labeled. Missing readings remain unavailable; no Bluetooth identifiers, saved network credentials or recovery keys are included. Copying uses the phone's local clipboard and sends nothing to a server. Firmware is copied as a complete card; text selection/tooltips no longer intercept that card gesture.

Widget checks cover copying from card padding and text, copying from the battery gauge, full untruncated hardware values in the copied report and shared alignment of CPU/Model detection/GPU values. The existing narrow-screen, large-text and theme checks remain.

Feature ideas discussed separately: saved control profiles (recommended next), queued/resumable transfers, usage-based runtime estimates and a consolidated connection-health page. These ideas are not implemented by this update.

Verification: 85 Flutter tests pass and the analyzer is clean. Android arm64 and signed iPhone builds are generated from this version; earlier iOS generated plugin build artifacts needed regeneration before delivery.
