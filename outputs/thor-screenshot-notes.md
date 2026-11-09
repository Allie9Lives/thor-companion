# Thor screenshots — 0.8.0

## Use

In the companion, open **Controls → Open screenshots**. Choose **Top**, **Bottom**, or **Both**, then **Capture & save**. Leave the Thor open/unlocked and the client on the capture page until transfer finishes. On iPhone, allow adding to Photos at first save. If permission is denied, the received preview stays in this page and **Save to Photos** can be retried after permission is changed.

Images save only on the client: iOS Photos with add-only access; Android 10+ Pictures/Thor Companion through MediaStore. Both captures are stacked top above bottom, preserving each screen's original pixels. The smaller bottom screen is centered on black padding. The two display captures are sequential, not an atomic simultaneous frame. Protected content follows Android screencap restrictions.

## Thor storage and capture

The existing shell-UID controls helper runs fixed `screencap -p -d <physical-display-id>` commands without a filename, reading stdout directly into bounded memory. Logical internal displays are mapped to physical IDs at capture time rather than hardcoding the test unit's IDs. The helper's local socket verifies the host app UID; the host verifies shell UID. No arbitrary shell commands, filesystem paths, image filenames, HTTP server, or Wi-Fi transfer is exposed.

One capture container (maximum 12 MiB) stays in RAM until delivery, cancellation/disconnect, service shutdown or a 300-second expiry. Delivery uses a bounded 300-second wake lock if necessary. No image is written to the Thor's files, Photos/gallery, storage, or diagnostics. The screenshot-capable helper was loaded through the existing automatic recovery after upgrading the test device; pairing, recovery identity and user monitor preferences remain intact.

## Bluetooth transfer

Reuses the existing encrypted, paired-owner-only controls and live notification characteristics. No service or characteristic is added/reordered, preserving existing GATT handles. Capture metadata includes a random transfer token, byte count and CRC32. Each binary notification has a versioned header, token, exact offset and total length, followed by MTU-bounded data. The notification sender serializes normal telemetry and screenshot packets with one outstanding notification, using Android delivery callbacks for pacing.

The client rejects missing/out-of-order packets, size inconsistencies, checksum failures, unexpected PNG data and oversized image dimensions. Late packets from a previous token are ignored. There is a 12-second idle timeout and 300-second transfer limit. No capture is automatically retried/replayed after an uncertain result. Client auto-lock is suspended only during transfer and restored at completion, error, cancellation or page exit. Disconnect and cancellation clear buffers; normal telemetry resumes afterward. Pixel data and typed text are not included in diagnostics.

Native screenshot source uses Android's documented stdout capture behavior: https://android.googlesource.com/platform/frameworks/base/+/master/cmds/screencap/screencap.cpp
Client Photos save uses add-only PHPhotoLibrary changes: https://developer.apple.com/documentation/photos/phphotolibrary

## Verification

- Real Thor in-memory capture: top 1920×1080, bottom 1240×1080, and both. Capture times observed ~0.4–1.1 seconds; combined container ~2.48 MB for the test screen content. No image file was created on the Thor by the probe.
- Java packet tests: exact payload reconstruction at multiple MTUs, CRC and bounds/error cases.
- 64 Flutter tests passed; analyzer clean. New tests cover CRC32, binary reconstruction, stale-token/duplicate handling, corruption/missing packet rejection, exact top/bottom PNGs, centered lossless stitching, controller transfer completion, cleanup and cancellation without replay.
- Host 0.8.0/version code 10 and companion 0.8.0/build 17 compiled, signed and installed. The iOS battery extension remains included. Installed-device check confirmed a full-resolution top screenshot saved to iPhone Photos (1,665,497-byte PNG). Transfer took approximately 85 seconds; the overall limit was extended to five minutes for larger stitched images while retaining the 12-second idle timeout. Final stitched save verification completed on November 7, 2026: the iPhone received mode=2 (2,456,864-byte container) and saved a 4,454,348-byte stitched PNG to Photos. The user confirmed the image contains both screens. That transfer took about 36 seconds. The Thor logged capture-buffer release, its screenshot wake lock was no longer active, no image files appeared in its app directory, and regular telemetry/widget updates resumed. The final iPhone build includes transfer-only auto-lock prevention and the five-minute overall allowance.
