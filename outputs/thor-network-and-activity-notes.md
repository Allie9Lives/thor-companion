# Thor 0.10.0 — network files, activity, service lifecycle and sounds

## File access and setup

In Thor Monitor's **Wi-Fi file access** section, choose one of two scopes:

- **Full shared storage:** tap Allow full shared-storage access, approve Android's special permission and keep Share storage roots enabled. This exposes the top level of internal shared storage and the actual microSD volume. Android/data, Android/obb, other apps' private data and the system/root filesystem remain protected. No root or shell access is used for file operations.
- **Selected folders:** leave Share storage roots off and choose an internal folder and/or microSD folder with Android's document picker. Persistable grants cover those trees only. Android's picker deliberately disallows some storage roots; use the full-storage option if top-level shared storage is needed.

Start monitoring. In the phone's gear menu, open **Files over Wi-Fi / VPN**, then **Link file access over Bluetooth**. That explicit authenticated action enables the file server and saves its pinned identity and credential on the phone. Tap **Connect over network** and allow iOS Local Network access. Browse either drive, Upload from the phone's Files picker or tap a file to download and export it to Files. Files is also available under Controls → Open files.

Once linked, file access is independent of Bluetooth range. The Thor must still be powered on with monitoring and file access running. Use its Wi-Fi address on the same reachable LAN, or its existing Tailscale address/MagicDNS name when both devices already have a working VPN route. The app does not change Tailscale, VPN routes, ACLs, saved Wi-Fi security, port forwarding, accounts or router settings. It adds no Internet relay. Tailscale was not reconfigured or enabled during development; cross-network operation requires the user's existing VPN connectivity and policy.

Revoke file connection on the Thor disables access, closes active connections and rotates the credential for the next link. Disabling Enable Wi-Fi file access stops the server but retains its saved link. Forget saved phone on the Thor also revokes file access; Forget in the companion erases its own saved network credential. Changing permissions/scope is under the owner's control. The server does not publish credentials in URLs, logs, mDNS or a public web page.

## Transfer implementation

This is a companion file browser over **pinned HTTPS**, not a plaintext FTP daemon. It supports browsing and bidirectional file copies; it does not offer a general network shell, remote arbitrary commands, automatic destructive synchronization or silent overwrites.

TLS uses a P-256 key generated and retained in Android Keystore, with a stable self-signed certificate. Android's TLS private-key path requires DIGEST_NONE authorization because the TLS stack computes the digest. A random 256-bit bearer credential and SHA-256 certificate pin are delivered only through the existing authenticated, owner-restricted BLE control characteristic. The client has an empty trust store and accepts only the saved exact certificate fingerprint, before sending HTTP credentials. Redirects are disabled. iPhone credentials use a ThisDeviceOnly Keychain item; Android credentials use AES-GCM with an Android Keystore key.

The host listens on TCP 47183 while file access is enabled. Each request requires authentication, with bounded headers and a two-worker/bounded-queue server. Browsing has 200-entry pages; the current phone UI caps one directory listing at 10,000 entries. Uploads/downloads stream in chunks, with a 64 GiB file ceiling, I/O timeouts and bounded transfer wake locks. Keep the phone's transfer page open. Small exported/download/upload staging files use the phone's temporary directory; large files need enough phone storage for staging. Failed transfers remove their own partial output where possible. An OS/process crash can leave a hidden `.thor-upload-…` partial on the Thor; it is never treated as a completed file. There is no automatic resume in this version.

Shared-root paths are canonicalized and checked for containment, including symlink escape and protected app-directory rejection. SAF paths resolve only below the chosen tree through the document provider. Existing destination names are rejected rather than intentionally replaced; concurrent external filesystem changes can still cause a provider/move failure. File transfer completion is acknowledged only after writing/finalizing. A response that has started streaming is closed on failure, never followed by an error body that could be mistaken for file bytes.

Public distribution: MANAGE_EXTERNAL_STORAGE is a special permission and Google Play evaluates apps requesting it. The file-manager/device-transfer use must be explained and approved where required; this development build is not a store approval. Selected-folder mode remains available without broad access. See Android's [all-files access documentation](https://developer.android.com/training/data-storage/manage-all-files) and [document-tree limitations](https://developer.android.com/training/data-storage/shared/documents-files). iOS uses its [Local Network privacy declaration](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy).

## Focused apps and optional closed-lid warnings

The existing fixed, UID-restricted helper has a new read-only activity probe (protocol 4). It reads Android input-dispatcher focused applications for each display, the Thor's hall-switch state and process CPU counters. It accepts no package, PID, path or shell command from Bluetooth. Per-package CPU is normalized across all CPU cores and sampled about every 30 seconds; the first observation establishes a baseline. Two displays may show the same application. While asleep, Android can retain the last focused application, so the UI says current or last focused.

The hall switch is used for lid state. A sleeping screen alone never counts as a closed lid. Unsupported/unknown readings reset the closed-duration gate. After at least 10 continuous observed minutes closed, three consecutive high-activity observations can produce an event: focused-app CPU >=12.5% of total CPU capacity, device GPU >=30%, or an observed battery fall of at least three percentage points within a rolling ten-minute window while unplugged. Observation gaps over two minutes reset the duration/load evidence. An event has a 30-minute cooldown. This is a heuristic warning, not an energy attribution service or a claim that an app is defective. Per-app GPU and per-app battery energy are not available; the UI and warning explicitly distinguish device-wide GPU activity. No app is stopped automatically.

Enable **Activity after 10 minutes closed** under Battery notifications on the phone. It is off by default and requires the master notification setting and incoming Bluetooth readings. The app saves the last observed event to avoid replaying it on reconnect. Events older than 90 seconds in the host's own time base are not delivered as new notifications. Passive host sleep, Bluetooth range and phone background restrictions can delay or prevent delivery. There is no server push fallback. The performance card shows focused apps and sampled lid duration when the helper supplies valid data.

## App dismissal and recovery

The monitoring service explicitly has `stopWithTask=false`. Its foreground service, Bluetooth server and optional Wi-Fi server are independent of MainActivity. Removing the host UI task left the same monitoring process alive, logged `task_dismissed`, and samples continued. No automatic UI reopening was necessary.

**Recover after app dismissal** is available during onboarding and later under Background monitoring. It adds a bounded system-alarm recovery attempt if the service is interrupted while monitoring is still wanted; Android controls actual delivery timing and background-start eligibility. START_STICKY remains the normal process-recreation path. Manual Stop saves monitoring-off and prevents the extra recovery. Force-stop, revoked permissions and Android's explicit app-stop restrictions are not bypassed. Continuous closed-lid monitoring still uses the user's existing optional wake-lock setting.

## Notification names and audio

Battery and activity notification titles use the configured device name from the Thor, with the saved device name as fallback. The connected device reports `Allie's AYN Thor Max`; that name is not hardcoded.

Sound cues are short edited variations from the user-supplied Tranquility pack: Bell Pulse for the locator, Tweeting Notification for positive battery events and Lone Bell for warnings/disconnection. The locator retains its gradual ramp, 60-second limit, Stop notification and alarm-volume restoration. iOS bundles native WAV notification resources; Android uses separate status/warning channels so users can control them in system settings. OS notification/Focus/sound settings still apply. See [sound credits](thor-sound-credits.md) for authors, source, CC BY 4.0 and modifications; credits are also in both apps.

## Verification in this version

- 80 Flutter tests passed; analyzer clean. Added TLS pin-before-credential checks, streamed file byte roundtrip, invalid connection handling and configured-name notification tests.
- Pure Java tests passed for closed-duration/sustained-load/unknown-lid/drain gates, normal standby drain suppression and observation-gap resets, plus shared-root containment, traversal/symlink escape, protected directories and invalid filenames.
- Physical Thor probe passed pinned-TLS 1 MiB+17-byte upload/download on both actual drives, rejection of an existing name without modifying its bytes, unauthenticated rejection, path boundaries and stable TLS identity/credential after server restart. Test files and the temporary instrumentation package were removed. Keystore TLS compatibility was tested and corrected before delivery.
- Locator resource played during a short native test and stopped normally. The owner confirmed focused-app display, iPhone download/export to Files, and uploads from Files to both actual storage roots while the Thor was closed. The resulting test document hashes matched on both drives. The native hall switch changed from 0 open to 1 closed. The ten-minute alert gate is covered by policy tests; a real ten-minute load/drain notification was not forced.
- Removing only Thor Monitor's UI task through Android's task service preserved its process and continued sampling. Other app tasks and Tailscale settings were not changed. Full process force-stop bypass and another real device reboot were not tested or promised.

The first iPhone file export failed because the legacy app-delegate window is nil in the scene-based app. The bridge now presents from the active UIWindowScene. Actual download/export and upload picker checks passed after that fix. Duplicate-name uploads are rejected with a direct explanation in the phone UI; the original test document in Internal initially caused the expected conflict, and a fresh-name Internal upload succeeded.

## Locator sound refinement — host 0.10.1

Removed the source recording's long inter-variation silence and restored the second cue's natural decay. Cue onsets are 2.23 seconds apart rather than four seconds. Both cues have smooth tail fades and are normalized to 95% peak for a modest, consistent level increase. The gentle 20-second volume ramp, automatic stop, notification Stop and volume restoration behavior are unchanged. Companion remains 0.10.0.
