import 'battery_alerts.dart';

class ConnectionAlertTracker {
  int? wifiEvent;
  bool? wifiConnected;
  bool? portal;
  String? wifiName;
  bool everBluetooth = false, lostScheduled = false;
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

  static const lossDelay = Duration(seconds: 15);

  /// Returns alerts to show; a key in [cancel] means drop that pending alert.
  List<BatteryAlert> bluetooth(
    bool connected,
    bool eligible,
    BatteryAlertOptions options,
    String device,
    DateTime now, {
    List<String>? cancel,
  }) {
    // The loss alert is handed to the OS with a delay: Dart timers stop while
    // iOS suspends the app, which used to hold it until the reconnect wake-up.
    final lostShown = lostAt != null && now.difference(lostAt!) >= lossDelay;
    if (lostAt != null && lostScheduled && !lostShown) {
      if (connected || !eligible || !options.enabled) {
        cancel?.add('bluetoothLost');
      }
    }
    if (!eligible || !options.enabled) {
      lostAt = null;
      lostScheduled = false;
      everBluetooth = connected;
      return [];
    }
    if (connected) {
      everBluetooth = true;
      lostAt = null;
      lostScheduled = false;
      return lostShown && options.bluetoothBack
          ? [
              BatteryAlert(
                'bluetoothBack',
                device,
                'Bluetooth connection restored.',
              ),
            ]
          : [];
    }
    if (!everBluetooth || lostAt != null) return [];
    lostAt = now;
    lostScheduled = options.bluetoothLost;
    return lostScheduled
        ? [
            BatteryAlert(
              'bluetoothLost',
              device,
              'Bluetooth connection lost. The device may be out of range.',
              delay: lossDelay.inSeconds,
            ),
          ]
        : [];
  }
}
