# Settings, locator and host themes — 0.12.3

Host version 0.12.3 (18); companion version 0.12.3 (26).

Find my Thor now starts at gain 0.035 instead of 0.02 and reaches full amplitude after 10 seconds instead of 20, following the same quadratic curve. The sound asset, peak limit, automatic 60-second stop, 220 ms stop fade and prior-volume restoration remain in place.

Client settings now use an equal-size tile grid: Appearance, Battery widgets (iOS), Battery notifications, Battery insights, Files and Connection health. Automatic reconnection is a separate, clearly labeled switch. Appearance opens a tile picker. Connection help is the penultimate row and Sound credits is last. Icons/title areas align between tiles, including the existing Controls tools. The widget guide now includes Home Screen instructions. The main Overview/Device/Controls organization is retained; an Internal storage heading overflow at 2× text size was corrected.

The host's Appearance chooser now offers Light, Dark, Clear Purple and Rainbow, plus System default. Clear Purple is dark and uses the companion's plum/lavender colors; Rainbow has a light base and gold/green/blue/red accents. Host screens and locator overlays share one palette. The overlay follows the saved theme, refreshes when it changes during playback, and follows system appearance changes while System default is selected. The appearance chooser scrolls on short displays and with larger text. No new permissions or pairing reset are needed.

Verification: all 99 Flutter tests pass and analysis is clean. Four-theme settings renders were inspected with legible iOS system fonts; tests check equal tile dimensions, footer order, navigation and narrow 2× text layout. Java tests verify locator timing/endpoints/monotonicity, the existing stop fade, all four palettes, system selection and text contrast. On-device native rendering verified overlay background and Stop-button colors for each host palette, with images inspected for Clear Purple and Rainbow. The temporary test package/cache files were removed and normal monitoring restored.

The Thor update is installed. The iPhone was reconnected and the signed 0.12.3 client was installed and launched. No claim of an on-phone visual/listening test for this version is made until that check occurs.
