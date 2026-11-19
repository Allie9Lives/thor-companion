import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thor_companion/diagnostics.dart';
import 'package:thor_companion/connection_health_page.dart';
import 'package:thor_companion/companion_controller.dart';
import 'package:thor_companion/adaptive_transport.dart';
import 'adaptive_transport_test.dart' show Host, TestBle, TestNetwork;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('connection errors redact Bluetooth identifiers and credentials', () {
    final text = redactConnectionDiagnostic(
      'deviceId: phone-identity, macAddress=AA:BB:CC:DD:EE:FF Bearer token-secret ${'a' * 64}',
    );
    expect(text, isNot(contains('AA:BB:CC:DD:EE:FF')));
    expect(text, isNot(contains('phone-identity')));
    expect(text, isNot(contains('token-secret')));
    expect(text, isNot(contains('a' * 64)));
  });
  test('native Android disconnect reason survives automatic cleanup', () async {
    final host = Host(), ble = TestBle(Host());
    final link = AdaptiveTransport(
      ble,
      persist: false,
      interval: const Duration(days: 1),
      networkFactory: (c, h) => TestNetwork(host),
    );
    final sub = link.connect('thor-id').listen((_) {});
    await Future<void>.delayed(const Duration(milliseconds: 30));
    ble.links.addError(
      StateError(
        'BleDisconnectedException status=133 macAddress=AA:BB:CC:DD:EE:FF',
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(link.lastBluetoothError, contains('status=133'));
    expect(link.lastBluetoothError, isNot(contains('AA:BB')));
    expect(link.lastBluetoothErrorAt, isNotNull);
    await sub.cancel();
    link.dispose();
    await ble.links.close();
    await ble.live.close();
  });
  testWidgets(
    'copy report includes phone, client build, failed setup stage and native events',
    (t) async {
      final originalPlatform = debugDefaultTargetPlatformOverride;
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = originalPlatform);
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      String? copied;
      messenger.setMockMethodCallHandler(
        diagnosticChannel,
        (call) async => switch (call.method) {
          'info' => {
            'phone': 'Example Android phone',
            'os': 'Android 14 (API 34)',
            'client': '0.17.0 (44)',
          },
          'read' => 'GATT read failed status=5',
          _ => null,
        },
      );
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      });
      addTearDown(() {
        messenger.setMockMethodCallHandler(diagnosticChannel, null);
        messenger.setMockMethodCallHandler(SystemChannels.platform, null);
      });
      final c = CompanionController.demo();
      c.receivedCount = 0;
      c.lastFailure = StateError('GATT_INSUFFICIENT_AUTHENTICATION');
      c.lastFailureStage = 'Device reading';
      c.error = 'Could not read the device.';
      await t.pumpWidget(
        MaterialApp(home: ConnectionHealthPage(controller: c)),
      );
      await t.pumpAndSettle();
      await t.tap(find.text('Copy connection report'));
      await t.pumpAndSettle();
      for (final value in [
        'Example Android phone',
        'Android 14',
        '0.17.0 (44)',
        'GATT_INSUFFICIENT_AUTHENTICATION',
        'Device reading',
        'status=5',
        'Readings received: 0',
      ]) {
        expect(copied, contains(value));
      }
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      c.dispose();
      debugDefaultTargetPlatformOverride = originalPlatform;
    },
  );
}
