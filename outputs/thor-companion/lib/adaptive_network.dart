import 'dart:convert';
import 'file_transfer.dart';

abstract class ControlNetwork {
  Future<void> probe();
  Future<List<int>> read(String kind);
  Future<List<int>> command(List<int> bytes);
  void close();
}

/// Every request has its own cancellable TLS client, so a timeout does not leave
/// an HTTP write waiting to run after a fallback command.
class PinnedControlNetwork implements ControlNetwork {
  PinnedControlNetwork(this.connection, this.host);
  final FileConnection connection;
  final String host;
  final Set<ThorFiles> _active = {};
  bool _closed = false;
  Future<T> _request<T>(Future<T> Function(ThorFiles) action) async {
    if (_closed) throw StateError('Network link closed');
    final client = ThorFiles(connection, host);
    _active.add(client);
    try {
      return await action(client).timeout(const Duration(milliseconds: 2500));
    } finally {
      _active.remove(client);
      client.close();
    }
  }

  List<int> _bytes(Map<String, dynamic> j) {
    final s = j['bytes'];
    if (s is! String || s.length > 100000) {
      throw const FormatException('Invalid network reading');
    }
    return base64Decode(s);
  }

  @override
  Future<void> probe() => _request((c) async {
    final j = await c.get('status');
    if (j['adaptive_control'] != 1 || j['monitoring'] != true) {
      throw StateError('Host network controls unavailable');
    }
    // Status alone is insufficient: verify the actual telemetry endpoint too.
    final bytes = _bytes(await c.get('link/read', {'kind': 'live'}));
    if (!RegExp(r'^n=\d+ b=\d+$').hasMatch(utf8.decode(bytes))) {
      throw const FormatException('Invalid host heartbeat');
    }
  });
  @override
  Future<List<int>> read(String kind) =>
      _request((c) async => _bytes(await c.get('link/read', {'kind': kind})));
  @override
  Future<List<int>> command(List<int> bytes) => _request((c) async {
    final r = await c.request('POST', 'link/control', {});
    r.contentLength = bytes.length;
    r.add(bytes);
    return _bytes(await c.response(await r.close()));
  });
  @override
  void close() {
    _closed = true;
    for (final c in _active.toList()) {
      c.close();
    }
    _active.clear();
  }
}
