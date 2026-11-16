import 'package:flutter_test/flutter_test.dart';
import 'package:thor_companion/connection_alerts.dart';
import 'package:thor_companion/battery_alerts.dart';
import 'package:thor_companion/file_transfer.dart';

void main() {
  final now = DateTime(2026, 11, 15, 10);
  BatteryAlertOptions options() => BatteryAlertOptions(
    enabled: true,
    wifiChanged: true,
    wifiLost: true,
    wifiSignIn: true,
    bluetoothLost: true,
    bluetoothBack: true,
  );
  Map<String, dynamic> state(
    int event,
    String name, {
    bool connected = true,
    bool captive = false,
    int age = 0,
  }) => {
    'known': true,
    'event': event,
    'name': name,
    'connected': connected,
    'captive': captive,
    'changed_at': now.millisecondsSinceEpoch - age,
  };
  test(
    'Wi-Fi baseline silent, network changes named, captive transitions distinct, no stale replay',
    () {
      final t = ConnectionAlertTracker(), o = options();
      expect(t.wifi(state(1, 'Home'), o, 'Thor', now), isEmpty);
      expect(
        t.wifi(state(2, 'Library'), o, 'Thor', now).single.body,
        contains('Library'),
      );
      expect(
        t
            .wifi(state(3, 'Library', captive: true), o, 'Thor', now)
            .map((a) => a.key),
        ['wifiSignIn'],
      );
      expect(t.wifi(state(4, 'Library'), o, 'Thor', now), isEmpty);
      expect(
        t.wifi(state(5, '', connected: false), o, 'Thor', now).single.key,
        'wifiLost',
      );
      expect(t.wifi(state(6, 'Home', age: 120000), o, 'Thor', now), isEmpty);
      expect(t.wifi(state(6, 'Home'), o, 'Thor', now), isEmpty);
    },
  );
  test(
    'Bluetooth debounces loss, restores once and suppresses deliberate sleep/disconnect',
    () {
      final t = ConnectionAlertTracker(), o = options();
      expect(t.bluetooth(false, true, o, 'Thor', now), isEmpty);
      expect(t.bluetooth(true, true, o, 'Thor', now), isEmpty);
      expect(t.bluetooth(false, true, o, 'Thor', now), isEmpty);
      expect(
        t.bluetooth(
          false,
          true,
          o,
          'Thor',
          now.add(const Duration(seconds: 14)),
        ),
        isEmpty,
      );
      expect(
        t
            .bluetooth(
              false,
              true,
              o,
              'Thor',
              now.add(const Duration(seconds: 16)),
            )
            .single
            .key,
        'bluetoothLost',
      );
      expect(
        t.bluetooth(
          false,
          true,
          o,
          'Thor',
          now.add(const Duration(seconds: 30)),
        ),
        isEmpty,
      );
      expect(
        t
            .bluetooth(
              true,
              true,
              o,
              'Thor',
              now.add(const Duration(seconds: 31)),
            )
            .single
            .key,
        'bluetoothBack',
      );
      expect(t.bluetooth(false, false, o, 'Thor', now), isEmpty);
      expect(t.bluetooth(true, true, o, 'Thor', now), isEmpty);
    },
  );
  test('notification options roundtrip with new events off by default', () {
    final old = BatteryAlertOptions.fromMap({'enabled': true});
    expect(old.wifiChanged, isFalse);
    final o = BatteryAlertOptions.fromMap(options().toMap());
    expect(o.wifiSignIn, isTrue);
    expect(o.bluetoothBack, isTrue);
  });
  test(
    'same pinned Thor retains LAN and VPN addresses, different Thor cannot inherit',
    () {
      FileConnection link(List<String> h, String pin, {String? manual}) =>
          FileConnection(
            hosts: h,
            port: 47183,
            pin: pin,
            token: 'b' * 64,
            name: 'Thor',
            manualHost: manual,
          );
      final old = link(
        ['192.168.1.2', '100.70.80.90'],
        'a' * 64,
        manual: 'thor.private',
      );
      final next = link(['192.168.2.3'], 'a' * 64).retainingAddresses(old);
      expect(next.hosts, ['192.168.2.3', '192.168.1.2', '100.70.80.90']);
      expect(next.manualHost, isNull);
      expect(
        old.withManualHost(null).retainingAddresses(old).manualHost,
        isNull,
      );
      expect(FileConnection.fromMap(next.toMap()).hosts, next.hosts);
      expect(link(['192.168.2.3'], 'c' * 64).retainingAddresses(old).hosts, [
        '192.168.2.3',
      ]);
    },
  );
}
