import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';

class AppIconUnavailable implements Exception {
  const AppIconUnavailable();
}

const fileBridge = MethodChannel('com.alan.thorCompanion/files');

class FileConnection {
  FileConnection({
    required this.hosts,
    required this.port,
    required this.pin,
    required this.token,
    required this.name,
    this.preferredHost,
    this.manualHost,
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
      throw const FormatException('Invalid device file connection');
    }
    return FileConnection(
      hosts: hosts,
      port: port,
      pin: pin,
      token: token,
      name: j['name'] as String? ?? 'AYN Thor',
      manualHost: j['manualHost'] is String && validHost(j['manualHost'])
          ? j['manualHost'] as String
          : null,
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
  final String? preferredHost, manualHost;
  List<String> get candidateHosts =>
      {?manualHost, ?preferredHost, ...hosts}.toList();
  String get defaultHost =>
      manualHost ?? preferredHost ?? (hosts.isEmpty ? '' : hosts.first);
  FileConnection retainingAddresses(FileConnection? previous) => FileConnection(
    hosts: {
      ...hosts,
      if (previous?.pin == pin) ...previous!.hosts,
    }.take(16).toList(),
    port: port,
    pin: pin,
    token: token,
    name: name,
    preferredHost: preferredHost,
    manualHost: manualHost,
  );
  FileConnection usingHost(String host) => FileConnection(
    hosts: hosts,
    port: port,
    pin: pin,
    token: token,
    name: name,
    preferredHost: host,
    manualHost: manualHost,
  );
  FileConnection withManualHost(String? host) => FileConnection(
    hosts: hosts,
    port: port,
    pin: pin,
    token: token,
    name: name,
    preferredHost: preferredHost,
    manualHost: host,
  );
  Map<String, dynamic> toMap() => {
    'hosts': hosts,
    'port': port,
    'pin': pin,
    'token': token,
    'name': name,
    if (preferredHost != null) 'preferredHost': preferredHost,
    if (manualHost != null) 'manualHost': manualHost,
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

  /// Opens the virtual controller channel: one JSON event per line until closed.
  Future<LivePad> livePad() async {
    final socket = await SecureSocket.connect(
      host,
      connection.port,
      context: SecurityContext(withTrustedRoots: false),
      onBadCertificate: (c) =>
          sha256.convert(c.der).toString() == connection.pin,
      timeout: const Duration(seconds: 10),
    );
    socket.write(
      'POST /v1/input HTTP/1.1\r\nHost: $host\r\n'
      'Authorization: Bearer ${connection.token}\r\n\r\n',
    );
    await socket.flush();
    return LivePad(socket);
  }

  /// Raw H.264 for one screen (0 top, 1 bottom) until cancelled. A still screen
  /// sends nothing for a while, so the body has no read timeout.
  Future<HttpClientResponse> liveStream(int screen, {int quality = 0}) async {
    final r = await (await request('GET', 'stream', {
      'screen': '$screen',
      'quality': '$quality',
    })).close();
    if (r.statusCode == 404) {
      await r.drain<void>();
      throw StateError('Update Thor Monitor to use live view.');
    }
    if (r.statusCode != 200) {
      await response(r);
      throw StateError('Live view is unavailable.');
    }
    return r;
  }

  Future<Map<String, dynamic>> recording(
    String action, {
    String token = '',
    int mode = 0,
    int quality = 1,
    int fps = 60,
  }) async {
    if (!const ['start', 'status', 'stop', 'clear'].contains(action) ||
        (token.isNotEmpty && !RegExp(r'^[a-f0-9]{24}$').hasMatch(token)) ||
        mode < 0 ||
        mode > 2 ||
        ![0, 1].contains(quality) ||
        ![30, 60].contains(fps)) {
      throw ArgumentError('Invalid recording request');
    }
    final request = await this.request(
      action == 'status' ? 'GET' : 'POST',
      'record/$action',
      {'token': token, 'mode': '$mode', 'quality': '$quality', 'fps': '$fps'},
    );
    if (action != 'status') request.contentLength = 0;
    // Stopping a long clip joins its segments on the Thor before replying.
    return response(
      await request.close().timeout(const Duration(seconds: 120)),
    );
  }

  Future<void> recordingFile(
    String token,
    int screen,
    File destination,
    void Function(int, int) progress,
  ) async {
    if (!RegExp(r'^[a-f0-9]{24}$').hasMatch(token) ||
        !const [0, 1].contains(screen)) {
      throw ArgumentError('Invalid recording');
    }
    final reply = await (await request('GET', 'record/file', {
      'token': token,
      'screen': '$screen',
    })).close().timeout(const Duration(seconds: 25));
    if (reply.statusCode != 200) {
      await response(reply);
      return;
    }
    final size = reply.contentLength;
    if (size < 128 ||
        size > 2048 * 1024 * 1024 ||
        reply.headers.contentType?.mimeType != 'video/mp4') {
      throw StateError('Invalid recording file');
    }
    final sink = destination.openWrite();
    var received = 0;
    try {
      await for (final chunk in reply.timeout(const Duration(seconds: 30))) {
        received += chunk.length;
        if (received > size) throw StateError('Recording size changed');
        sink.add(chunk);
        progress(received, size);
      }
      await sink.flush();
      if (received != size) {
        throw StateError('Recording transfer was interrupted');
      }
    } finally {
      await sink.close();
    }
  }

  Future<Uint8List> appIcon(String package, String revision) async {
    final reply = await (await request('GET', 'app-icon', {
      'package': package,
      'revision': revision,
    })).close();
    if (reply.statusCode != 200) {
      await reply.drain<void>();
      if (reply.statusCode == 401 || reply.statusCode == 403) {
        throw const HttpException('Icon access needs linking');
      }
      throw const AppIconUnavailable();
    }
    if (reply.contentLength < 24 ||
        reply.contentLength > 32768 ||
        reply.headers.contentType?.mimeType != 'image/png') {
      throw StateError('Invalid app icon');
    }
    final buffer = BytesBuilder(copy: false);
    var received = 0;
    await for (final bytes in reply.timeout(const Duration(seconds: 3))) {
      received += bytes.length;
      if (received > reply.contentLength) throw StateError('Icon too large');
      buffer.add(bytes);
    }
    if (received != reply.contentLength) throw StateError('Incomplete icon');
    return buffer.takeBytes();
  }

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

/// Virtual controller events for Thor Monitor's /v1/input channel.
class LivePad {
  LivePad(this._socket) {
    _ping = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _write('{"t":"p"}'),
    );
    _socket.listen(
      (data) {
        final text = ascii.decode(data, allowInvalid: true);
        if (!_answered) {
          _answered = true;
          if (!text.startsWith('HTTP/1.1 200')) {
            error = text.contains('Recovery')
                ? 'Advanced controls are unavailable. Check Recovery setup on the device.'
                : 'Update Thor Monitor to use the controller.';
          }
        } else if (text.contains('error')) {
          error = 'The device rejected a controller input.';
        }
      },
      onDone: () => closed = true,
      onError: (_) => closed = true,
      cancelOnError: true,
    );
  }
  final SecureSocket _socket;
  late final Timer _ping;
  bool _answered = false, closed = false;
  String? error;

  void _write(String line) {
    if (closed) return;
    try {
      _socket.write('$line\n');
    } catch (_) {
      closed = true;
    }
  }

  void button(int key, bool down) =>
      _write(jsonEncode({'t': 'b', 'k': key, 'd': down ? 1 : 0}));

  /// Tap (0), swipe (1), Back (2) or Home (3) on screen 0 (top) or 1 (bottom).
  void input(int screen, int action, Map<String, int> points) =>
      _write(jsonEncode({'t': 'i', 'value': action, 'd': screen, ...points}));
  void axes(Map<String, int> values) =>
      _write(jsonEncode({'t': 'a', ...values}));
  void close() {
    _ping.cancel();
    closed = true;
    _socket.destroy();
  }
}
