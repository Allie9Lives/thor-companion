import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thor_companion/file_transfer.dart';
import 'package:thor_companion/battery_alerts.dart';

void main() {
  late HttpServer server;
  late FileConnection connection;
  late ThorFiles files;
  late Directory temporary;
  var calls = 0;
  String? authorization;
  List<int> uploaded = [];
  final captureBytes = List<int>.generate(256 * 1024, (i) => i % 256);
  String? captureMode;
  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('thor-files-test');
    final context = SecurityContext()
      ..useCertificateChain('test/fixtures/local-test.crt')
      ..usePrivateKey('test/fixtures/local-test.key');
    server = await HttpServer.bindSecure(
      InternetAddress.loopbackIPv4,
      0,
      context,
    );
    calls = 0;
    authorization = null;
    final pem = await File('test/fixtures/local-test.crt').readAsString();
    final der = base64Decode(pem.replaceAll(RegExp(r'-----[^-]+-----|\s'), ''));
    connection = FileConnection(
      hosts: ['127.0.0.1'],
      port: server.port,
      pin: sha256.convert(der).toString(),
      token: 'a' * 64,
      name: "Allie's AYN Thor Max",
    );
    files = ThorFiles(connection, '127.0.0.1');
    server.listen((request) async {
      calls++;
      authorization = request.headers.value(HttpHeaders.authorizationHeader);
      if (request.uri.path == '/v1/capture') {
        expect(request.method, 'POST');
        captureMode = request.uri.queryParameters['mode'];
        request.response.headers.contentType = ContentType(
          'application',
          'x-thor-screenshot',
        );
        request.response.contentLength = captureBytes.length;
        request.response.add(captureBytes);
      } else if (request.method == 'PUT') {
        uploaded = await request.fold<List<int>>([], (a, b) => a..addAll(b));
        request.response.write('{"ok":true}');
      } else if (request.uri.path == '/v1/file') {
        request.response.contentLength = uploaded.length;
        request.response.add(uploaded);
      } else {
        request.response.headers.contentType = ContentType.json;
        request.response.write('{"roots":[]}');
      }
      await request.response.close();
    });
  });
  tearDown(() async {
    files.close();
    await server.close(force: true);
    await temporary.delete(recursive: true);
  });
  test('TLS pin is required before any bearer credential is sent', () async {
    final wrong = ThorFiles(
      FileConnection(
        hosts: connection.hosts,
        port: server.port,
        pin: '0' * 64,
        token: connection.token,
        name: 'Thor',
      ),
      '127.0.0.1',
    );
    await expectLater(wrong.get('roots'), throwsA(isA<HandshakeException>()));
    wrong.close();
    expect(calls, 0);
    expect(authorization, isNull);
    expect(await files.get('roots'), {'roots': []});
    expect(authorization, 'Bearer ${connection.token}');
  });
  test('streamed upload and download preserve file bytes', () async {
    final bytes = List<int>.generate(1024 * 1024 + 17, (i) => (i * 23) % 256);
    final source = File('${temporary.path}/source');
    await source.writeAsBytes(bytes);
    var lastProgress = 0;
    await files.upload('sd', 'ROMs', "L'été.bin", source, (n, total) {
      lastProgress = n;
      expect(n, lessThanOrEqualTo(total));
    });
    expect(lastProgress, bytes.length);
    expect(sha256.convert(uploaded), sha256.convert(bytes));
    final destination = File('${temporary.path}/download');
    await files.download(
      'sd',
      "ROMs/L'été.bin",
      destination,
      (n, total) => lastProgress = n,
    );
    expect(
      sha256.convert(await destination.readAsBytes()),
      sha256.convert(bytes),
    );
  });
  test('network capture streams authenticated bytes with progress', () async {
    var received = 0;
    final bytes = await files.capture(2, (n, total) {
      received = n;
      expect(total, captureBytes.length);
    });
    expect(bytes, captureBytes);
    expect(received, captureBytes.length);
    expect(captureMode, '2');
    expect(authorization, 'Bearer ${connection.token}');
    expect(calls, 1);
    await expectLater(files.capture(3, (_, _) {}), throwsArgumentError);
    expect(calls, 1);
  });
  test('connection rejects malformed hosts and credentials', () {
    expect(
      () => FileConnection.fromMap({...connection.toMap(), 'token': 'weak'}),
      throwsFormatException,
    );
    for (final host in ['http://example.com', 'a/b', 'x y', 'user@host']) {
      expect(FileConnection.validHost(host), isFalse);
    }
  });
  test('notification title uses the configured device name', () {
    final alert = const BatteryAlert(
      'low10',
      'Battery is low',
      '10% remaining.',
    ).forDevice("Allie's AYN Thor Max");
    expect(alert.title, "Allie's AYN Thor Max");
    expect(alert.body, contains('10%'));
  });
}
