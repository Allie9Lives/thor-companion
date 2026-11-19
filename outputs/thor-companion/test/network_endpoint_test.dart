import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:thor_companion/file_transfer.dart';
import 'package:thor_companion/network_endpoint.dart';

FileConnection credentials({String? manual, List<String>? hosts}) =>
    FileConnection(
      hosts: hosts ?? ['192.168.1.20', '100.90.80.70'],
      port: 47183,
      pin: 'a' * 64,
      token: 'b' * 64,
      name: 'Device',
      manualHost: manual,
    );
void main() {
  test(
    'reachable VPN wins over slightly faster LAN, losing TLS client closes',
    () async {
      final vpn = Completer<String>(), closed = <String>[];
      final selection = selectNetworkEndpoint(
        credentials(),
        probe: (host) => isVpnAddress(host) ? vpn.future : Future.value(host),
        close: closed.add,
      );
      await Future<void>.delayed(Duration.zero);
      vpn.complete('100.90.80.70');
      final result = await selection;
      expect(result.host, '100.90.80.70');
      expect(closed, ['192.168.1.20']);
    },
  );
  test(
    'unreachable VPN does not hold a working local route until timeout',
    () async {
      final vpn = Completer<String>(), closed = <String>[];
      final selection = selectNetworkEndpoint(
        credentials(),
        preferenceWindow: const Duration(milliseconds: 5),
        timeout: const Duration(milliseconds: 100),
        probe: (host) => isVpnAddress(host) ? vpn.future : Future.value(host),
        close: closed.add,
      );
      final result = await selection;
      expect(result.host, '192.168.1.20');
      expect(vpn.isCompleted, false);
      vpn.complete('late-vpn');
      await Future<void>.delayed(Duration.zero);
      expect(closed, ['late-vpn']);
    },
  );
  test(
    'manual address is preferred but cannot prevent a reachable fallback',
    () async {
      final c = credentials(manual: 'thor.private');
      final chosen = await selectNetworkEndpoint(
        c,
        probe: (h) async => h,
        close: (_) {},
      );
      expect(chosen.host, 'thor.private');
      final fallback = await selectNetworkEndpoint(
        c,
        preferenceWindow: Duration.zero,
        probe: (h) async {
          if (h == 'thor.private') throw StateError('unreachable');
          return h;
        },
        close: (_) {},
      );
      expect(c.hosts, contains(fallback.host));
      expect(FileConnection.fromMap(c.toMap()).manualHost, 'thor.private');
      expect(
        FileConnection.fromMap(c.withManualHost(null).toMap()).manualHost,
        isNull,
      );
    },
  );
  test('old last-used IP is only a hint, not a permanent override', () async {
    final c = credentials().usingHost('192.168.1.20');
    final result = await selectNetworkEndpoint(
      c,
      probe: (h) async => h,
      close: (_) {},
    );
    expect(result.host, '100.90.80.70');
    expect(FileConnection.fromMap(c.toMap()).manualHost, isNull);
  });
  test(
    'all failed probes report offline, cancellation closes successful clients',
    () async {
      await expectLater(
        selectNetworkEndpoint<String>(
          credentials(),
          probe: (_) async => throw StateError('pin rejected'),
          close: (_) {},
        ),
        throwsStateError,
      );
      final closed = <String>[];
      await expectLater(
        selectNetworkEndpoint(
          credentials(),
          probe: (h) async => h,
          close: closed.add,
          cancelled: () => true,
        ),
        throwsStateError,
      );
      expect(closed.toSet(), credentials().hosts.toSet());
    },
  );
  test(
    'VPN classification does not mistake public or private LAN addresses',
    () {
      expect(isVpnAddress('100.64.0.1'), true);
      expect(isVpnAddress('100.127.255.254'), true);
      expect(isVpnAddress('fd7a:115c:a1e0::1'), true);
      for (final h in [
        '100.63.0.1',
        '100.128.0.1',
        '192.168.0.1',
        '10.1.2.3',
        'example.com',
      ]) {
        expect(isVpnAddress(h), false);
      }
    },
  );
}
