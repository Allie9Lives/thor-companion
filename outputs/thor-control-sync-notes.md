# Companion 0.7.1 — linked sliders and responsive controls

- Brightness/volume previews are shared by both sliders while their sync option is on, including throughout the drag before any BLE command is sent.
- Enabling sync aligns both screens to the current top-screen value. Dragging either slider then controls both. Turning sync off restores independent adjustment.
- Ordinary controls remain interactive during telemetry reads and control writes. Their requested values display immediately until device readback confirms them or reports an error, at which point the actual values are shown.
- BLE transactions remain serialized. New changes wait behind any current transaction. Repeated unsent changes to the same setting/target coalesce to the latest value, retaining chronological order across different settings/targets. An already transmitted command is never retried automatically. Disconnect discards unsent settings rather than replaying them after reconnect.
- A small progress indicator replaces the global disabled appearance during setting changes. Offline, stale, unsupported or unauthorized controls still disable appropriately.
- Removed the unconditional 500 ms settle delay. Acknowledgements are read immediately; if acknowledged values are still settling, only the readback is retried at 100 ms intervals, at most three times. Existing value tolerances and error reporting remain.
- Refresh buttons use the serialized telemetry/controls refresh path to avoid concurrent BLE reads. Keyboard input retains its separate explicit-send/no-replay behavior.

Verification: 58 Flutter tests passed and analyzer clean. Tests cover linked preview and release, sync enable alignment, controls remaining enabled during both reads and writes, ordered/coalesced queued values, and cancellation on disconnect. Android companion APK and signed iPhone build rebuilt. Thor host is unchanged at 0.7.0; companion version 0.7.1 build 16, including the battery widget extension.
