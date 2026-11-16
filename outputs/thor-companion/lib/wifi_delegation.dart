import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

class WifiFollowing {
  static const channel = MethodChannel('com.alan.thorCompanion/wifi');
  static bool get usesAutomation =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
  Future<void> prepare() async {
    if (!kIsWeb &&
        defaultTargetPlatform == TargetPlatform.android &&
        !await Permission.locationWhenInUse.request().isGranted) {
      throw StateError(
        'Allow location access to read this phone’s Wi-Fi name.',
      );
    }
  }

  Future<({String name, String event})?> current() async {
    final j = await channel.invokeMapMethod<String, dynamic>('current');
    if (j == null || j['name'] is! String) return null;
    return (name: j['name'] as String, event: '${j['event'] ?? j['name']}');
  }
}
