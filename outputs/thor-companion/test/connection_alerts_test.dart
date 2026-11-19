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
      expect(t.wifi(state(1, 'Home'), o, 'Device', now), isEmpty);
      expect(
        t.wifi(state(2, 'Library'), o, 'Device', now).single.body,
        contains('Library'),
      );
      expect(
        t
            .wifi(state(3, 'Library', captive: true), o, 'Device', now)
            .map((a) => a.key),
        ['wifiSignIn'],
      );
      expect(t.wifi(state(4, 'Library'), o, 'Device', now), isEmpty);
      expect(
        t.wifi(state(5, '', connected: false), o, 'Device', now).single.key,
        'wifiLost',
      );
      expect(t.wifi(state(6, 'Home', age: 120000), o, 'Device', now), isEmpty);
      expect(t.wifi(state(6, 'Home'), o, 'Device', now), isEmpty);
    },
  );
  test(
    'Bluetooth loss is scheduled with the OS, cancelled on quick reconnect, restored once',
    () {
      final t = ConnectionAlertTracker(), o = options();
      List<BatteryAlert> at(
        bool up,
        int s, {
        bool eligible = true,
        List<String>? cancel,
      }) => t.bluetooth(
        up,
        eligible,
        o,
        'Device',
        now.add(Duration(seconds: s)),
        cancel: cancel,
      );
      expect(at(false, 0), isEmpty);
      expect(at(true, 0), isEmpty);
      final lost = at(false, 1).single;
      expect([lost.key, lost.delay], ['bluetoothLost', 15]);
      expect(lost.toMap()['delay'], '15');
      expect(at(false, 10), isEmpty);
      final cancel = <String>[];
      expect(at(true, 12, cancel: cancel), isEmpty);
      expect(cancel, ['bluetoothLost']);
      expect(at(false, 20).single.key, 'bluetoothLost');
      expect(at(false, 40), isEmpty);
      final none = <String>[];
      expect(at(true, 41, cancel: none).single.key, 'bluetoothBack');
      expect(none, isEmpty);
      expect(at(false, 50).single.key, 'bluetoothLost');
      final sleep = <String>[];
      expect(at(false, 51, eligible: false, cancel: sleep), isEmpty);
      expect(sleep, ['bluetoothLost']);
      expect(at(true, 52), isEmpty);
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
    'same pinned device retains LAN and VPN addresses, different device cannot inherit',
    () {
      FileConnection link(List<String> h, String pin, {String? manual}) =>
          FileConnection(
            hosts: h,
            port: 47183,
            pin: pin,
            token: 'b' * 64,
            name: 'Device',
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
