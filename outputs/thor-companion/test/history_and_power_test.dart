import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thor_companion/ble_transport.dart';
import 'package:thor_companion/companion_controller.dart';
import 'package:thor_companion/battery_pages.dart';
import 'package:thor_companion/battery_history.dart';
import 'package:thor_companion/ui.dart';
import 'controls_test.dart' show ControlBle;

class HistoryBle extends ControlBle {
  bool corruptCursor = false;
  @override
  Future<void> writeControl(String device, List<int> bytes) async {
    final command = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    if (command['set'] == 'battery_sleep') {
      writes++;
      commands.add(command);
      final now = DateTime.now().millisecondsSinceEpoch;
      state.addAll({
        'ack': command['id'],
        'error': '',
        'sleep_events': [
          [now - 600000, 1],
          [now - 300000, 0],
        ],
        'more': false,
        'next': now - 300000,
      });
      return;
    }
    if (command['set'] != 'battery_history') {
      await super.writeControl(device, bytes);
      return;
    }
    writes++;
    commands.add(command);
    final first = command['value'] == 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    state.addAll({
      'ack': command['id'],
      'error': '',
      'history': [
        [
          now - (first ? 600000 : 300000),
          first ? 80 : 79,
          0,
          35,
          4200,
          -500000,
          5000000,
          null,
          1,
        ],
      ],
      'next': corruptCursor ? 0 : now - 600000,
      'more': first,
    });
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late HistoryBle ble;
  late CompanionController c;
  var disposed = false;
  setUp(() async {
    disposed = false;
    ble = HistoryBle();
    ble.state.addAll({'history': true, 'power_control': true});
    c = CompanionController(transport: ble, rememberDevice: false);
    await c.connect(const NearbyThor('thor', 'Thor', -50));
    ble.links.add(LinkState.connected);
    await Future<void>.delayed(const Duration(milliseconds: 25));
  });
  tearDown(() async {
    if (!disposed) c.dispose();
    await ble.close();
  });

  test(
    'paged history merges measured rows and releases the transaction',
    () async {
      await c.loadBatteryHistory();
      expect(c.batteryHistoryError, isNull);
      expect(
        ble.commands.where((j) => j['set'] == 'battery_history'),
        hasLength(2),
      );
      expect(
        c.batteryLedger.points.where((p) => p.level == 80 || p.level == 79),
        hasLength(2),
      );
      expect(c.controlBusy, isFalse);
      expect(c.batteryHistoryBusy, isFalse);
    },
  );
  test('sleep markers sync separately from measured battery samples', () async {
    ble.state['sleep_policy'] = true;
    await c.refreshControls();
    await c.loadBatteryHistory();
    expect(c.batteryHistoryError, isNull);
    expect(c.batteryLedger.sleepEvents.map((e) => e.code), [1, 0]);
    expect(
      ble.commands.where((j) => j['set'] == 'battery_sleep'),
      hasLength(1),
    );
  });
  test(
    'wake screens can be requested with stale readings when keep-alive is paused',
    () async {
      ble.state.addAll({
        'sleep_policy': true,
        'sleep_suspended': true,
        'wake_control': true,
        'screens_awake': false,
      });
      await c.refreshControls();
      c.receivedAt = DateTime.now().subtract(const Duration(minutes: 3));
      expect(await c.devicePower(3), true);
      expect(c.keepAlivePaused, false);
      expect(c.controls!.values['screens_awake'], true);
      expect(ble.commands.where((j) => j['set'] == 'power').single['value'], 3);
    },
  );
  test('restore time can be changed remotely while connected', () async {
    ble.state.addAll({'sleep_policy': true, 'sleep_end': 360});
    await c.refreshControls();
    await c.setControl('sleep_end', 420);
    expect(c.controlError, isNull);
    expect(c.controlNumber('sleep_end'), 420);
  });
  test('non-advancing history cursor fails without looping', () async {
    ble.corruptCursor = true;
    await c.loadBatteryHistory();
    expect(c.batteryHistoryError, isNotNull);
    expect(ble.writes, 1);
    expect(c.controlBusy, isFalse);
  });
  test('uncertain restart acknowledgement never replays the command', () async {
    ble.wrongAck = true;
    await expectLater(c.devicePower(1), throwsStateError);
    expect(ble.commands.where((j) => j['set'] == 'power'), hasLength(1));
    expect(c.controlBusy, isFalse);
  });
  test('power waits for a current read and sends exactly once', () async {
    ble.blocked = Completer<List<int>>();
    final refresh = c.refresh();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    final power = c.devicePower(0);
    expect(c.powerBusy, isTrue);
    expect(ble.writes, 0);
    ble.blocked!.complete(
      utf8.encode('{"seq":124,"ts_ms":1000,"battery_pct":69}'),
    );
    await refresh;
    expect(await power, isTrue);
    expect(ble.commands.where((j) => j['set'] == 'power'), hasLength(1));
    expect(c.powerBusy, isFalse);
  });
  testWidgets('polling follows external values and pauses in background', (
    tester,
  ) async {
    c.dispose();
    c = CompanionController(transport: ble, rememberDevice: false);
    await c.connect(const NearbyThor('thor', 'Thor', -50));
    ble.links.add(LinkState.connected);
    await tester.pump();
    await tester.pump();
    c.controlsVisible = true;
    ble.state['bb'] = 19;
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(c.controlNumber('bb'), 19);
    c.setForeground(false);
    ble.state['bb'] = 91;
    await tester.pump(const Duration(seconds: 2));
    expect(c.controlNumber('bb'), 19);
    c.dispose();
    disposed = true;
  });
  testWidgets('battery diagnostics fit a narrow screen with large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final now = DateTime.now().millisecondsSinceEpoch;
    c.batteryLedger.merge(
      List.generate(
        20,
        (i) => BatteryPoint(
          now - (20 - i) * 300000,
          90 - i.toDouble(),
          false,
          35,
          4200,
          -500000,
          5000000,
          null,
          true,
        ),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(Brightness.light),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(1.35)),
          child: child!,
        ),
        home: BatteryInsightsPage(controller: c),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.drag(find.byType(ListView), const Offset(0, -1800));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
