// Regenerate the native launcher assets with: flutter test tool/render_icons.dart
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thor_companion/ui.dart';

void main() {
  testWidgets('render the code-native handheld mark at launcher sizes', (
    tester,
  ) async {
    await tester.runAsync(() async {
      Future<void> render(String path, int size) async {
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        canvas.drawColor(iconBackground, BlendMode.src);
        canvas.scale(size / 1024);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(112, 112, 800, 800),
            const Radius.circular(224),
          ),
          Paint()..color = iconForeground,
        );
        canvas.translate(235, 235);
        canvas.scale(554 / 25);
        const HandheldPainter().paint(canvas, const Size(25, 25));
        final picture = recorder.endRecording();
        final image = await picture.toImage(size, size);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File(path).writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
        picture.dispose();
      }

      final dir = Directory('ios/Runner/Assets.xcassets/AppIcon.appiconset');
      final json =
          jsonDecode(await File('${dir.path}/Contents.json').readAsString())
              as Map<String, dynamic>;
      for (final dynamic item in json['images'] as List) {
        final icon = item as Map<String, dynamic>;
        if (icon['filename'] == null) continue;
        final size = double.parse((icon['size'] as String).split('x').first);
        final scale = double.parse(
          (icon['scale'] as String).replaceAll('x', ''),
        );
        await render('${dir.path}/${icon['filename']}', (size * scale).round());
      }
      for (final item in {
        'mdpi': 48,
        'hdpi': 72,
        'xhdpi': 96,
        'xxhdpi': 144,
        'xxxhdpi': 192,
      }.entries) {
        await render(
          'android/app/src/main/res/mipmap-${item.key}/ic_launcher.png',
          item.value,
        );
      }
      await render('web/favicon.png', 32);
      for (final size in [192, 512]) {
        await render('web/icons/Icon-$size.png', size);
        await render('web/icons/Icon-maskable-$size.png', size);
      }
    });
  });
}
