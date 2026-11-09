# Host icon and battery widgets — 0.12.2

Host version 0.12.2 (17), companion version 0.12.2 (25).

The Thor host now declares an adaptive Android launcher icon with the same dual-screen handheld motif as the companion. It includes a round-mask mapping and Android 13 monochrome/themed-icon foreground. The icon is drawn from vector resources; no extra image or runtime permissions are needed. The native resource linker now permits the icon's new color resource when merging the compiled resources.

The existing Thor Battery widget kind now also supports the small Home Screen widget, retaining existing Lock Screen placements. Add it by long-pressing the iPhone Home Screen → Edit → Add Widget → search Thor → choose Thor Battery → Add Widget. Open the companion and receive a reading first.

The Home Screen widget shows an exact circular charge ring, a dual-screen device glyph, numeric percentage and a plug symbol while the Thor reports charging. The ring is red at 20% or less when not charging and otherwise green. It adapts to system light/dark backgrounds; iOS can recolor widgets in its tinted/clear modes. Missing readings show an empty ring and an instruction to open the companion, while stale/disconnected readings are labeled last known.

Lock Screen rectangular, inline and circular widgets and the Live Activity now choose battery.0/.25/.50/.75/.100 from the received percentage. The plug is separate, so charging at a low percentage no longer appears as a full battery. The smallest Dynamic Island minimal view continues to prioritize numeric percentage. Charging follows the Thor's actual charging status, not merely cable presence; full or bypass-powered states do not falsely claim active charging.

All widget forms use the existing shared private cache and the same WidgetKit update policy. This does not change iOS refresh scheduling or add notifications after force-quit. The canceled internet-push proposal remains unimplemented.

Verification: native snapshot tests cover every quarter-fill boundary, exact ring fractions, charging retaining the correct fill, clamping, freshness and cache encoding. Actual SwiftUI views are rendered with isolated synthetic data in an iOS simulator for low/half/full/charging/last-known/empty states and the battery symbols. No synthetic readings are written to the phone's real widget cache. Android icon declarations and adaptive resource packaging are verified in the built APK. Production host and client builds are installed without resetting pairing or settings.
