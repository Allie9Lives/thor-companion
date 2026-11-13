# Setup guide

Install **Thor Monitor** on your Thor and **Thor Companion** on your phone.

## 1. Set up your Thor

Open Thor Monitor and follow the setup screens.

### Choose your color

Pick a theme and icon to match your Thor. You can change these later in Appearance.

<img src="assets/onboarding/step-1.png" alt="Choose a color in Thor Monitor setup" width="420">

### Allow Bluetooth and background monitoring

Allow **Nearby devices**, **notifications**, and **unrestricted battery use**. Enable **Start after restart** if you want monitoring to resume automatically.

<img src="assets/onboarding/step-3.png" alt="Allow notifications and background access in Thor Monitor setup" width="420">

Continue through advanced controls and optional features, then **start monitoring**.

## 2. Connect your phone

1. Keep the Thor open and unlocked.
2. Open Thor Companion and allow Bluetooth access.
3. Find your Thor, tap **Connect**, and confirm pairing on both devices.

<img src="assets/onboarding/step-6.png" alt="Connect your phone and confirm Bluetooth pairing" width="420">

The app remembers your Thor and reconnects automatically. **Disconnect** pauses this until you tap **Reconnect**.

## 3. Enable advanced controls

For fan, performance and power controls, pair Thor Monitor with Android’s wireless debugging service. You only need the Thor for this.

1. Connect to trusted Wi-Fi. In Android Settings, tap **Build number** seven times to enable Developer options if needed.
2. In Thor Monitor, open **gear → Controls recovery → Recovery setup → Open wireless debugging**. Enable it and approve the network prompt.
3. In Android's Wireless debugging page, choose **Pair device with pairing code**. Keep that window open.
4. Enter its **pairing port** and six-digit code in Thor Monitor, then tap **Pair**. Use the port shown beside the code, not the ordinary connection port.
5. Enable automatic controls recovery and wait for **Advanced controls ready**.

After restarting, unlock the Thor once. Controls reconnect when Wi-Fi and wireless debugging are available. Android may ask you to approve a new network.

## Optional features

Choose these during setup, or return to them in the host settings later.

<img src="assets/onboarding/step-5.png" alt="Optional Wi-Fi, Find my Thor, keyboard and battery saving setup" width="420">

| Feature | Setup |
| --- | --- |
| Wi-Fi controls, files and screen capture | Turn on **Wi-Fi access** on the Thor and allow **Local Network** on iPhone. Follow the Bluetooth linking prompt, then choose which folders to share. Existing VPN settings are unchanged. |
| Screen recording | Open **Controls → Screen capture → Video** on the phone. Choose a screen and quality, record, then **Stop & save**. iPhone also offers 30/60 FPS export. |
| FTP server | Open **Files → FTP server** on the phone. Start it, then enter the connection details in an FTP client using **explicit TLS** and passive mode. |
| App drawer | Tap a focused-screen box or **Open apps** in Controls. Open apps can be switched, moved or stopped. |
| Phone keyboard | Open **Phone keyboard** in the host settings and follow the prompts. |
| Find my Thor | Allow **Stop panel over apps** on the Thor to dismiss the sound over any app. |
| Battery alerts | Open **gear → Battery notifications** on your phone, choose your alerts and send a test. Keep the app running in the background to receive them. |
| Battery widgets | Add **Thor Battery** to your Home or Lock Screen. Turn on **Live battery** in the app for more frequent updates. |
| Battery history | Tap **Battery insights** below the battery card. The graph fills in as you use the app. |

## Overnight battery saving

On the Thor, open **gear → Monitoring → Battery saving** and add your trusted Wi-Fi.

By default, on trusted Wi-Fi, the Thor can sleep after **3 hours with screens off** between **9 PM and 6 AM**. You can change those times or turn on **Keep awake while plugged in**. Allow **Alarms & reminders** so monitoring can resume at the scheduled time without waking the screens.

## Need help?

- **No readings:** Open Thor Monitor, start monitoring, then reconnect from the phone.
- **Controls unavailable:** Open Recovery setup and retry; check for a wireless-debugging approval prompt.
- **Screenshots or files won't connect:** Check Wi-Fi access and network reachability. Screen capture also needs advanced controls and an open, unlocked Thor.
- **Review permissions:** Use **gear → Review setup** on the Thor.

[Back to downloads](../README.md) · [Sound credits](sound-credits.md)

