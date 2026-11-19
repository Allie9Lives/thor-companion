import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:thor_companion/ble_transport.dart';
import 'package:thor_companion/companion_controller.dart';
import 'package:thor_companion/battery_widget.dart';

class FakeBle implements BleTransport {
  final links = StreamController<LinkState>.broadcast();
  final radios = StreamController<RadioState>.broadcast();
  final notifications = StreamController<List<int>>.broadcast();
  int discoveries = 0, connections = 0;
  final backgroundRequests = <bool>[];
  int sequence = 1,
      reads = 0,
      subscriptions = 0,
      concurrentReads = 0,
      maxConcurrentReads = 0;
  Completer<List<int>>? blocked;
  bool malformed = false;
  bool? locatorActive;
  Object? discoveryFailure, statsFailure;
  @override
  Stream<RadioState> get radio async* {
    yield RadioState.ready;
    yield* radios.stream;
  }

  @override
  Future<void> requestAccess() async {}
  @override
  Future<void> discover(String deviceId) async {
    discoveries++;
    if (discoveryFailure != null) throw discoveryFailure!;
  }

  @override
  Stream<NearbyThor> scan() => const Stream.empty();
  @override
  Stream<LinkState> connect(String deviceId, {bool background = false}) {
    backgroundRequests.add(background);
    connections++;
    return links.stream;
  }

  @override
  Stream<List<int>> subscribe(String deviceId, String characteristicId) {
    subscriptions++;
    return notifications.stream;
  }

  @override
  Future<List<int>> read(String deviceId, String characteristicId) async {
    concurrentReads++;
    if (concurrentReads > maxConcurrentReads) {
      maxConcurrentReads = concurrentReads;
    }
    try {
      reads++;
      if (characteristicId == statsId && statsFailure != null) {
        throw statsFailure!;
      }
      if (blocked != null && characteristicId == statsId) {
        return await blocked!.future;
      }
      if (characteristicId == hardwareId) {
        return utf8.encode('{"model":"AYN Thor","ufs_version":"4.0"}');
      }
      if (malformed) return utf8.encode('{}');
      return utf8.encode(
        jsonEncode({
          'seq': sequence++,
          'ts_ms': 1793815386000,
          'battery_pct': 69,
          'locator_active': locatorActive,
          'plugged_code': 0,
        }),
      );
    } finally {
      concurrentReads--;
    }
  }

  Future<void> close() async {
    await links.close();
    await notifications.close();
    await radios.close();
  }
}

/// Adds a control channel whose read can be held open across a link loss.
class FakeControlBle extends FakeBle implements ControlTransport {
  Completer<List<int>>? control;
  int controlReads = 0;
  @override
  bool supportsControls(String deviceId) => true;
  @override
  Future<void> writeControl(String deviceId, List<int> bytes) async {}
  @override
  Future<List<int>> read(String deviceId, String characteristicId) {
    if (characteristicId != controlId) {
      return super.read(deviceId, characteristicId);
    }
    // Only the first control read hangs; later ones fail fast like a busy Thor.
    if (++controlReads > 1) return Future.error(StateError('Controls busy'));
    control = Completer<List<int>>();
    return control!.future;
  }
}

/// Acknowledges every control write the way Thor Monitor does.
class FakeInputBle extends FakeBle implements ControlTransport {
  final writes = <Map<String, dynamic>>[];
  String error = '';
  @override
  bool supportsControls(String deviceId) => true;
  @override
  Future<void> writeControl(String deviceId, List<int> bytes) async {
    expect(bytes.length, lessThanOrEqualTo(180));
    writes.add(jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>);
  }

  @override
  Future<List<int>> read(String deviceId, String characteristicId) {
    if (characteristicId != controlId) {
      return super.read(deviceId, characteristicId);
    }
    return Future.value(
      utf8.encode(
        jsonEncode({
          'v': 1,
          'ack': writes.isEmpty ? '' : writes.last['id'],
          'error': error,
        }),
      ),
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeBle ble;
  late CompanionController c;
  setUp(() {
    ble = FakeBle();
    c = CompanionController(transport: ble, rememberDevice: false);
  });
  tearDown(() async {
    c.dispose();
    await ble.close();
  });

  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 20));
  Future<void> establish() async {
    await settle();
    await c.connect(const NearbyThor('thor', 'Device', -50));
    ble.links.add(LinkState.connected);
    await settle();
  }

  test(
    'connect reads stats/hardware then subscribes; heartbeat refreshes stats',
    () async {
      await establish();
      expect(c.connected, isTrue);
      expect(c.stats?.battery, 69);
      expect(c.hardware?.ufsVersion, '4.0');
      expect(ble.subscriptions, 1);
      expect(c.stale, isFalse);
      final before = c.receivedCount;
      ble.notifications.add(utf8.encode('n=12 b=69'));
      await settle();
      expect(c.receivedCount, before + 1);
      expect(c.heartbeat?.sequence, 12);
      expect(ble.maxConcurrentReads, 1);
    },
  );
  test('repeated Connect is ignored while a connection is pending', () async {
    final first = c.connect(const NearbyThor('thor', 'Device', -50));
    final second = c.connect(const NearbyThor('thor', 'Device', -50));
    await Future.wait([first, second]);
    expect(ble.connections, 1);
    expect(c.phase, CompanionPhase.connecting);
  });

  test(
    'Reconnect on a live link retries data without replacing the link',
    () async {
      ble.malformed = true;
      await establish();
      ble.malformed = false;
      await c.connect(const NearbyThor('thor', 'Device', -50));
      expect(ble.connections, 1);
      expect(ble.discoveries, 2);
      expect(c.stats?.battery, 69);
      expect(c.error, isNull);
    },
  );

  test(
    'disconnected readings remain visible but are explicitly stale',
    () async {
      await establish();
      ble.links.add(LinkState.disconnected);
      await settle();
      expect(c.connected, isFalse);
      expect(c.stale, isTrue);
      expect(c.stats?.battery, 69);
      expect(c.error, contains('Connection ended'));
    },
  );
  test(
    'failed first read never subscribes and Refresh retries the full setup',
    () async {
      ble.malformed = true;
      await establish();
      expect(c.stats, isNull);
      expect(c.error, contains('incomplete'));
      expect(c.initializing, isFalse);
      expect(ble.subscriptions, 0);
      ble.malformed = false;
      await c.refresh();
      expect(ble.discoveries, 2);
      expect(c.stats?.battery, 69);
      expect(ble.subscriptions, 1);
      expect(c.notificationsRequested, isTrue);
    },
  );

  test(
    'Refresh restores a failed notification subscription without forgetting pairing',
    () async {
      await establish();
      ble.notifications.addError(StateError('Subscription failed'));
      await settle();
      expect(c.connected, isTrue);
      expect(c.notificationsRequested, isFalse);
      expect(c.error, contains('Refresh'));
      await c.refresh();
      expect(ble.discoveries, 2);
      expect(ble.subscriptions, 2);
      expect(c.notificationsRequested, isTrue);
      expect(c.error, isNull);
      ble.notifications.add(utf8.encode('n=99 b=69'));
      await settle();
      expect(c.heartbeat?.sequence, 99);
    },
  );

  test(
    'silent live stream is repaired automatically without a swipe',
    () async {
      await establish();
      final before = c.receivedCount;
      c.receivedAt = DateTime.now().subtract(const Duration(seconds: 46));
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      expect(c.receivedCount, before + 1);
      expect(ble.discoveries, 2);
      expect(ble.subscriptions, 2);
      expect(ble.connections, 1);
      expect(ble.maxConcurrentReads, 1);
    },
  );

  test(
    'watchdog leaves a healthy stream and background connection alone',
    () async {
      await establish();
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      expect(ble.discoveries, 1);
      c.setForeground(false);
      c.receivedAt = DateTime.now().subtract(const Duration(seconds: 46));
      final before = c.receivedCount;
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      expect(c.receivedCount, before);
      c.setForeground(true);
      await settle();
      expect(c.receivedCount, before + 1);
    },
  );

  test('connected readings older than 90 seconds are stale', () async {
    await establish();
    c.receivedAt = DateTime.now().subtract(const Duration(seconds: 91));
    expect(c.connected, isTrue);
    expect(c.stale, isTrue);
  });

  test(
    'reconnecting keeps cached readings stale until a new response',
    () async {
      await establish();
      final before = c.stats;
      await c.disconnect();
      ble.blocked = Completer<List<int>>();
      await c.connect(const NearbyThor('thor', 'Device', -50));
      ble.links.add(LinkState.connected);
      await settle();
      expect(c.connected, isTrue);
      expect(c.stats, same(before));
      expect(c.stale, isTrue);
      ble.blocked!.complete(
        utf8.encode('{"seq":1,"ts_ms":1000,"battery_pct":68}'),
      );
      await settle();
      expect(c.stale, isFalse);
      expect(c.stats?.sequence, 1);
    },
  );

  test(
    'bad packet leaves the last good reading and timestamp unchanged',
    () async {
      await establish();
      final at = c.receivedAt;
      final reading = c.stats;
      ble.malformed = true;
      await c.refresh();
      expect(c.receivedAt, at);
      expect(c.stats, same(reading));
      expect(c.error, isNotNull);
    },
  );
  test(
    'response from an old session cannot update a disconnected dashboard',
    () async {
      await establish();
      final old = c.stats;
      ble.blocked = Completer<List<int>>();
      final read = c.refresh();
      await settle();
      await c.disconnect();
      ble.blocked!.complete(
        utf8.encode('{"seq":999,"ts_ms":1000,"battery_pct":1}'),
      );
      await read;
      expect(c.stats, same(old));
      expect(c.connected, isFalse);
      expect(c.reading, isFalse);
    },
  );
  test(
    'overlapping refresh requests do not issue concurrent GATT reads',
    () async {
      await establish();
      ble.blocked = Completer<List<int>>();
      final first = c.refresh();
      await settle();
      final count = ble.reads;
      await c.refresh();
      expect(ble.reads, count);
      ble.blocked!.complete(
        utf8.encode('{"seq":55,"ts_ms":1000,"battery_pct":68}'),
      );
      await first;
      expect(c.stats?.sequence, 55);
      expect(ble.maxConcurrentReads, 1);
    },
  );
  Future<void> until(bool Function() condition) async {
    for (var i = 0; i < 100 && !condition(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(condition(), isTrue);
  }

  void fastRetries({
    Future<void> Function(BatteryWidgetSnapshot?)? publish,
    bool background = false,
  }) {
    c.dispose();
    c = CompanionController(
      transport: ble,
      rememberDevice: false,
      retryDelay: (_) => const Duration(milliseconds: 40),
      batteryPublisher: publish,
      backgroundReconnect: background,
    );
  }

  test('unexpected loss reconnects once and restores subscription', () async {
    fastRetries();
    await establish();
    ble.links.add(LinkState.disconnected);
    await until(() => ble.connections == 2);
    expect(c.stale, isTrue);
    ble.links.add(LinkState.connected);
    await until(() => c.receivedCount == 2);
    expect(ble.subscriptions, 2);
    expect(c.retryAttempt, 0);
    expect(c.retryAt, isNull);
    expect(c.stale, isFalse);
  });

  test('intentional disconnect cancels pending automatic retry', () async {
    fastRetries();
    await establish();
    ble.links.add(LinkState.disconnected);
    await settle();
    await c.disconnect();
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(ble.connections, 1);
    expect(c.retryAt, isNull);
    c.setForeground(false);
    c.setForeground(true);
    await settle();
    expect(ble.connections, 1);
  });

  test('background pauses retry and foreground resumes it', () async {
    fastRetries();
    await establish();
    c.setForeground(false);
    ble.links.add(LinkState.disconnected);
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(ble.connections, 1);
    c.setForeground(true);
    await until(() => ble.connections == 2);
    ble.links.add(LinkState.connected);
    await until(() => c.receivedCount == 2);
  });

  test(
    'radio off preserves connection intent and radio on reconnects',
    () async {
      fastRetries();
      await establish();
      ble.radios.add(RadioState.off);
      await settle();
      expect(c.connected, isFalse);
      expect(c.retryAt, isNull);
      ble.radios.add(RadioState.ready);
      await until(() => ble.connections == 2);
    },
  );

  test('automatic reconnect can be disabled', () async {
    fastRetries();
    await establish();
    await c.setAutomaticReconnect(false);
    ble.links.add(LinkState.disconnected);
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(ble.connections, 1);
    await c.setAutomaticReconnect(true);
    await until(() => ble.connections == 2);
  });

  test(
    'widget receives real readings, disconnect state, and Forget clears it',
    () async {
      final snapshots = <BatteryWidgetSnapshot?>[];
      fastRetries(
        publish: (snapshot) async {
          snapshots.add(snapshot);
        },
      );
      await establish();
      expect(snapshots.last?.percent, 69);
      expect(snapshots.last?.connected, isTrue);
      await c.disconnect();
      await settle();
      expect(snapshots.last?.connected, isFalse);
      expect(snapshots.last?.updatedAt, c.receivedAt);
      await c.forget();
      expect(snapshots.last, isNull);
    },
  );
  test(
    'stale pairing stops retries and preserves repair instructions',
    () async {
      fastRetries();
      ble.discoveryFailure = StaleServiceCache();
      await establish();
      expect(c.pairingRecoveryRequired, isTrue);
      expect(c.connected, isFalse);
      expect(c.busy, isFalse);
      expect(c.retryAt, isNull);
      expect(c.error, contains('saved Bluetooth pairing is out of date'));
      c.setForeground(false);
      c.setForeground(true);
      ble.radios.add(RadioState.off);
      await settle();
      ble.radios.add(RadioState.ready);
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(ble.connections, 1);
      expect(c.pairingRecoveryRequired, isTrue);
      expect(c.error, contains('Re-pair the device'));
    },
  );
  test(
    'host authorization denial pauses retries and preserves the system pairing for repair',
    () async {
      fastRetries();
      ble.statsFailure = StateError(
        'CBATTErrorDomain Code=5 Authentication is insufficient.',
      );
      await establish();
      expect(c.hostAuthorizationRequired, true);
      expect(c.pairingRecoveryRequired, true);
      expect(c.retryAt, isNull);
      expect(c.error, contains('Approve this phone'));
      ble.links.add(LinkState.disconnected);
      await settle();
      c.setForeground(false);
      c.setForeground(true);
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(ble.connections, 1);
      expect(c.error, contains('Approve this phone'));
      ble.statsFailure = null;
      final retry = c.retryPhoneAuthorization();
      await settle();
      ble.links.add(LinkState.connected);
      await retry;
      await settle();
      expect(c.connected, true);
      expect(c.stats?.battery, 69);
      expect(c.hostAuthorizationRequired, false);
      expect(c.pairingRecoveryRequired, false);
      expect(c.error, isNull);
    },
  );
  test(
    'Android authorization denial asks for approval instead of a generic read error',
    () async {
      fastRetries();
      ble.statsFailure = StateError(
        'GATT exception from MAC address XX:XX:XX:XX:XX:XX, status 8 (GATT_INSUF_AUTHORIZATION or GATT_CONN_TIMEOUT), type BleGattOperation{description=\'CHARACTERISTIC_READ\'}.',
      );
      await establish();
      expect(c.hostAuthorizationRequired, true);
      expect(c.pairingRecoveryRequired, true);
      expect(c.retryAt, isNull);
      expect(c.error, startsWith('Approve this phone'));
      expect(c.error, isNot(contains('pair again')));
    },
  );
  test(
    'Android authentication failure explains approval and re-pairing',
    () async {
      fastRetries();
      ble.statsFailure = StateError(
        'GATT exception from MAC address XX:XX:XX:XX:XX:XX, status 5 (GATT_INSUF_AUTHENTICATION), type BleGattOperation{description=\'CHARACTERISTIC_READ\'}.',
      );
      await establish();
      expect(c.pairingRecoveryRequired, true);
      expect(c.error, contains('Approve this phone'));
      expect(c.error, contains('pair again'));
    },
  );
  test('background refresh respects explicit Disconnect', () async {
    await establish();
    await c.disconnect();
    final opens = ble.connections;
    expect(await c.backgroundRefresh(), false);
    expect(ble.connections, opens);
  });
  test(
    'background refresh reads and publishes an existing connection',
    () async {
      await establish();
      final count = c.receivedCount;
      expect(await c.backgroundRefresh(), true);
      expect(c.receivedCount, greaterThan(count));
    },
  );
  test('repair flow scans afresh and resumes after a new pairing', () async {
    fastRetries();
    ble.discoveryFailure = StaleServiceCache();
    await establish();
    await c.scanAfterPairingReset();
    expect(c.pairingRecoveryRequired, isFalse);
    expect(c.remembered, isNull);
    expect(c.selected, isNull);
    expect(c.phase, CompanionPhase.scanning);
    ble.discoveryFailure = null;
    await c.connect(const NearbyThor('new-id', 'Device', -50));
    ble.links.add(LinkState.connected);
    await until(() => c.notificationsRequested);
    expect(c.stats?.battery, 69);
    expect(c.error, isNull);
  });
  test(
    'iPhone background requests one native pending connection without retry timers',
    () async {
      fastRetries(background: true);
      await establish();
      c.setForeground(false);
      ble.links.add(LinkState.disconnected);
      await until(() => ble.connections == 2);
      expect(ble.backgroundRequests, [false, true]);
      expect(c.retryAt, isNull);
      ble.links.addError(StateError('Native request failed'));
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(ble.connections, 2);
      c.setForeground(true);
      await until(() => ble.connections == 3);
      expect(ble.backgroundRequests.last, isFalse);
    },
  );
  test(
    'connecting the saved device preserves the existing widget/live activity cache',
    () async {
      final snapshots = <BatteryWidgetSnapshot?>[];
      fastRetries(
        publish: (snapshot) async {
          snapshots.add(snapshot);
        },
      );
      c.remembered = const NearbyThor('thor', 'Device', 0);
      await establish();
      expect(snapshots, isNotEmpty);
      expect(snapshots.contains(null), isFalse);
      expect(snapshots.last?.percent, 69);
    },
  );
  test(
    'a control left over from a dropped link does not leave the next link without readings',
    () async {
      c.dispose();
      await ble.close();
      final controlBle = FakeControlBle();
      ble = controlBle;
      c = CompanionController(
        transport: controlBle,
        rememberDevice: false,
        retryDelay: (_) => const Duration(milliseconds: 40),
      );
      await establish();
      expect(c.receivedCount, 1);
      await until(() => controlBle.controlReads == 1);
      expect(c.controlBusy, isTrue);

      controlBle.links.add(LinkState.disconnected);
      await until(() => controlBle.connections == 2);
      controlBle.links.add(LinkState.connected);
      await settle();
      // The old control still owns the transport, so the first read waits.
      expect(c.receivedCount, 1);
      expect(c.notificationsRequested, isFalse);

      controlBle.control!.completeError(StateError('Connection changed'));
      // Well before the 1 s watchdog: the deferred read must replay itself.
      for (var i = 0; i < 30 && !c.notificationsRequested; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(c.receivedCount, 2);
      expect(c.notificationsRequested, isTrue);
      expect(controlBle.subscriptions, 1);
      // Recovered on the same link, not by the watchdog forcing a reconnect.
      expect(controlBle.connections, 2);
      expect(c.phase, CompanionPhase.connected);
    },
  );
  test(
    'remote input sends one bounded command and reports old hosts',
    () async {
      c.dispose();
      await ble.close();
      final input = FakeInputBle();
      ble = input;
      c = CompanionController(transport: input, rememberDevice: false);
      await establish();
      input.writes.clear();
      expect(
        await c.sendRemoteInput(
          'bottom',
          1,
          x: 0,
          y: 10000,
          x2: 10000,
          y2: 0,
          ms: 3000,
        ),
        isNull,
      );
      expect(input.writes.single, containsPair('set', 'input'));
      expect(input.writes.single, containsPair('target', 'bottom'));
      expect(input.writes.single, containsPair('ms', 3000));
      expect(await c.sendRemoteInput('top', 2), isNull);
      expect(input.writes.last.containsKey('x'), isFalse);
      input.error = 'Control failed: Unsupported control';
      expect(
        await c.sendRemoteInput('top', 0, x: 1, y: 1),
        'Update Thor Monitor to use remote touch.',
      );
    },
  );
}
