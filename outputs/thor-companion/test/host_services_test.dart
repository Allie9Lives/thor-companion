import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thor_companion/ble_transport.dart';
import 'package:thor_companion/companion_controller.dart';
import 'package:thor_companion/service_status.dart';
import 'controls_test.dart' show ControlBle;

class ServicesBle extends ControlBle {
  ServicesBle() {
    state['svc'] = 11;
  }
  @override
  Future<void> writeControl(String id, List<int> bytes) async {
    await super.writeControl(id, bytes);
    final action = (jsonDecode(utf8.decode(bytes)) as Map)['set'];
    final bits = state['svc'] as int;
    state['svc'] = switch (action) {
      'web_ops_start' => bits | 2,
      'web_ops_stop' => bits & ~2,
      'ftp_start' => bits | 4,
      'ftp_stop' => bits & ~4,
      'monitor_pause' => (bits & ~1) | 16,
      'monitor_resume' => (bits | 1) & ~16,
      _ => bits,
    };
    state['urls'] = ['https://192.168.1.10:47184/'];
  }
}

void main() {
  testWidgets(
    'monitoring confirmation cancels without a write, pause and resume keep link',
    (tester) async {
      final ble = ServicesBle();
      final controller = CompanionController(
        transport: ble,
        rememberDevice: false,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListenableBuilder(
              listenable: controller,
              builder: (_, _) => ServiceStatusStrip(controller: controller),
            ),
          ),
        ),
      );
      await tester.pump();
      await controller.connect(const NearbyThor('thor', 'Thor', -50));
      ble.links.add(LinkState.connected);
      await tester.pump();
      await tester.pumpAndSettle();
      final initial = ble.writes;
      await tester.tap(find.text('Monitoring'));
      await tester.pumpAndSettle();
      expect(find.text('Pause monitoring?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(ble.writes, initial);
      await tester.tap(find.text('Monitoring'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pause'));
      await tester.pumpAndSettle();
      expect(controller.readingsPaused, true);
      expect(controller.connected, true);
      expect(controller.stale, false);
      await tester.tap(find.text('Monitoring'));
      await tester.pumpAndSettle();
      expect(controller.readingsPaused, false);
      expect(controller.connected, true);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
      await ble.close();
    },
  );
}
