import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thor_companion/adaptive_network.dart';
import 'package:thor_companion/file_transfer.dart';

void main() {
  test(
    'network controls verify TLS pin, authenticate, preserve bytes and reject an old host',
    () async {
      final context = SecurityContext()
        ..useCertificateChain('test/fixtures/local-test.crt')
        ..usePrivateKey('test/fixtures/local-test.key');
      final server = await HttpServer.bindSecure(
        InternetAddress.loopbackIPv4,
        0,
        context,
      );
      final pem = await File('test/fixtures/local-test.crt').readAsString();
      final pin = sha256
          .convert(
            base64Decode(pem.replaceAll(RegExp(r'-----[^-]+-----|\s'), '')),
          )
          .toString();
      var old = false;
      List<int>? command;
      var authorized = 0;
      final sub = server.listen((r) async {
        expect(
          r.headers.value(HttpHeaders.authorizationHeader),
          'Bearer ${'a' * 64}',
        );
        authorized++;
        Map<String, dynamic> body;
        if (r.uri.path == '/v1/status') {
          body = {'monitoring': true, 'adaptive_control': old ? 0 : 1};
        } else if (r.uri.path == '/v1/link/control') {
          expect(r.method, 'POST');
          command = await r.fold<List<int>>([], (a, b) => a..addAll(b));
          body = {
            'bytes': base64Encode(utf8.encode('{"ack":"retry-id","error":""}')),
          };
        } else {
          body = {
            'bytes': base64Encode(
              utf8.encode(
                r.uri.queryParameters['kind'] == 'live'
                    ? 'n=1 b=70'
                    : '{"battery_pct":70}',
              ),
            ),
          };
        }
        r.response.headers.contentType = ContentType.json;
        r.response.write(jsonEncode(body));
        await r.response.close();
      });
      FileConnection connection(String p) => FileConnection(
        hosts: ['127.0.0.1'],
        port: server.port,
        pin: p,
        token: 'a' * 64,
        name: 'Thor',
      );
      final n = PinnedControlNetwork(connection(pin), '127.0.0.1');
      try {
        await n.probe();
        expect(utf8.decode(await n.read('stats')), contains('70'));
        final bytes = utf8.encode(
          '{"id":"retry-id","set":"text","value":"hello"}',
        );
        expect(utf8.decode(await n.command(bytes)), contains('retry-id'));
        expect(command, bytes);
        final before = authorized,
            bad = PinnedControlNetwork(connection('0' * 64), '127.0.0.1');
        await expectLater(bad.probe(), throwsA(anything));
        bad.close();
        expect(authorized, before);
        old = true;
        await expectLater(n.probe(), throwsA(isA<StateError>()));
      } finally {
        n.close();
        await sub.cancel();
        await server.close(force: true);
      }
    },
  );
}
