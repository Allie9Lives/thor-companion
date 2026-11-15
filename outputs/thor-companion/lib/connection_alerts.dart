import 'battery_alerts.dart';

class ConnectionAlertTracker {
  int? wifiEvent;
  bool? wifiConnected;
  bool? portal;
  String? wifiName;
  bool everBluetooth = false, lostSent = false;
  DateTime? lostAt;

  List<BatteryAlert> wifi(
    Map<String, dynamic> state,
    BatteryAlertOptions options,
    String device,
    DateTime now,
  ) {
    if (state['known'] != true || state['event'] is! num) return [];
    final event = (state['event'] as num).toInt(),
        connected = state['connected'] == true,
        captive = state['captive'] == true;
    final prior = wifiEvent, oldConnected = wifiConnected, oldPortal = portal;
    final oldName = wifiName;
    wifiName = state['name'] as String?;
    wifiEvent = event;
    wifiConnected = connected;
    portal = captive;
    if (prior == null || prior == event || !options.enabled) return [];
    final changed = (state['changed_at'] as num?)?.toInt() ?? 0;
    final age = now.millisecondsSinceEpoch - changed;
    if (age < -5000 || age > 90000) return [];
    final name = state['name'] as String? ?? 'Wi-Fi';
    return [
      if (connected &&
          (oldConnected != true || oldName != wifiName) &&
          options.wifiChanged)
        BatteryAlert(
          'wifiChanged',
          device,
          'Wi-Fi connection has changed to $name.',
        ),
      if (!connected && oldConnected == true && options.wifiLost)
        BatteryAlert('wifiLost', device, 'Wi-Fi disconnected.'),
      if (connected && captive && oldPortal != true && options.wifiSignIn)
        BatteryAlert(
          'wifiSignIn',
          device,
          '$name needs sign-in. Open Wi-Fi in Thor Companion.',
        ),
    ];
  }

  List<BatteryAlert> bluetooth(
    bool connected,
    bool eligible,
    BatteryAlertOptions options,
    String device,
    DateTime now,
  ) {
    if (!eligible || !options.enabled) {
      lostAt = null;
      lostSent = false;
      everBluetooth = connected;
      return [];
    }
    if (connected) {
      final notify = lostSent && options.bluetoothBack;
      everBluetooth = true;
      lostAt = null;
      lostSent = false;
      return notify
          ? [
              BatteryAlert(
                'bluetoothBack',
                device,
                'Bluetooth connection restored.',
              ),
            ]
          : [];
    }
    if (!everBluetooth || lostSent) return [];
    lostAt ??= now;
    if (now.difference(lostAt!) < const Duration(seconds: 15)) return [];
    lostSent = true;
    return options.bluetoothLost
        ? [
            BatteryAlert(
              'bluetoothLost',
              device,
              'Bluetooth connection lost. The Thor may be out of range.',
            ),
          ]
        : [];
  }
}
