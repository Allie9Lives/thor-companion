<p align="center"><img src="docs/assets/header.svg" alt="Thor Companion — Your Thor, on your phone." width="100%"></p>

<p align="center">Battery, system stats, and remote controls for your AYN Thor.</p>
<p align="center"><a href="https://github.com/Allie9Lives/thor-companion/releases/latest"><strong>Download the latest release</strong></a> · <a href="#quick-start">Quick start</a> · <a href="https://github.com/Allie9Lives/thor-companion/issues">Report an issue</a></p>

## Downloads

Install **Thor Monitor** on the Thor and **Thor Companion** on your phone.

| App | Device | Download |
| --- | --- | --- |
| Thor Monitor **0.14.3** | AYN Thor | [Host APK](https://github.com/Allie9Lives/thor-companion/releases/download/v0.14.3/Thor-Monitor-0.14.3.apk) |
| Thor Companion **0.14.0** | Android phone | [Android APK](https://github.com/Allie9Lives/thor-companion/releases/download/v0.14.3/Thor-Companion-Android-0.14.0.apk) |
| Thor Companion **0.14.0** | iPhone | [Development IPA](https://github.com/Allie9Lives/thor-companion/releases/download/v0.14.3/Thor-Companion-iOS-0.14.0-development.ipa) |

These are development builds. The iPhone IPA requires valid provisioning or re-signing; it is not an App Store or TestFlight install. [All release files, source archives and checksums →](https://github.com/Allie9Lives/thor-companion/releases/latest)

## What it does

- **See your Thor at a glance.** Battery, charging power, temperature, CPU/GPU/RAM, model, internal storage and microSD.
- **Control both screens.** Brightness and volume with sync, plus refresh rate, fan, performance and power options.
- **Keep an eye on battery life.** Usage graphs, runtime estimates, charging alerts, iPhone widgets and Live Activity.
- **Find your Thor.** Play a rising locator sound and stop it from either device.
- **Type, capture and transfer.** Use your phone as a keyboard, save screenshots of either screen or both, and browse shared files over Wi-Fi or an existing VPN.
- **Stay connected.** Automatic Bluetooth/Wi-Fi handoff, reconnect, and configurable overnight battery saving on trusted Wi-Fi.

Choose **Light**, **Dark**, **Clear Purple**, or **Rainbow** on both apps.

## A look inside

<table>
<tr><th>Thor Companion · phone</th><th>Thor Monitor · host</th></tr>
<tr><td align="center"><img src="docs/assets/client-overview.png" alt="Thor Companion phone dashboard with battery and performance readings" width="280"></td><td align="center"><img src="docs/assets/host-overview.png" alt="Thor Monitor host dashboard with battery, performance, internal storage and microSD" width="320"></td></tr>
</table>

*Interface previews with sample readings.*

## Quick start

1. Install the host APK on your Thor and follow its guided setup.
2. Install the companion on your phone. Keep the Thor open for the first connection, then find it and confirm Bluetooth pairing on both devices.
3. For fan, performance and power controls, finish **Controls recovery** on the Thor. Enable **Wi-Fi access** for network controls, files and screenshots.

For overnight saving, add your Wi-Fi in **Settings → Monitoring → Battery saving**. Existing Tailscale settings are left alone.

[Full setup guide](docs/setup.md) · [Build from source](BUILDING.md) · [Sound credits](docs/sound-credits.md)

## License

Free to use; source available for inspection. Modifying or redistributing the app requires prior written approval from Allie9Lives. Selling copies or charging for access is prohibited. Third-party licenses and required library-replacement rights still apply. See [LICENSE](LICENSE) for the full terms.
