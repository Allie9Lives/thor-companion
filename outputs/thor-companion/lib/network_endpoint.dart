import 'dart:async';
import 'dart:io';
import 'file_transfer.dart';

bool isVpnAddress(String host) {
  final ip = InternetAddress.tryParse(host);
  if (ip == null) return false;
  final b = ip.rawAddress;
  // Shared address space and the IPv6 mesh prefix. Other VPN routes work too;
  // they are selected by the same pinned reachability check as local addresses.
  return ip.type == InternetAddressType.IPv4
      ? b[0] == 100 && b[1] >= 64 && b[1] <= 127
      : b[0] == 0xfd && b[1] == 0x7a && b[2] == 0x11 && b[3] == 0x5c;
}

class NetworkEndpoint<T> {
  NetworkEndpoint(this.host, this.value, this.elapsed);
  final String host;
  final T value;
  final Duration elapsed;
}

/// Race read-only, authenticated probes. Keep a working route until its
/// replacement is verified; abandon all losing clients, including late replies.
Future<NetworkEndpoint<T>> selectNetworkEndpoint<T>(
  FileConnection connection, {
  required Future<T> Function(String host) probe,
  required void Function(T value) close,
  Duration timeout = const Duration(milliseconds: 2500),
  Duration preferenceWindow = const Duration(milliseconds: 180),
  bool Function()? cancelled,
}) async {
  final hosts = connection.candidateHosts;
  if (hosts.isEmpty) {
    throw StateError('Link network access over Bluetooth first.');
  }
  final done = Completer<NetworkEndpoint<T>>();
  NetworkEndpoint<T>? fallback;
  var remaining = hosts.length;
  Timer? grace;
  bool preferred(String host) => connection.manualHost != null
      ? host == connection.manualHost
      : isVpnAddress(host);
  void finish() {
    if (done.isCompleted) return;
    grace?.cancel();
    if (cancelled?.call() == true) {
      if (fallback != null) close(fallback!.value);
      fallback = null;
      done.completeError(StateError('Connection changed'));
    } else if (fallback != null) {
      done.complete(fallback);
      fallback = null;
    } else {
      done.completeError(
        StateError('Could not reach the Thor over Wi-Fi or VPN.'),
      );
    }
  }

  for (final host in hosts) {
    unawaited(() async {
      final watch = Stopwatch()..start();
      var expired = false;
      try {
        final task = probe(host).then((value) {
          if (expired) close(value);
          return value;
        });
        final value = await task.timeout(
          timeout,
          onTimeout: () {
            expired = true;
            throw TimeoutException('Network probe timed out');
          },
        );
        final result = NetworkEndpoint(host, value, watch.elapsed);
        if (done.isCompleted || cancelled?.call() == true) {
          close(value);
        } else if (preferred(host)) {
          if (fallback != null) close(fallback!.value);
          fallback = result;
          finish();
        } else {
          if (fallback == null) {
            fallback = result;
            grace = Timer(preferenceWindow, finish);
          } else {
            close(value);
          }
        }
      } catch (_) {
        // Each probe owns and closes its failed TLS client.
      } finally {
        remaining--;
        if (remaining == 0) finish();
      }
    }());
  }
  return done.future;
}

class ReachableFiles {
  ReachableFiles(this.client, this.status);
  final ThorFiles client;
  final Map<String, dynamic> status;
}

Future<NetworkEndpoint<ReachableFiles>> connectFilesAutomatically(
  FileConnection connection, {
  bool Function()? cancelled,
}) => selectNetworkEndpoint(
  connection,
  cancelled: cancelled,
  close: (result) => result.client.close(),
  probe: (host) async {
    final client = ThorFiles(connection, host);
    try {
      final status = await client
          .get('status')
          .timeout(const Duration(milliseconds: 2400));
      if (status['version'] is! String || status['monitoring'] is! bool) {
        throw StateError('Update Thor Monitor to use network access.');
      }
      return ReachableFiles(client, status);
    } catch (_) {
      client.close();
      rethrow;
    }
  },
);
