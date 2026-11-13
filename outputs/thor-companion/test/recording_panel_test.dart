import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:thor_companion/companion_controller.dart';
import 'package:thor_companion/file_transfer.dart';
import 'package:thor_companion/network_link.dart';
import 'package:thor_companion/recording_panel.dart';

class CaptureServer extends ThorFiles {
  CaptureServer()
    : super(
        FileConnection(
          hosts: ['192.0.2.1'],
          port: 443,
          pin: 'a' * 64,
          token: 'b' * 64,
          name: 'Thor',
        ),
        '192.0.2.1',
      );
  final actions = <String>[];
  bool cleared = false, failClear = false;
  @override
  Future<Map<String, dynamic>> recording(
    String action, {
    String token = '',
    int mode = 0,
    int quality = 1,
    int fps = 60,
  }) async {
    actions.add(action);
    if (action == 'clear') {
      if (failClear) throw const SocketException('offline');
      cleared = true;
    }
    return cleared
        ? {'state': 'idle'}
        : {
            'state': 'ready',
            'token': 'c' * 24,
            'mode': 0,
            'elapsed_ms': 2500,
            'tracks': [
              {
                'screen': 0,
                'bytes': 128,
                'offset_ms': 0,
                'duration_ms': 2500,
                'width': 1280,
                'height': 720,
              },
            ],
          };
  }

  @override
  Future<void> recordingFile(
    String token,
    int screen,
    File destination,
    void Function(int, int) progress,
  ) async {
    await destination.writeAsBytes(List.filled(128, 0));
    progress(128, 128);
  }
}

void main() {
  testWidgets(
    'Photos failure retains Thor clip; cleanup retry does not save twice',
    (tester) async {
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.empty();
      final directory = Directory.systemTemp.createTempSync('thor-video-test');
      final server = CaptureServer(), c = CompanionController.demo();
      final network = NetworkLink(c)
        ..connection = server.connection
        ..transport = server
        ..status = {'recording': true};
      var saves = 0;
      var failSave = true;
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        fileBridge,
        (call) async => call.method == 'cacheDirectory' ? directory.path : null,
      );
      messenger.setMockMethodCallHandler(captureBridge, (call) async {
        if (call.method == 'saveVideo') {
          saves++;
          if (failSave) {
            throw PlatformException(
              code: 'photos',
              message: 'Photos unavailable',
            );
          }
        }
        return null;
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: RecordingPanel(network: network, onBusyChanged: (_) {}),
            ),
          ),
        ),
      );
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });
      await tester.pump();
      final dynamic state = tester.state(find.byType(RecordingPanel));
      await tester.runAsync(() async {
        await state.stopAndSave();
      });
      await tester.pump();
      expect(saves, 1);
      expect(server.actions.contains('clear'), false);
      expect(find.text('Photos unavailable'), findsOneWidget);
      failSave = false;
      server.failClear = true;
      await tester.runAsync(() async {
        await state.stopAndSave();
      });
      await tester.pump();
      expect(saves, 2);
      expect(server.cleared, false);
      expect(find.text('Remove Thor copy'), findsOneWidget);
      server.failClear = false;
      await tester.runAsync(() async {
        await state.stopAndSave();
      });
      await tester.pump();
      expect(saves, 2);
      expect(server.cleared, true);
      expect(find.text('Saved to Photos · Thor copy removed'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      network.dispose();
      c.dispose();
      messenger.setMockMethodCallHandler(fileBridge, null);
      messenger.setMockMethodCallHandler(captureBridge, null);
      await tester.runAsync(() async {
        await directory.delete(recursive: true);
      });
    },
  );
}
