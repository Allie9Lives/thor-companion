import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

// Connection events only: no telemetry payloads or Bluetooth identifiers.
void logBle(String message) {
  message = message.replaceAll(
    RegExp(r'deviceId: [^,)]+'),
    'deviceId: [redacted]',
  );
  debugPrint(message);
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
    unawaited(
      const MethodChannel(
        'com.alan.thorCompanion/diagnostics',
      ).invokeMethod<void>('append', message).catchError((Object _) {}),
    );
  }
}
