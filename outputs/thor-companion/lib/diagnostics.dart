import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

const diagnosticChannel = MethodChannel('com.alan.thorCompanion/diagnostics');
final _connectionEvents = <String>[];

String redactConnectionDiagnostic(Object value) => value
    .toString()
    .replaceAll(RegExp(r'deviceId: [^,)]+'), 'deviceId: [redacted]')
    .replaceAll(
      RegExp(r'\b(?:[0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}\b'),
      '[Bluetooth address]',
    )
    .replaceAll(
      RegExp(r'Bearer\s+\S+', caseSensitive: false),
      'Bearer [redacted]',
    )
    .replaceAll(RegExp(r'\b[a-fA-F0-9]{64}\b'), '[credential redacted]');

// Connection events only: never record telemetry, commands, passwords or tokens.
void logBle(String message) {
  message = redactConnectionDiagnostic(message);
  final line = '${DateTime.now().toUtc().toIso8601String()} $message';
  _connectionEvents.add(line.length > 2048 ? line.substring(0, 2048) : line);
  if (_connectionEvents.length > 120) _connectionEvents.removeAt(0);
  debugPrint(message);
  if (!kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.android)) {
    unawaited(
      diagnosticChannel
          .invokeMethod<void>('append', message)
          .catchError((Object _) {}),
    );
  }
}

String recentConnectionEvents() => _connectionEvents.join('\n');
Future<String> connectionEventReport() async {
  try {
    final saved = await diagnosticChannel.invokeMethod<String>('read');
    if (saved != null && saved.isNotEmpty) {
      return redactConnectionDiagnostic(saved);
    }
  } catch (_) {}
  return recentConnectionEvents();
}
