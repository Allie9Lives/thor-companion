# Reversible 5 GHz workaround

The Thor repeatedly selected a 6 GHz access point on its saved network after boot and timed out during WPA3 authentication. The previously working connection used 5745 MHz (5 GHz), also with WPA3.

With the user’s approval, saved network ID **3** was pinned to that working 5 GHz access point. Only the profile’s BSSID field was changed through Android’s Wi-Fi service using an authorized ADB shell. The security mode and password were preserved; passwords were neither read nor printed. The original BSSID field was unset. This is a one-network workaround, not a global radio/security change.

The tradeoff is that the Thor cannot roam to other access points on this saved network while the pin remains. If the access point is replaced or the Thor is moved out of its coverage, remove the pin or select another network.

To restore normal roaming from the workspace root:

```sh
python3 outputs/thor-wifi-workaround/restore-roaming.py --network-id 3
```

Supply `--serial YOUR_THOR_SERIAL` if multiple Android devices are attached, or `--adb /path/to/adb` for a standalone copy. If the saved network was deleted/recreated, use `adb shell cmd wifi list-networks` to find its current ID first.

The source and prebuilt setup-only tool are included. It requires the already authorized ADB shell UID; it is not exposed through Thor Companion or Bluetooth. `inspect` reads only the selected profile’s pin, `clear` removes it, and `pin` changes only that pin. The tool uses this Thor’s Android 13 Wi-Fi service interface.

Android documents the saved-profile field in [WifiConfiguration.BSSID](https://developer.android.com/reference/android/net/wifi/WifiConfiguration#BSSID).
