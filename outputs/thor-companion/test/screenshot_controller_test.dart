import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:thor_companion/ble_transport.dart';
import 'package:thor_companion/companion_controller.dart';
import 'package:thor_companion/screenshot_transfer.dart';
import 'controls_test.dart' show ControlBle;
import 'screenshot_test.dart' show container, packet;

class ScreenshotBle extends ControlBle {
  ScreenshotBle() {
    state['screenshots'] = true;
  }
  bool holdStream = false;
  Uint8List? image;
  int captures = 0, clears = 0;
  @override
  Future<void> writeControl(String id, List<int> bytes) async {
    final j = jsonDecode(utf8.decode(bytes)) as Map;
    state['ack'] = j['id'];
    state['error'] = '';
    if (j['set'] == 'screenshot') {
      captures++;
      image = container(j['value'] as int);
      state['shot_token'] = '17';
      state['shot_bytes'] = image!.length;
      state['shot_crc'] = screenshotCrc(image!);
    } else if (j['set'] == 'screenshot_stream' && !holdStream) {
      final image = this.image!;
      for (var offset = 0; offset < image.length;) {
        final count = (image.length - offset).clamp(0, 53);
        notifications.add(packet(image, 17, offset, count));
        offset += count;
      }
    } else if (j['set'] == 'screenshot_clear') {
      clears++;
      image = null;
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ScreenshotBle ble;
  late CompanionController c;
  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 20));
  setUp(() async {
    ble = ScreenshotBle();
    c = CompanionController(transport: ble, rememberDevice: false);
    await settle();
    await c.connect(const NearbyThor('thor', 'Thor', -50));
    ble.links.add(LinkState.connected);
    await settle();
  });
  tearDown(() async {
    c.dispose();
    await ble.close();
  });
  test(
    'capture receives binary over the existing notification stream and releases the host buffer',
    () async {
      expect(await c.captureScreens(2), container(2));
      expect(c.screenshotProgress, 1);
      expect(c.screenshotBusy, isFalse);
      expect(ble.captures, 1);
      expect(ble.clears, 1);
      expect(ble.image, isNull);
      expect(c.error, isNull);
      await c.refresh();
      expect(ble.captures, 1);
    },
  );
  test(
    'cancel stops receiving, releases the host buffer and does not replay',
    () async {
      ble.holdStream = true;
      final future = c.captureScreens(0);
      final failed = expectLater(future, throwsStateError);
      await settle();
      expect(c.screenshotBusy, isTrue);
      c.cancelScreenshot();
      await failed;
      expect(ble.clears, 1);
      expect(c.screenshotBusy, isFalse);
      await c.refresh();
      expect(ble.captures, 1);
    },
  );
}
