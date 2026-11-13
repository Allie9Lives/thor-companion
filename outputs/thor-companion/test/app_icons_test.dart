import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:thor_companion/app_icons.dart';
import 'package:thor_companion/file_transfer.dart';

class IconsServer extends ThorFiles {
  IconsServer()
    : super(
        FileConnection(
          hosts: ['192.0.2.1'],
          port: 443,
          pin: 'a' * 64,
          token: 'b' * 64,
          name: 'Test',
        ),
        '192.0.2.1',
      );
  int calls = 0;
  bool missing = false;
  @override
  Future<Uint8List> appIcon(String package, String revision) async {
    calls++;
    if (missing) throw const AppIconUnavailable();
    return base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=',
    );
  }
}

void main() {
  test('icons persist locally and cached icons need no network', () async {
    final directory = await Directory.systemTemp.createTemp('thor-icon-test');
    final server = IconsServer();
    final cache = AppIconCache(
      'device',
      directory: () async => directory,
      network: () async => server,
    );
    expect(await cache.get('com.test.app', 'a' * 16), isNotNull);
    expect(server.calls, 1);
    expect(await cache.get('com.test.app', 'a' * 16), isNotNull);
    expect(server.calls, 1);
    cache.close();
    var requested = false;
    final offline = AppIconCache(
      'device',
      directory: () async => directory,
      network: () async {
        requested = true;
        throw const SocketException('offline');
      },
    );
    expect(await offline.get('com.test.app', 'a' * 16), isNotNull);
    expect(requested, false);
    expect(await offline.get('com.test.app', 'b' * 16), isNull);
    expect(requested, true);
    offline.close();
    await directory.delete(recursive: true);
  });
  test('a missing icon does not disable fetching the next app', () async {
    final server = IconsServer()..missing = true;
    final cache = AppIconCache(
      'device',
      directory: () async => null,
      network: () async => server,
    );
    expect(await cache.get('com.test.missing', 'a' * 16), isNull);
    server.missing = false;
    expect(await cache.get('com.test.available', 'a' * 16), isNotNull);
    expect(server.calls, 2);
    expect(await cache.get('bad/path', 'a' * 16), isNull);
    expect(AppIconCache.validPng(Uint8List(32)), false);
    cache.close();
  });
}
