# Hardware test results — November 4, 2026

## Verified

- App compiled, APK signature verified, installed and launched on Android 13 Thor.
- BLE advertising and GATT connection from iPhone using nRF Connect succeeded.
- Authenticated Bluetooth pairing succeeded after opening the Thor's pairing-request notification. Earlier requests timed out when not confirmed.
- Encrypted Battery Level reads succeeded; app recorded authorization of the first bonded phone.
- Custom stats, live status, and hardware characteristic reads succeeded. Observed response sizes were 216, 9, and 246 bytes respectively.
- Ordinary app access to storage model `KLUGGARHHD-B0G1` and UFS descriptor `0x0400` succeeded. This device's UFS 4.0 classification does not require root or ADB.
- Live status notification subscription was enabled at 12:45:09 local time.
- At 12:45:33 the app sampled with `interactive=false` and `plugged_code=0`, then queued and completed a notification with success status 0 (sample sequence 35).

## First five-minute closed-lid, unplugged test

The owner reported that nRF Connect remained connected but its value stopped changing. App logs confirm that notifications were enabled, rather than this simply being a failure to subscribe.

- 12:45:33: timer sample sequence 35, battery 67%, not interactive, unplugged; notification success.
- 12:45:33: screen-off broadcast and sample sequence 36.
- No app sample events for approximately 316.9 seconds.
- 12:50:50: screen-on broadcast and sample sequence 37, USB power present.
- No intervening GATT disconnect event was recorded in the retrieved log.

Conclusion: the initial no-wake-lock prototype did not maintain periodic app sampling during this unplugged sleep interval, despite retaining its BLE connection. This is consistent with CPU suspend. It does not establish that BLE on-demand reads fail, that a wake lock is required for every product mode, or that a permanently active mode would have acceptable power consumption.

## Follow-up attempt at on-demand reads

The owner reported a complete disconnect during a second closed-lid, unplugged test. Logs show screen-off at 12:52:11, no fresh app samples until 12:54:02, and a disconnect event delivered at 12:54:00 near USB reconnection. No successful unplugged read was logged in that interval. A later battery read succeeded while plugged in with the screen off. The precise cause and timing of the radio disconnect are not established by these app callbacks, which themselves can be delayed by suspend.

## Version 0.2 test preparation

Added an explicitly selected, 10-minute partial-wake-lock test mode, with visible notification, countdown, Stop control, automatic service stop, OS wake-lock timeout, and release in service teardown. Passive mode remains available. Sampling uses fixed delay so it does not attempt a burst of catch-up tasks after delays. This tests the suspend hypothesis and has not yet established unplugged reliability or battery cost.

Version 0.2 compiled, its APK signature verified, and the upgrade installed. After the owner started the timed test and closed the lid, Android power diagnostics showed `mWakefulness=Asleep` and an acquired `PARTIAL_WAKE_LOCK` tagged `com.alan.thormonitor:ClosedLidTest`. App samples 3, 4, and 5 reported `interactive=false` and `wake_lock_held=true`, while plugged in.

## Successful unplugged timed test

The owner restarted the timed mode at 13:02:42 and reported watching the iPhone counter advance from `n=24 b=69` to `n=35 b=69` while the Thor was closed and unplugged and nRF Connect remained visible.

The retrieved logs independently confirm:

- Samples 24 through 36, inclusive, ran from 13:03:06 through 13:09:07 local time: **13 consecutive samples over approximately six minutes**.
- Every one of those samples recorded `interactive=false`, `plugged_code=0`, and `wake_lock_held=true`.
- Each sample was followed by a successful custom Live status notification queue result (`result=0`) and completion callback (`status=0`). No disconnect was recorded in this interval.
- Intervals stayed approximately 30 seconds apart.
- USB power was present again in sample 37 at 13:09:22.
- The integer battery readings were 69% during the unplugged samples, 68% immediately after reconnecting, then 69% while charging. The short interval, coarse percentage readings, and delayed charge-state updates do not support a reliable battery-drain estimate.

After collecting the logs, the Stop monitoring button was exercised through the app UI. The app logged `wake_lock_released` and `stopped`; a fresh Android power dump confirmed that the test's wake lock was absent from the live wake-lock list. Stop-button cleanup is verified. Automatic ten-minute expiry has not yet been exercised end-to-end.

**Conclusion:** BLE delivery to the foreground iPhone diagnostic client works with the Thor closed and unplugged during the bounded CPU-awake test. The baseline without a wake lock failed to sustain sampling. Long-term power cost, reliability over hours, reconnection, behavior under additional power-saving modes, and iPhone background delivery are not yet validated. This is feasibility evidence, not a claim that all closed-lid operation is solved.

## Original on-demand test procedure

With USB disconnected and the lid closed for at least one minute, manually read the Live status characteristic from the iPhone, repeating after 30 seconds. Determine whether a fresh sequence is returned without opening the Thor. This tests whether a client can request fresh stats on demand while the Thor otherwise sleeps.

Continuous fixed-interval updates, on-demand reads, iPhone background behavior, reconnection from suspend, and battery cost require separate validation. No wake locks or global sleep changes were added during the first test.

## Reconnection investigation and host 0.3.1

At 14:36, logs recorded only 22 response bytes for custom stats reads, rather than the complete JSON value. The original implementation clipped responses using an app-maintained MTU map that defaulted to 23 after a server restart. Android already knows the connection’s actual MTU; the app’s extra clipping could cause the central to accept a short, incomplete JSON value. The response callback now passes all remaining bytes to Android and retains stable read-offset snapshots.

Host 0.3.1 compiled, signature verification passed, and it was installed. The Mode label was verified as Stopped before service start and Passive monitoring after tapping Start passive monitoring; sample logs confirmed the service was running. The owner’s earlier repeated passive-button taps also appeared in the logs, confirming that the old combined status label had obscured a working button.

## Host 0.4.0 performance and microSD verification

The APK compiled, passed signature verification and was installed on the Thor. Its unprivileged app process recorded valid GPU, RAM and microSD fields in its own diagnostic sample, without additional permissions. The first CPU reading was null as intended; after 30 seconds the timer sample reported CPU 7.4% across a 30,009 ms window and GPU 2%. RAM available was 9,738,153,984 bytes. The mounted SD card reported 511,801,556,992 usable bytes total and 260,961,730,560 available bytes. The SD mount maps to a block device whose sysfs type is SD. Root access was not used by the app.

CPU counter regressions passed for initial warmup, short intervals, idle, full busy, I/O wait, guest double-count avoidance, reset and unreadable input. The expanded stats packet was estimated at approximately 368 bytes from the actual initial sample, below the GATT attribute limit. End-to-end companion confirmation follows in its VALIDATION.md.

## Resumed verification — November 5, 2026

After restarting the expired timed session, the companion connected, read the expanded stats and hardware values, and enabled Live notifications. Host response logs report 373 bytes for stats and 246 bytes for hardware, both sent successfully. The owner confirmed the new readings display correctly in the companion. The ten-minute automatic stop was also observed in the previous session's logs (`active_test_expired`, then `stopped`).
