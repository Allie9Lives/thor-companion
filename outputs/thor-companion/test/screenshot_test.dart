import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter_test/flutter_test.dart';
import 'package:thor_companion/screenshot_transfer.dart';
import 'package:thor_companion/screenshot_page.dart';

final red = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAMAAAACCAYAAACddGYaAAAAEUlEQVR4nGP4z8DwH4YZkDkAm34L9XKwuTwAAAAASUVORK5CYII=',
);
final blue = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGNgYPj/HwADAgH/5ncLrgAAAABJRU5ErkJggg==',
);
Uint8List container(int mode) {
  final screens = mode == 2 ? [0, 1] : [mode];
  final builder = BytesBuilder()..add([84, 72, 83, 49, screens.length]);
  for (final screen in screens) {
    final image = screen == 0 ? red : blue;
    builder.add([screen]);
    builder.add((ByteData(4)..setUint32(0, image.length)).buffer.asUint8List());
    builder.add(image);
  }
  return builder.takeBytes();
}

Uint8List packet(Uint8List bytes, int token, int offset, int count) {
  final p = ByteData(16 + count)
    ..setUint32(0, 0x54533031)
    ..setUint32(4, token)
    ..setUint32(8, offset)
    ..setUint32(12, bytes.length);
  final value = p.buffer.asUint8List();
  value.setRange(16, value.length, bytes, offset);
  return value;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'CRC uses standard CRC32 and packets reconstruct exact Unicode-independent binary',
    () async {
      expect(screenshotCrc(utf8.encode('123456789')), 0xcbf43926);
      final bytes = container(2), progress = <double>[];
      final receiver = ScreenshotReceiver(
        42,
        bytes.length,
        screenshotCrc(bytes),
        progress.add,
      )..start();
      final result = receiver.done.future;
      for (var offset = 0; offset < bytes.length;) {
        final count = (bytes.length - offset).clamp(0, 37);
        receiver.add(packet(bytes, 42, offset, count));
        offset += count;
      }
      expect(await result, bytes);
      expect(progress.last, 1);
      expect(screenshotImages(bytes, 2).keys.toSet(), {0, 1});
    },
  );
  test(
    'late captures and duplicate packets do not corrupt an active transfer',
    () async {
      final bytes = container(0);
      final r = ScreenshotReceiver(
        7,
        bytes.length,
        screenshotCrc(bytes),
        (_) {},
      )..start();
      r.add(packet(bytes, 6, 0, 20));
      expect(r.received, 0);
      r.add(packet(bytes, 7, 0, 20));
      r.add(packet(bytes, 7, 0, 20));
      expect(r.received, 20);
      r.add(packet(bytes, 7, 20, bytes.length - 20));
      expect(await r.done.future, bytes);
    },
  );
  test(
    'missing packets and bad checksums fail without producing an image',
    () async {
      final bytes = container(0);
      final gap = ScreenshotReceiver(1, bytes.length, 0, (_) {})..start();
      final failed = expectLater(gap.done.future, throwsStateError);
      gap.add(packet(bytes, 1, 3, 10));
      await failed;
      final bad = ScreenshotReceiver(1, bytes.length, 0, (_) {})..start();
      final corrupt = expectLater(bad.done.future, throwsStateError);
      bad.add(packet(bytes, 1, 0, bytes.length));
      await corrupt;
      expect(
        () => ScreenshotReceiver(1, maxScreenshotBytes + 1, 0, (_) {}),
        throwsFormatException,
      );
      expect(() => screenshotImages(container(0), 2), throwsFormatException);
    },
  );
  test(
    'top and bottom retain original PNG; both stack with centered transparent padding',
    () async {
      expect(await composeScreenshot(container(0), 0), red);
      expect(await composeScreenshot(container(1), 1), blue);
      final png = await composeScreenshot(container(2), 2);
      final codec = await ui.instantiateImageCodec(png);
      final image = (await codec.getNextFrame()).image;
      expect(image.width, 3);
      expect(image.height, 3);
      final raw = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!.buffer.asUint8List();
      expect(raw.sublist(0, 4), [255, 0, 0, 255]);
      expect(raw.sublist(24, 28), [0, 0, 0, 0]);
      expect(raw.sublist(32, 36), [0, 0, 0, 0]);
      expect(raw.sublist(28, 32), [0, 0, 255, 255]);
      image.dispose();
      codec.dispose();
    },
  );
}
