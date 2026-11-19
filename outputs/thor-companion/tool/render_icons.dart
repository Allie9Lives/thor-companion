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
      Future<void> render(
        String path,
        int size, {
        Color outer = iconBackground,
        Color tile = iconForeground,
        Color mark = iconBackground,
        bool rainbow = false,
      }) async {
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        canvas.drawColor(outer, BlendMode.src);
        canvas.scale(size / 1024);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(112, 112, 800, 800),
            const Radius.circular(224),
          ),
          Paint()
            ..color = tile
            ..shader = rainbow
                ? ui.Gradient.linear(
                    const Offset(112, 112),
                    const Offset(912, 912),
                    const [
                      Color(0xFF8D6500),
                      Color(0xFF24794B),
                      Color(0xFF285BC5),
                      Color(0xFFBA4141),
                    ],
                    const [0, 1 / 3, 2 / 3, 1],
                  )
                : null,
        );
        canvas.translate(235, 235);
        canvas.scale(554 / 25);
        HandheldPainter(color: mark).paint(canvas, const Size(25, 25));
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
      final variants = <String, (Color, Color, Color, bool)>{
        'Dark': (iconBackground, iconForeground, iconBackground, false),
        'Light': (
          const Color(0xFFF2F2F5),
          const Color(0xFF252529),
          Colors.white,
          false,
        ),
        'Purple': (
          const Color(0xFF1D1825),
          const Color(0xFF6B5C87),
          const Color(0xFFF5EFFB),
          false,
        ),
        'Rainbow': (const Color(0xFFC6C4C0), Colors.white, const Color(0xFFC6C4C0), true),
      };
      for (final variant in variants.entries) {
        final colors = variant.value;
        if (variant.key != 'Dark') {
          final folder = Directory(
            'ios/Runner/Assets.xcassets/AppIcon${variant.key}.appiconset',
          );
          await folder.create(recursive: true);
          await File(
            '${folder.path}/Contents.json',
          ).writeAsString(const JsonEncoder.withIndent('  ').convert(json));
          for (final dynamic item in json['images'] as List) {
            final entry = item as Map<String, dynamic>;
            if (entry['filename'] == null) continue;
            final size =
                double.parse((entry['size'] as String).split('x').first) *
                double.parse((entry['scale'] as String).replaceAll('x', ''));
            await render(
              '${folder.path}/${entry['filename']}',
              size.round(),
              outer: colors.$1,
              tile: colors.$2,
              mark: colors.$3,
              rainbow: colors.$4,
            );
          }
        }
        for (final item in {
          'mdpi': 48,
          'hdpi': 72,
          'xhdpi': 96,
          'xxhdpi': 144,
          'xxxhdpi': 192,
        }.entries) {
          await render(
            'android/app/src/main/res/mipmap-${item.key}/ic_launcher_${variant.key.toLowerCase()}.png',
            item.value,
            outer: colors.$1,
            tile: colors.$2,
            mark: colors.$3,
            rainbow: colors.$4,
          );
        }
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
