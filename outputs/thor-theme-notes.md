# Companion 0.11.0 — Clear Purple and Rainbow

Open the client's gear menu → Appearance. Existing System default, Light and Dark choices remain available.

- **Clear Purple:** base color exactly `#6B5C87`, deep purple background/cards and light lavender text/highlights.
- **Rainbow:** white base, blue primary controls, yellow/green/red performance accents and a thin four-color header detail. Text retains its neutral foreground colors; warning and shutdown styling remains recognizable.

The choice is stored using the existing appearance preference. Previous `system`, `light` and `dark` values continue to load; `clearPurple` and `rainbow` are new named values. Unknown values fall back to System default. Changing themes retains the same connection/controller and current readings.

The palette is a ThemeExtension, so shared cards, dialogs, sheets, sliders, switches, navigation and secondary pages follow the selected colors. Clear Purple is a dark palette; Rainbow is light. Dark remains the separate neutral dark theme. The host app and native Lock Screen widget/Live Activity appearance are unchanged.

Actual Flutter renders were inspected for both themes, including performance/storage. Added checks cover the exact purple color, text/button contrast above 4.5:1, showing both named choices and switching back to Dark without replacing connection state. The existing light/dark checks remain in the suite.
