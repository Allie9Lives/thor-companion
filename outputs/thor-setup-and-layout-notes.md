# Host 0.10.2 / Companion 0.11.1 — setup and layout

The client no longer displays the obsolete monitoring-session / ten-minute-test notice in Device. The optional alert for activity after ten minutes with the lid closed remains; it is a different feature.

The battery gauge grows from 80 to 112 logical pixels, with a larger charge symbol and a 20-pixel inset from the card's right content edge. It remains hidden on narrow/high-text-scale layouts where the readings need the space. Text sizes and the existing themes are retained.

Device's CPU and Model detection rows stay on one line. Labels use natural width rather than taking half the row; the CPU has the remaining width. Model detection is shortened to Processor + RAM, with its full inference description in a tooltip. On narrow screens with large accessibility text, overly long values use ellipsis rather than wrapping or shrinking to tiny type; long-press exposes the full value.

## First-install host setup

Setup now has five screens:

1. Bluetooth access: allow Nearby devices and turn Bluetooth on. Continue checks both before advancing.
2. Background monitoring: notification permission, unrestricted battery settings, the explicit CPU/battery tradeoff for closed-lid monitoring, start after restart and dismissal recovery.
3. Controls recovery: optional local Wireless debugging pairing and permission setup, with clear recovery status. Monitoring can be set up first.
4. Optional features: full shared-storage access or selected folders for file transfers, and enabling/selecting the remote keyboard. These features are not required to finish monitoring setup and remain available afterward.
5. Phone connection: tap Start monitoring on the Thor first, then scan/connect from the phone and approve pairing prompts. The lid-open and pairing-notification instructions remain visible.

The flow preserves partially completed progress. Existing installations keep setup_complete, pairing, permissions and preferences; Review setup starts the guide again without erasing them. Manual Stop and all recovery preferences are unchanged.

## Verification

The source built and the five screens were exercised on a separate fresh package, Thor Setup Check, on the physical Thor. Only that test copy received temporary Nearby-device grants to navigate the flow. It never started monitoring or paired a phone. It was uninstalled afterward; the existing host's data was not cleared. This verifies fresh screen progression, including optional features and the final Start action layout, without resetting the owner's installation. System permission/pairing dialogs were not all re-exercised from scratch in this pass; their underlying actions were retained from the previously tested setup.

Flutter analyzer passed. The 82-test suite passed before the extra layout assertions; the updated eight widget/render checks also passed, including one-line CPU/model values and no obsolete timer notice at narrow width with enlarged text. Dark/light battery renders were visually inspected. Android companion, signed iPhone companion and native host builds passed. Source archives and development artifacts were refreshed.
