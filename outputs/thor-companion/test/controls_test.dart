import 'dart:convert';
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:thor_companion/ble_transport.dart';
import 'package:thor_companion/companion_controller.dart';
import 'package:thor_companion/controls.dart';
import 'controller_test.dart' show FakeBle;

class ControlBle extends FakeBle implements ControlTransport {
  final state = <String, dynamic>{
    'v': 1,
    'settings': true,
    'bt': 39,
    'bb': 42,
    'vt': 80,
    'vb': 60,
    'hz': 60,
    'fan': 4,
    'performance': 0,
    'bypass': 0,
    'focus': 0,
    'vibration': 1,
    'led': 1,
    'style': 1,
    'ack': '',
    'error': '',
  };
  Completer<void>? holdWrite;
  int writes = 0;
  final commands = <Map<String, dynamic>>[];
  bool wrongAck = false, reject = false;
  @override
  bool supportsControls(String deviceId) => true;
  @override
  Future<List<int>> read(String id, String characteristic) async =>
      characteristic == controlId
      ? utf8.encode(jsonEncode(state))
      : super.read(id, characteristic);
  @override
  Future<void> writeControl(String id, List<int> bytes) async {
    writes++;
    final j = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    commands.add(j);
    if (holdWrite != null) await holdWrite!.future;
    state['ack'] = wrongAck ? 'old' : j['id'];
    state['error'] = reject ? 'Advanced controls unavailable' : '';
    if (!reject) {
      if (j['set'] == 'brightness') {
        if (j['target'] != 'bottom') state['bt'] = j['value'];
        if (j['target'] != 'top') state['bb'] = j['value'];
      } else if (j['set'] == 'volume') {
        if (j['target'] != 'bottom') state['vt'] = j['value'];
        if (j['target'] != 'top') state['vb'] = j['value'];
      } else {
        state[j['set'] as String] = j['value'];
      }
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ControlBle ble;
  late CompanionController c;
  setUp(() async {
    ble = ControlBle();
    c = CompanionController(transport: ble, rememberDevice: false);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await c.connect(const NearbyThor('thor', 'Thor', -50));
    ble.links.add(LinkState.connected);
    await Future<void>.delayed(const Duration(milliseconds: 20));
  });
  tearDown(() async {
    c.dispose();
    await ble.close();
  });
  test(
    'host locator dismissal updates client without Controls polling',
    () async {
      c.controlsVisible = false;
      ble.state['find'] = 1;
      ble.locatorActive = true;
      await c.refresh();
      await c.refreshControls();
      expect(c.controlNumber('find'), 1);
      final writes = ble.writes;
      ble.locatorActive = false;
      ble.state['find'] = 0;
      ble.notifications.add(utf8.encode('n=99 b=69'));
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(c.controlNumber('find'), 0);
      expect(c.stats!.locatorActive, isFalse);
      expect(ble.writes, writes);
    },
  );
  test(
    'heartbeat during a control write is read after the transaction',
    () async {
      ble.holdWrite = Completer<void>();
      final before = c.receivedCount;
      final change = c.setControl('fan', 1);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(c.controlBusy, isTrue);
      ble.notifications.add(utf8.encode('n=123 b=69'));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(c.receivedCount, before);
      ble.holdWrite!.complete();
      await change;
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(c.receivedCount, before + 1);
      expect(c.controlError, isNull);
      expect(ble.maxConcurrentReads, 1);
    },
  );

  test(
    'linked brightness updates both and confirms correlated readback',
    () async {
      expect(c.controls?.number('bb'), 42);
      await c.setControl('brightness', 50, target: 'both');
      expect(c.controls?.number('bt'), 50);
      expect(c.controls?.number('bb'), 50);
      expect(c.controlError, isNull);
    },
  );
  test(
    'single-screen change preserves other screen; sync toggle sends no command',
    () async {
      await c.setControlLink(brightness: true);
      expect(ble.writes, 0);
      await c.setControl('brightness', 55, target: 'top');
      expect(c.controls?.number('bb'), 42);
    },
  );
  test(
    'explicit overlapping changes serialize and failures stay separate from telemetry',
    () async {
      ble.reject = true;
      await Future.wait([c.setControl('fan', 1), c.setControl('fan', 5)]);
      expect(ble.writes, 2);
      expect(c.controlError, contains('unavailable'));
      expect(c.connected, isTrue);
      expect(c.stats?.battery, 69);
      expect(c.error, isNull);
    },
  );
  test(
    'uncorrelated response is not success and a manual disconnect blocks writes',
    () async {
      ble.wrongAck = true;
      await c.setControl('hz', 120);
      expect(c.controlError, contains('confirm'));
      await c.disconnect();
      await c.setControl('fan', 1);
      expect(ble.writes, 1);
    },
  );
  test(
    'pending values stay responsive and unsent changes coalesce in order',
    () async {
      ble.holdWrite = Completer<void>();
      final first = c.setControl('brightness', 55, target: 'both');
      final replaced = c.setControl('fan', 1);
      final latest = c.setControl('fan', 5);
      final other = c.setControl('volume', 30, target: 'both');
      expect(c.controlNumber('bt'), 55);
      expect(c.controlNumber('bb'), 55);
      expect(c.controlNumber('fan'), 5);
      expect(c.controlNumber('vt'), 30);
      expect(c.controlNumber('vb'), 30);
      expect(ble.writes, 1);
      ble.holdWrite!.complete();
      await Future.wait([first, replaced, latest, other]);
      expect(ble.commands.map((m) => m['set']).toList(), [
        'brightness',
        'fan',
        'volume',
      ]);
      expect(c.controls?.number('fan'), 5);
      expect(c.controls?.number('vb'), 30);
      expect(c.applyingControls, isFalse);
    },
  );

  test('disconnect discards unsent controls without replaying them', () async {
    ble.holdWrite = Completer<void>();
    final first = c.setControl('brightness', 55, target: 'top');
    final pending = c.setControl('fan', 5);
    await c.disconnect();
    ble.holdWrite!.complete();
    await Future.wait([first, pending]);
    expect(ble.writes, 1);
    expect(c.controlNumber('fan'), 4);
    expect(c.applyingControls, isFalse);
  });

  test('rejects unsupported control schema', () {
    expect(
      () => ThorControlState.fromBytes(utf8.encode('{"v":2}')),
      throwsFormatException,
    );
  });
}
