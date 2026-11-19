import 'package:flutter/services.dart';

const batteryAlertChannel = MethodChannel(
  'com.alan.thorCompanion/batteryAlerts',
);

class BatteryAlertOptions {
  BatteryAlertOptions({
    this.enabled = false,
    this.low10 = true,
    this.low20 = true,
    this.charged80 = true,
    this.plugged = true,
    this.unplugged = true,
    this.closedLid = false,
    this.wifiChanged = false,
    this.wifiLost = false,
    this.wifiSignIn = false,
    this.bluetoothLost = false,
    this.bluetoothBack = false,
  });
  factory BatteryAlertOptions.fromMap(Map<String, dynamic> j) =>
      BatteryAlertOptions(
        enabled: j['enabled'] == true,
        low10: j['low10'] != false,
        low20: j['low20'] != false,
        charged80: j['charged80'] != false,
        plugged: j['plugged'] != false,
        unplugged: j['unplugged'] != false,
        closedLid: j['closedLid'] == true,
        wifiChanged: j['wifiChanged'] == true,
        wifiLost: j['wifiLost'] == true,
        wifiSignIn: j['wifiSignIn'] == true,
        bluetoothLost: j['bluetoothLost'] == true,
        bluetoothBack: j['bluetoothBack'] == true,
      );
  bool enabled, low10, low20, charged80, plugged, unplugged, closedLid;
  bool wifiChanged, wifiLost, wifiSignIn, bluetoothLost, bluetoothBack;
  Map<String, bool> toMap() => {
    'enabled': enabled,
    'low10': low10,
    'low20': low20,
    'charged80': charged80,
    'plugged': plugged,
    'unplugged': unplugged,
    'closedLid': closedLid,
    'wifiChanged': wifiChanged,
    'wifiLost': wifiLost,
    'wifiSignIn': wifiSignIn,
    'bluetoothLost': bluetoothLost,
    'bluetoothBack': bluetoothBack,
  };
}

class BatteryAlert {
  const BatteryAlert(this.key, this.title, this.body, {this.delay = 0});
  final String key, title, body;

  /// Seconds the OS waits before showing it, so it fires while the app is suspended.
  final int delay;
  BatteryAlert forDevice(String name) =>
      BatteryAlert(key, name, '$title. $body', delay: delay);
  Map<String, String> toMap() => {
    'id': key,
    'title': title,
    'body': body,
    if (delay > 0) 'delay': '$delay',
  };
}

class BatteryAlertTracker {
  double? previous;
  bool? previousPlug;
  bool sent10 = false, sent20 = false, sent80 = false;
  int lastTime = 0;
  void load(Map<String, dynamic> j) {
    previous = (j['level'] as num?)?.toDouble();
    previousPlug = j['plugged'] as bool?;
    sent10 = j['sent10'] == true;
    sent20 = j['sent20'] == true;
    sent80 = j['sent80'] == true;
    lastTime = (j['time'] as num?)?.toInt() ?? 0;
  }

  Map<String, Object?> toMap() => {
    'level': previous,
    'plugged': previousPlug,
    'sent10': sent10,
    'sent20': sent20,
    'sent80': sent80,
    'time': lastTime,
  };
  List<BatteryAlert> observe(
    double level,
    bool plugged,
    int time,
    BatteryAlertOptions options,
  ) {
    if (!level.isFinite || level < 0 || level > 100 || time <= lastTime) {
      return [];
    }
    final old = previous, oldPlug = previousPlug;
    lastTime = time;
    if (old == null || oldPlug == null) {
      previous = level;
      previousPlug = plugged;
      sent10 = level <= 10;
      sent20 = level <= 20;
      sent80 = level >= 80;
      return [];
    }
    if (level > 13) sent10 = false;
    if (level > 23) sent20 = false;
    if (level < 75 || (!plugged && level < 80)) sent80 = false;
    final alerts = <BatteryAlert>[];
    if (!plugged && level <= 10 && !sent10) {
      final warn10 = options.low10, warn20 = options.low20 && !sent20;
      sent10 = sent20 = true;
      if (warn10 || warn20) {
        alerts.add(
          BatteryAlert(
            warn10 ? 'low10' : 'low20',
            'Device battery is low',
            '${level.round()}% remaining. Connect your device to power.',
          ),
        );
      }
    } else if (!plugged && level <= 20 && !sent20) {
      sent20 = true;
      if (options.low20) {
        alerts.add(
          BatteryAlert(
            'low20',
            'Device battery is low',
            '${level.round()}% remaining.',
          ),
        );
      }
    }
    if (plugged && old < 80 && level >= 80 && !sent80) {
      sent80 = true;
      if (options.charged80) {
        alerts.add(
          BatteryAlert(
            'charged80',
            'Device charged to 80%',
            'Your device is now at ${level.round()}%.',
          ),
        );
      }
    }
    if (plugged != oldPlug) {
      if (plugged && options.plugged) {
        alerts.add(
          const BatteryAlert(
            'plugged',
            'Device connected to power',
            'Your device is plugged in.',
          ),
        );
      }
      if (!plugged && options.unplugged) {
        alerts.add(
          const BatteryAlert(
            'unplugged',
            'Device disconnected from power',
            'Your device is running on battery.',
          ),
        );
      }
    }
    previous = level;
    previousPlug = plugged;
    return options.enabled ? alerts : [];
  }
}

Future<bool> requestBatteryAlertPermission() async =>
    await batteryAlertChannel.invokeMethod<bool>('requestPermission') ?? false;
Future<void> showBatteryAlert(BatteryAlert alert) =>
    batteryAlertChannel.invokeMethod<void>('show', alert.toMap());
Future<void> cancelBatteryAlert(String key) =>
    batteryAlertChannel.invokeMethod<void>('cancel', key);
