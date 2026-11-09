# Thor 0.6.1: identification, memory check, update recovery

AYN's current official configurations: https://www.ayntec.com/products/ayn-thor

- Lite: Snapdragon 865, 8 GB RAM, 128 GB storage.
- Base: Snapdragon 8 Gen 2, 8 GB RAM, 128 GB storage.
- Pro: Snapdragon 8 Gen 2, 12 GB RAM, 256 GB storage.
- Max: Snapdragon 8 Gen 2, 16 GB RAM, 512 GB or 1 TB storage.

The current Batch 7 listing specifies UFS 3.1. The connected older Max actually reports descriptor 0x0400 (UFS 4.0). Never derive UFS from the tier or current sales listing.

Host inference requires a Thor Android model, a recognized SoC (including the connected firmware's QCS8550 alias for this Thor's Snapdragon 8 Gen 2), and a measured physical RAM band allowing Android's reserved RAM. Unknown or conflicting configurations remain unidentified. Internal data capacity is matched separately to nominal capacities with partition overhead tolerance; neither available space nor microSD determines the model. This is hardware inference, not an OEM SKU identifier.

The connected unit: Max, 15,996,096,512 bytes physical RAM, 1,011,194,642,432 bytes usable internal partition, 1 TB nominal configuration. Its configured Android device name is shown as the heading; AYN Thor Max appears immediately underneath. No device or Bluetooth name is changed. Hardware metadata refreshes on reconnect and every five minutes of successful telemetry, so later device renames propagate to the saved entry.

## Memory inspection before updating the host

Read-only Android dumpsys meminfo and /proc/meminfo snapshots:
- Total physical RAM: 15,621,188 KiB (14.90 GiB).
- Available: 9,183,864 KiB (8.76 GiB); completely free: 2,729,448 KiB.
- File cache: 4,569,536 KiB; reclaimable kernel memory: 2,172,908 KiB. These categories must not all be summed indiscriminately.
- Host PSS: 54,220 KiB (52.9 MiB); helper: 40,547 KiB (39.6 MiB). Combined about 92.5 MiB, 0.6% of physical RAM.
- Later same-process sample: host 48,866 KiB; helper 40,559 KiB. No growth pattern observed in this short interval; this is not a long-duration leak guarantee.
- Largest PSS entries: Android system 328 MiB, Cocoon launcher 300 MiB, Wallpaper Engine 262 MiB, Google Play services 240 MiB; then Chrome, Play Store, Spotify, Reddit, keyboard and System UI. Shared libraries are apportioned in PSS; raw RSS totals double-count them.

The measured state was not low on available RAM. Cached/reclaimable memory and multiple resident apps explain much of the difference between completely free and available memory. Our processes were a small fraction of usage. No user apps were killed or caches cleared for this investigation.

## Refresh recovery

The previous controller could drop a heartbeat-triggered refresh during a controls transaction and otherwise waited until the 90-second stale threshold before repairing a silent subscription.

- Foreground watchdog now rediscovers, reads and resubscribes after 45 seconds without a successful update (host normally publishes every 30 seconds).
- Recovery attempts are bounded to at most one start every 15 seconds; failures retain the existing reconnect/backoff and manual service-cache recovery rules.
- Heartbeat refreshes arriving during control transactions are coalesced and run after the transaction finishes, preserving serialized BLE access.
- Foreground resume still refreshes automatically. No new Dart background polling is introduced; iOS suspension/force-quit limits remain.
- No GATT service/characteristic ordering changes, pairing reset, wireless debugging identity changes, or Wi-Fi changes.

Regression checks cover all model tiers, unknown hardware, capacity matching, a silently stalled stream, no background watchdog polling, a healthy stream with no extra reads, control/heartbeat overlap, optional metadata and legacy hardware compatibility.

## Installed-device verification

Both devices updated to 0.6.1 (companion build 14, host version code 8). The companion automatically connected and parsed Max / 1 TB / configuredName=true at 03:13:22 UTC. A subsequent native ATT interruption at 03:13:50 recovered automatically by 03:13:54 with no swipe or pairing reset; scheduled readings continued at 03:14:10 and 03:14:40. This confirms actual reconnect recovery and continued notifications; the simulated silent-stream path is covered separately by regression tests. Final Flutter suite: 48 passed; analyzer clean; native model tests passed. iOS app signature verified, source/APK/IPA artifacts refreshed, and widget extension retained.
