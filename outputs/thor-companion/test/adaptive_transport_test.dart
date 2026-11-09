import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:thor_companion/adaptive_transport.dart';
import 'package:thor_companion/adaptive_network.dart';
import 'package:thor_companion/ble_transport.dart';
import 'package:thor_companion/link_policy.dart';
import 'package:thor_companion/companion_controller.dart';

class Host {
  bool reachable = false, loseAck = false;
  int executions = 0, probes = 0;
  final receipts = <String, List<int>>{};
  List<int> command(List<int> bytes) {
    final j = jsonDecode(utf8.decode(bytes)) as Map;
    return receipts.putIfAbsent(j['id'] as String, () {
      executions++;
      return utf8.encode(
        jsonEncode({'v': 1, 'ack': j['id'], 'error': '', 'find': 1}),
      );
    });
  }
}

class TestBle implements BleTransport, ControlTransport, SignalTransport {
  TestBle(this.host);
  final Host host;
  final links = StreamController<LinkState>.broadcast();
  final live = StreamController<List<int>>.broadcast();
  int signal = -88, cancellations = 0, opens = 0;
  List<int> reply = [];
  int sequence = 0;
  List<int> data(String c) => utf8.encode(
    c == hardwareId
        ? '{"model":"AYN Thor","device_name":"Thor"}'
        : jsonEncode({
            'seq': ++sequence,
            'ts_ms': DateTime.now().millisecondsSinceEpoch,
            'battery_pct': 70,
          }),
  );
  @override
  Stream<RadioState> get radio => Stream.value(RadioState.ready);
  @override
  Future<void> requestAccess() async {}
  @override
  Stream<NearbyThor> scan() => const Stream.empty();
  @override
  Stream<LinkState> connect(String id, {bool background = false}) {
    opens++;
    return Stream.multi((out) {
      final sub = links.stream.listen(out.add);
      out.onCancel = () async {
        cancellations++;
        await sub.cancel();
      };
      scheduleMicrotask(() => out.add(LinkState.connected));
    });
  }

  @override
  Future<void> discover(String id) async {}
  @override
  Stream<List<int>> subscribe(String id, String c) => live.stream;
  @override
  Future<int> readSignal(String id) async => signal;
  @override
  bool supportsControls(String id) => true;
  @override
  Future<List<int>> read(String id, String c) async {
    if (c == controlId) {
      final bytes = reply.isEmpty
          ? utf8.encode('{"v":1,"ack":"","error":""}')
          : reply;
      if (utf8.decode(bytes).contains('hosts')) reply = [];
      return bytes;
    }
    return c == liveId ? utf8.encode('n=1 b=70') : data(c);
  }

  @override
  Future<void> writeControl(String id, List<int> bytes) async {
    final j = jsonDecode(utf8.decode(bytes)) as Map;
    if (j['set'] == 'network_session') {
      reply = utf8.encode(
        '{"ack":"${j['id']}","error":"","hosts":["thor"],"pin":"${'a' * 64}","token":"${'b' * 64}","port":47183}',
      );
    } else {
      reply = host.command(bytes);
    }
  }
}

class TestNetwork implements ControlNetwork {
  TestNetwork(this.host);
  final Host host;
  bool closed = false;
  @override
  Future<void> probe() async {
    host.probes++;
    if (!host.reachable || closed) throw StateError('isolated');
  }

  @override
  Future<List<int>> read(String kind) async {
    if (!host.reachable || closed) throw StateError('lost');
    if (kind == 'control') return utf8.encode('{"v":1,"ack":"","error":""}');
    if (kind == 'hardware') return utf8.encode('{"model":"AYN Thor"}');
    return utf8.encode(
      kind == 'live'
          ? 'n=2 b=70'
          : '{"seq":8,"ts_ms":1794000000000,"battery_pct":70}',
    );
  }

  @override
  Future<List<int>> command(List<int> bytes) async {
    if (!host.reachable || closed) throw StateError('lost');
    final result = host.command(bytes);
    if (host.loseAck) throw StateError('ack lost');
    return result;
  }

  @override
  void close() {
    closed = true;
  }
}

Future<void> until(bool Function() condition) async {
  for (var i = 0; i < 200 && !condition(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  expect(condition(), true, reason: 'condition timed out');
}

void main() {
  test('routing requires verified network, weak signal and hysteresis', () {
    final p = LinkPolicy(), now = DateTime(2026);
    p.bluetooth(signal: -90);
    p.bluetooth(signal: -90);
    expect(p.choose(now, bleAvailable: true), ControlRoute.bluetooth);
    p.network(const Duration(milliseconds: 20), now);
    expect(p.choose(now, bleAvailable: true), ControlRoute.bluetooth);
    p.network(const Duration(milliseconds: 20), now);
    expect(p.choose(now, bleAvailable: true), ControlRoute.network);
    for (var i = 0; i < 4; i++) {
      p.bluetooth(signal: -60, elapsed: const Duration(milliseconds: 10));
    }
    expect(
      p.choose(now.add(const Duration(seconds: 2)), bleAvailable: true),
      ControlRoute.network,
    );
    p.networkFailed();
    expect(p.choose(now, bleAvailable: true), ControlRoute.bluetooth);
  });
  test('responsiveness can switch without a weak RSSI reading', () {
    final p = LinkPolicy(), now = DateTime(2026);
    for (var i = 0; i < 3; i++) {
      p.bluetooth(elapsed: const Duration(milliseconds: 600), signal: -60);
      p.network(const Duration(milliseconds: 40), now);
    }
    expect(p.choose(now, bleAvailable: true), ControlRoute.network);
  });
  late Host host;
  late TestBle ble;
  late AdaptiveTransport link;
  StreamSubscription<LinkState>? session;
  setUp(() {
    host = Host();
    ble = TestBle(host);
    link = AdaptiveTransport(
      ble,
      persist: false,
      interval: const Duration(milliseconds: 20),
      networkFactory: (c, h) => TestNetwork(host),
    );
  });
  tearDown(() async {
    await session?.cancel();
    session = null;
    link.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 30));
    await ble.links.close();
    await ble.live.close();
  });
  Future<List<LinkState>> start() async {
    final states = <LinkState>[];
    session = link.connect('thor-id').listen(states.add);
    await until(() => link.bleConnected);
    await link.discover('thor-id');
    return states;
  }

  test(
    'isolated Wi-Fi retains BLE; verified Wi-Fi takes over without cancelling BLE',
    () async {
      await start();
      await until(() => host.probes >= 2);
      expect(link.route, ControlRoute.bluetooth);
      expect(ble.cancellations, 0);
      host.reachable = true;
      await until(() => link.route == ControlRoute.network);
      expect(link.bleConnected, true);
      expect(ble.cancellations, 0);
      await link.writeControl(
        'thor-id',
        utf8.encode('{"id":"one","set":"find","value":1}'),
      );
      expect(host.executions, 1);
      host.reachable = false;
      await until(() => !link.networkReady);
      expect(link.route, ControlRoute.bluetooth);
      expect(ble.cancellations, 0);
    },
  );
  test(
    'Wi-Fi survives BLE loss, then explicit disconnect ends both paths',
    () async {
      host.reachable = true;
      final states = await start();
      await until(() => link.networkReady);
      ble.links.add(LinkState.disconnected);
      await until(() => !link.bleConnected);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(states.where((s) => s == LinkState.disconnected), isEmpty);
      expect(utf8.decode(await link.read('thor-id', statsId)), contains('70'));
      await session!.cancel();
      session = null;
      final probes = host.probes;
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(host.probes, probes);
      expect(link.networkReady, false);
    },
  );
  test(
    'lost network acknowledgement retries the identical request without duplicate effect',
    () async {
      host.reachable = true;
      await start();
      await until(() => link.route == ControlRoute.network);
      host.loseAck = true;
      await link.writeControl(
        'thor-id',
        utf8.encode('{"id":"same","set":"text","value":"hello"}'),
      );
      expect(host.executions, 1);
      final reply =
          jsonDecode(utf8.decode(await link.read('thor-id', controlId))) as Map;
      expect(reply['ack'], 'same');
      expect(link.route, ControlRoute.bluetooth);
    },
  );
  test(
    'background uses retained BLE and automatic switching can be disabled',
    () async {
      host.reachable = true;
      await start();
      await until(() => link.route == ControlRoute.network);
      link.setForeground(false);
      expect(link.networkReady, false);
      expect(ble.cancellations, 0);
      link.setForeground(true);
      await until(() => link.networkReady);
      await link.setAutomatic(false);
      expect(link.route, ControlRoute.bluetooth);
      expect(link.networkReady, false);
    },
  );
  test(
    'host battery saving stops automatic link probes until it resumes',
    () async {
      host.reachable = true;
      await start();
      await until(() => link.route == ControlRoute.network);
      link.setSleeping(true);
      final probes = host.probes;
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(host.probes, probes);
      link.setSleeping(false);
      await until(() => host.probes > probes);
    },
  );
  test(
    'network-only monitoring checks again at the saved morning restore time',
    () async {
      host.reachable = true;
      final states = await start();
      await until(() => link.route == ControlRoute.network);
      link.setSleeping(
        true,
        resumeAt: DateTime.now()
            .subtract(const Duration(seconds: 10))
            .add(const Duration(milliseconds: 100)),
      );
      ble.links.add(LinkState.disconnected);
      await until(() => !link.bleConnected);
      final probes = host.probes;
      await until(() => !link.sleeping && host.probes > probes);
      expect(states.where((s) => s == LinkState.disconnected), isEmpty);
      expect(link.route, ControlRoute.network);
    },
  );
  test('immediate cancellation cannot create a ghost connection', () async {
    session = link.connect('thor-id').listen((_) {});
    await session!.cancel();
    session = null;
    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(ble.opens, 0);
  });
  test(
    'controller stays usable across a network handoff and still honors Disconnect',
    () async {
      host.reachable = true;
      final c = CompanionController(
        transport: link,
        rememberDevice: false,
        batteryPublisher: (_) async {},
      );
      try {
        await c.connect(const NearbyThor('thor-id', 'Thor', -88));
        await until(() => c.notificationsRequested);
        await until(() => link.route == ControlRoute.network);
        ble.links.add(LinkState.disconnected);
        await until(() => !link.bleConnected);
        await c.refresh();
        expect(c.connected, true);
        expect(c.stats?.battery, 70);
        expect(c.error, isNull);
        expect(c.controlError, isNull);
        await c.setControl('find', 1);
        expect(c.controlError, isNull);
        expect(host.executions, 1);
        await c.disconnect();
        expect(c.connected, false);
        expect(link.networkReady, false);
      } finally {
        c.dispose();
      }
    },
  );
}
