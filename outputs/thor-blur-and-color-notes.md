# Locator blur, animation and Thor color — host 0.12.4

Host version 0.12.4 (19). The companion remains 0.12.3 (26), now installed on the development iPhone.

Find my Thor uses Android's cross-window blur behind its themed Stop panel on both internal displays. The panel fades/scales/slides into place over 220 ms while the backdrop blur and dimming reveal together. This respects Android's disabled-animation setting. If Android temporarily disables cross-window blur, the panel switches to a stronger dimmed backdrop; listeners and animations are removed when the panel closes. No screenshots or screen recording are used to produce the effect. Existing Stop behavior, audio fade, ten-second sound ramp and automatic sound timeout are unchanged.

New installs begin with **What color is your Thor?** followed by Bluetooth, background monitoring, control recovery, optional features and phone connection. The brief explanation reads: “Matches the host theme and app icon to your Thor. Change either later in Appearance.” Color choice is optional; Continue can retain the default. It changes only appearance, not model identification or controls. Existing completed setups stay completed, while saved progress in the previous five-step flow migrates to the corresponding permission step.

| Thor color | Initial host theme | Launcher icon |
| --- | --- | --- |
| Black | Dark | White handheld on dark background |
| White | Light | Dark handheld on pale background |
| Clear Purple | Clear Purple | White handheld on #6B5C87 |
| Rainbow | Rainbow | Four-color handheld on a light background |

For existing installs, open the host's **Appearance → Thor color & icon**, or Review setup. The normal theme picker remains independent, so you can later choose a different theme without changing the saved shell color or icon. Android activity aliases switch the launcher icon atomically with DONT_KILL_APP. The real MainActivity stays enabled/exported for existing explicit launch shortcuts. Some launchers cache icons, and Android's themed-icon mode may recolor the monochrome layer. The icon change applies to the launcher entry; Android's app-information screen may retain the application-level default icon.

Verification on the development Thor:

- Device reports native blur supported/enabled. Instrumentation confirmed two panels, a nonzero 37 px blur radius, initial-to-final entrance animation, final scale/opacity and fallback dimming. Rapid show/hide and listener/animation cleanup passed. The captured on-device image visibly blurs the host UI behind a sharp Stop panel.
- A separate freshly installed setup-check app verified all four color choices save the right theme and enable exactly one launcher alias, then Continue advances to Bluetooth setup without requiring a permission for color selection. All four color variants were captured. The test app was removed; existing host pairing/preferences were not reset.
- Pure Java color-mapping checks pass. Native host build/signature checks pass. The temporary instrumentation package/cache images are removed and normal monitoring is restored after testing.

Platform references:
- https://source.android.com/docs/core/display/window-blurs
- https://developer.android.com/guide/topics/manifest/activity-alias-element
