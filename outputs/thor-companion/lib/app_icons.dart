import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'file_transfer.dart';
import 'package:flutter/material.dart';

/// Device/version-scoped files. Cached icons do not wait behind network requests.
class AppIconCache {
  AppIconCache(
    this.device, {
    Future<Directory?> Function()? directory,
    Future<ThorFiles?> Function()? network,
  }) : _directoryProvider = directory ?? _nativeDirectory,
       _networkProvider = network ?? _nativeNetwork;
  final String device;
  final Future<Directory?> Function() _directoryProvider;
  final Future<ThorFiles?> Function() _networkProvider;
  Future<Directory?>? _directory;
  Future<ThorFiles?>? _network;
  ThorFiles? _transport;
  bool _offline = false, _closed = false;
  Future<void> _queue = Future.value();
  DateTime? _retryAt;
  final _failed = <String>{};
  final _pending = <String, Future<Uint8List?>>{};
  static Future<Directory?> _nativeDirectory() async {
    final path = await fileBridge.invokeMethod<String>('iconCacheDirectory');
    return path == null ? null : Directory(path);
  }

  static Future<ThorFiles?> _nativeNetwork() async {
    final saved = await fileBridge.invokeMapMethod<String, dynamic>(
      'loadConnection',
    );
    if (saved == null) return null;
    final connection = FileConnection.fromMap(saved);
    return ThorFiles(connection, connection.defaultHost);
  }

  static bool validPng(Uint8List bytes) {
    if (bytes.length < 24 ||
        bytes.length > 32768 ||
        bytes[0] != 137 ||
        ascii.decode(bytes.sublist(1, 4), allowInvalid: true) != 'PNG') {
      return false;
    }
    final header = ByteData.sublistView(bytes),
        width = header.getUint32(16),
        height = header.getUint32(20);
    return width > 0 && height > 0 && width <= 128 && height <= 128;
  }

  Future<Uint8List?> get(String package, String? revision) {
    if (revision == null ||
        !RegExp(r'^[a-f0-9]{16}$').hasMatch(revision) ||
        !RegExp(
          r'^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z][A-Za-z0-9_]*)+$',
        ).hasMatch(package)) {
      return Future.value(null);
    }
    if (_offline && _retryAt != null && DateTime.now().isAfter(_retryAt!)) {
      _offline = false;
      _network = null;
      _transport = null;
      for (final key in _failed) {
        _pending.remove(key);
      }
      _failed.clear();
    }
    final key = sha256
        .convert(utf8.encode('$device|$package|$revision'))
        .toString();
    return _pending.putIfAbsent(key, () => _load(package, revision, key));
  }

  Future<Uint8List?> _load(String package, String revision, String key) async {
    if (_closed) return null;
    File? file;
    Directory? directory;
    try {
      directory = await (_directory ??= _directoryProvider());
      if (directory != null) {
        file = File('${directory.path}/$key.png');
        if (await file.exists()) {
          final bytes = await file.readAsBytes();
          if (validPng(bytes)) return bytes;
          await file.delete();
        }
      }
    } catch (_) {
      /* Continue with a memory-only icon if the cache is unavailable. */
    }
    final done = Completer<Uint8List?>();
    _queue = _queue.then((_) async {
      Uint8List? bytes;
      try {
        if (_closed || _offline) {
          _failed.add(key);
          done.complete(null);
          return;
        }
        _transport ??= await (_network ??= _networkProvider());
        if (_transport != null) {
          bytes = await _transport!
              .appIcon(package, revision)
              .timeout(const Duration(seconds: 4));
          if (!validPng(bytes)) {
            bytes = null;
          } else if (file != null) {
            try {
              await file.writeAsBytes(bytes, flush: true);
              final entries = await directory!
                  .list()
                  .where(
                    (entry) =>
                        entry is File &&
                        RegExp(r'/[a-f0-9]{64}\.png$').hasMatch(entry.path),
                  )
                  .cast<File>()
                  .toList();
              if (entries.length > 256) {
                entries.sort(
                  (a, b) =>
                      a.lastModifiedSync().compareTo(b.lastModifiedSync()),
                );
                for (final old in entries.take(entries.length - 256)) {
                  await old.delete();
                }
              }
            } catch (_) {
              /* Cache failure must not hide a valid icon. */
            }
          }
        }
      } on AppIconUnavailable {
        /* Missing icon: keep its letter and try the next app. */
      } catch (_) {
        _failed.add(key);
        _retryAt = DateTime.now().add(const Duration(seconds: 20));
        _offline = true;
        _transport?.close();
      }
      if (!done.isCompleted) done.complete(bytes);
    });
    return done.future;
  }

  void close() {
    _closed = true;
    _transport?.close();
  }
}

class CachedAppIcon extends StatelessWidget {
  const CachedAppIcon({
    super.key,
    required this.future,
    required this.name,
    required this.identity,
    this.size = 48,
    required this.color,
  });
  final Future<Uint8List?>? future;
  final String name, identity;
  final double size;
  final Color color;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: size,
    height: size,
    child: FutureBuilder<Uint8List?>(
      key: ValueKey(identity),
      future: future,
      builder: (context, snapshot) {
        final fallback = Center(
          child: Text(
            name.isEmpty ? '?' : name.characters.first.toUpperCase(),
            style: TextStyle(
              fontSize: size * .5,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        );
        final image = snapshot.data;
        return AnimatedSwitcher(
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 160),
          child: ClipRRect(
            key: ValueKey('$identity:${image != null}'),
            borderRadius: BorderRadius.circular(size * .22),
            child: image == null
                ? SizedBox(width: size, height: size, child: fallback)
                : Image.memory(
                    image,
                    width: size,
                    height: size,
                    fit: BoxFit.contain,
                    gaplessPlayback: true,
                    errorBuilder: (_, _, _) => fallback,
                  ),
          ),
        );
      },
    ),
  );
}
