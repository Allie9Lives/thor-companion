import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';

const fileBridge = MethodChannel('com.alan.thorCompanion/files');

class FileConnection {
  FileConnection({
    required this.hosts,
    required this.port,
    required this.pin,
    required this.token,
    required this.name,
    this.preferredHost,
  });
  factory FileConnection.fromMap(Map<String, dynamic> j) {
    final hosts = (j['hosts'] as List).cast<String>();
    final port = j['port'];
    final pin = j['pin'], token = j['token'];
    if (port is! int ||
        port < 1 ||
        port > 65535 ||
        pin is! String ||
        token is! String ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(pin) ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(token) ||
        hosts.length > 16 ||
        hosts.any((s) => !validHost(s))) {
      throw const FormatException('Invalid Thor file connection');
    }
    return FileConnection(
      hosts: hosts,
      port: port,
      pin: pin,
      token: token,
      name: j['name'] as String? ?? 'AYN Thor',
      preferredHost:
          j['preferredHost'] is String &&
              validHost(j['preferredHost'] as String)
          ? j['preferredHost'] as String
          : null,
    );
  }
  static bool validHost(String host) =>
      host.isNotEmpty &&
      host.length <= 253 &&
      !host.contains(RegExp(r'[\s/@?#\\]')) &&
      !host.contains('://');
  final List<String> hosts;
  final int port;
  final String pin, token, name;
  final String? preferredHost;
  String get defaultHost => preferredHost ?? (hosts.isEmpty ? '' : hosts.first);
  FileConnection usingHost(String host) => FileConnection(
    hosts: hosts,
    port: port,
    pin: pin,
    token: token,
    name: name,
    preferredHost: host,
  );
  Map<String, dynamic> toMap() => {
    'hosts': hosts,
    'port': port,
    'pin': pin,
    'token': token,
    'name': name,
    if (preferredHost != null) 'preferredHost': preferredHost,
  };
}

class ThorFiles {
  ThorFiles(this.connection, String host) : host = host.trim() {
    if (!FileConnection.validHost(this.host)) {
      throw const FormatException('Enter an IP address or hostname');
    }
    client = HttpClient(context: SecurityContext(withTrustedRoots: false))
      ..connectionTimeout = const Duration(seconds: 10)
      ..idleTimeout = const Duration(seconds: 15)
      ..badCertificateCallback = ((certificate, h, p) =>
          h == this.host &&
          p == connection.port &&
          sha256.convert(certificate.der).toString() == connection.pin);
  }
  final FileConnection connection;
  final String host;
  late HttpClient client;
  Uri url(String route, Map<String, String> query) => Uri(
    scheme: 'https',
    host: host,
    port: connection.port,
    path: '/v1/$route',
    queryParameters: query.isEmpty ? null : query,
  );
  Future<HttpClientRequest> request(
    String method,
    String route,
    Map<String, String> query,
  ) async {
    final r = await client.openUrl(method, url(route, query));
    r.followRedirects = false;
    r.headers.set(
      HttpHeaders.authorizationHeader,
      'Bearer ${connection.token}',
    );
    return r;
  }

  Future<Map<String, dynamic>> response(HttpClientResponse r) async {
    final bytes = <int>[];
    await for (final chunk in r.timeout(const Duration(seconds: 15))) {
      bytes.addAll(chunk);
      if (bytes.length > 1024 * 1024) {
        throw const FormatException('File response too large');
      }
    }
    final j = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    if (r.statusCode != 200) {
      throw StateError(j['error'] as String? ?? 'File request failed');
    }
    return j;
  }

  Future<Map<String, dynamic>> get(
    String route, [
    Map<String, String> query = const {},
  ]) async => response(await (await request('GET', route, query)).close());
  Future<void> upload(
    String root,
    String folder,
    String name,
    File file,
    void Function(int, int) progress,
  ) async {
    final size = await file.length();
    if (size > 64 * 1024 * 1024 * 1024) throw StateError('File exceeds 64 GiB');
    final r = await request('PUT', 'file', {
      'root': root,
      'path': folder,
      'name': name,
    });
    r.contentLength = size;
    var sent = 0;
    await r
        .addStream(
          file.openRead().map((chunk) {
            sent += chunk.length;
            progress(sent, size);
            return chunk;
          }),
        )
        .timeout(const Duration(minutes: 30));
    await response(await r.close());
  }

  Future<void> download(
    String root,
    String path,
    File destination,
    void Function(int, int) progress,
  ) async {
    final r = await (await request('GET', 'file', {
      'root': root,
      'path': path,
    })).close();
    if (r.statusCode != 200) {
      await response(r);
      return;
    }
    final size = r.contentLength;
    if (size < 0 || size > 64 * 1024 * 1024 * 1024) {
      throw StateError('Invalid file size');
    }
    final sink = destination.openWrite();
    var received = 0;
    try {
      await for (final chunk in r.timeout(const Duration(seconds: 30))) {
        received += chunk.length;
        if (received > size) throw StateError('File size changed');
        sink.add(chunk);
        progress(received, size);
      }
      await sink.flush();
      if (received != size) throw StateError('Incomplete download');
    } finally {
      await sink.close();
    }
  }

  Future<Uint8List> capture(int mode, void Function(int, int) progress) async {
    if (mode < 0 || mode > 2) throw ArgumentError('Invalid screen');
    final r = await request('POST', 'capture', {'mode': '$mode'});
    r.contentLength = 0;
    final reply = await r.close().timeout(const Duration(seconds: 45));
    if (reply.statusCode != 200) {
      await response(reply);
      throw StateError('Capture failed');
    }
    final length = reply.contentLength;
    if (length < 10 ||
        length > 12 * 1024 * 1024 ||
        reply.headers.contentType?.mimeType !=
            'application/x-thor-screenshot') {
      throw StateError('Invalid screenshot response. Update Thor Monitor.');
    }
    final buffer = BytesBuilder(copy: false);
    var count = 0;
    await for (final bytes in reply.timeout(const Duration(seconds: 25))) {
      count += bytes.length;
      if (count > length) throw StateError('Screenshot exceeded its size');
      buffer.add(bytes);
      progress(count, length);
    }
    if (count != length) {
      throw StateError('Screenshot transfer was interrupted');
    }
    return buffer.takeBytes();
  }

  void close() => client.close(force: true);
}
