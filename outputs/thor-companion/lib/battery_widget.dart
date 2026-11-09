import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class BatteryWidgetSnapshot {
  const BatteryWidgetSnapshot({
    required this.percent,
    required this.updatedAt,
    required this.charging,
    required this.connected,
  });
  final double percent;
  final DateTime updatedAt;
  final bool charging, connected;
  Map<String, Object> toMap() => {
    'percent': percent,
    'updatedAtMs': updatedAt.millisecondsSinceEpoch,
    'charging': charging,
    'connected': connected,
  };
}

Future<void> publishBatteryWidget(BatteryWidgetSnapshot? snapshot) async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) return;
  await const MethodChannel(
    'com.alan.thorCompanion/batteryWidget',
  ).invokeMethod<void>(
    snapshot == null ? 'clear' : 'update',
    snapshot?.toMap(),
  );
}

Future<void> setLiveBattery(bool enabled) async {
  await const MethodChannel(
    'com.alan.thorCompanion/batteryWidget',
  ).invokeMethod<void>(enabled ? 'startLive' : 'stopLive');
}
