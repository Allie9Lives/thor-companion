import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thor_companion/companion_controller.dart';
import 'package:thor_companion/ble_transport.dart';
import 'package:thor_companion/wifi_page.dart';
import 'controls_test.dart' show ControlBle;

class WifiDemo extends CompanionController {
  WifiDemo() : super.demo() {
    wifiState = {
      'known': true,
      'connected': true,
      'name': 'Home Wi-Fi',
      'validated': true,
      'id': 2,
    };
  }
  @override
  Future<void> refreshWifi() async {}
  @override
  Future<List<Map<String, dynamic>>> wifiNetworks({
    bool nearby = false,
  }) async => [
    {'id': 2, 'n': 'Home Wi-Fi', 's': 'wpa3'},
    {'id': 3, 'n': 'Campus Wi-Fi', 's': 'enterprise'},
  ];
}

void main() {
  testWidgets('Wi-Fi page fits narrow screen and large text without overflow', (
    t,
  ) async {
    t.view.physicalSize = const Size(320, 700);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final c = WifiDemo();
    await t.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.4)),
          child: WifiPage(controller: c),
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('Thor Wi-Fi'), findsOneWidget);
    expect(find.text('Follow phone Wi-Fi'), findsOneWidget);
    expect(t.takeException(), isNull);
    await t.drag(find.byType(ListView), const Offset(0, -450));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
    c.dispose();
  });
  test(
    'Wi-Fi passwords use bounded transient command chunks, then one commit',
    () async {
      final ble = ControlBle();
      final controller = CompanionController(
        transport: ble,
        rememberDevice: false,
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await controller.connect(const NearbyThor('thor', 'Thor', -50));
      ble.links.add(LinkState.connected);
      await Future<void>.delayed(const Duration(milliseconds: 40));
      final password = 'q"\\a' * 12;
      await controller.joinNewWifi('Test Wi-Fi', 'wpa2', password);
      final commands = ble.commands
          .where((j) => (j['set'] as String).startsWith('wifi_'))
          .toList();
      expect(commands.last['set'], 'wifi_commit');
      final staged = <int>[];
      var sequence = 0;
      for (final j in commands.where((j) => j['set'] == 'wifi_stage')) {
        expect(utf8.encode(jsonEncode(j)).length, lessThanOrEqualTo(180));
        expect(j['value']['n'], sequence++);
        staged.addAll(base64Decode(j['value']['b'] as String));
      }
      final config = jsonDecode(utf8.decode(staged)) as Map;
      expect(config['p'], password);
      expect(config['s'], 'Test Wi-Fi');
      controller.dispose();
      await ble.close();
    },
  );
}
