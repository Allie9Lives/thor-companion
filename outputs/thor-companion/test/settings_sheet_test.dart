import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thor_companion/companion_controller.dart';
import 'package:thor_companion/main.dart';
import 'package:thor_companion/ui.dart';
import 'package:thor_companion/settings_sheet.dart';

void main() {
  setUpAll(() async {
    final fonts = Directory(
      '../../work/flutter/bin/cache/artifacts/material_fonts',
    );
    if (fonts.existsSync()) {
      final loader = FontLoader('Roboto');
      for (final name in [
        'Roboto-Regular.ttf',
        'Roboto-Medium.ttf',
        'Roboto-Bold.ttf',
      ]) {
        loader.addFont(
          File(
            '${fonts.path}/$name',
          ).readAsBytes().then((b) => ByteData.sublistView(b)),
        );
      }
      await loader.load();
    }
    final systemFont = File('/System/Library/Fonts/SFNS.ttf');
    final fallbackFont = File('${fonts.path}/Roboto-Regular.ttf');
    final textFont = systemFont.existsSync() ? systemFont : fallbackFont;
    if (textFont.existsSync()) {
      for (final name in ['CupertinoSystemText', 'CupertinoSystemDisplay']) {
        final loader = FontLoader(
          name,
        )..addFont(textFont.readAsBytes().then((b) => ByteData.sublistView(b)));
        await loader.load();
      }
    }
    final icons = File(
      '../../work/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    );
    if (icons.existsSync()) {
      final loader = FontLoader('MaterialIcons')
        ..addFont(icons.readAsBytes().then((b) => ByteData.sublistView(b)));
      await loader.load();
    }
  });

  for (final choice in [
    AppAppearance.light,
    AppAppearance.dark,
    AppAppearance.clearPurple,
    AppAppearance.rainbow,
  ]) {
    testWidgets('Settings tiles and footer order: ${choice.name}', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      tester.view.physicalSize = const Size(780, 1688);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final c = CompanionController.demo(), key = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: ThorCompanionApp(controller: c, initialAppearance: choice),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Appearance and settings'));
      await tester.pumpAndSettle();
      final labels = [
        'Appearance',
        'Battery widgets',
        'Battery notifications',
        'Battery insights',
        'Files',
        'Connection health',
      ];
      final sizes = labels
          .map(
            (label) => tester.getSize(
              find.descendant(
                of: find.byType(SettingsSheet),
                matching: find.widgetWithText(OutlinedButton, label),
              ),
            ),
          )
          .toList();
      expect(sizes.every((s) => s == sizes.first), isTrue);
      expect(
        tester.getTopLeft(find.text('Connection help')).dy,
        lessThan(tester.getTopLeft(find.text('Sound credits')).dy),
      );
      expect(
        tester.getTopLeft(find.text('Connection health')).dy,
        lessThan(tester.getTopLeft(find.text('Connection help')).dy),
      );
      Future<void> capture(String suffix) async {
        final output = Platform.environment['THOR_SETTINGS_PREVIEW_PATH'];
        if (output == null) return;
        await tester.runAsync(() async {
          final boundary =
              key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final image = await boundary.toImage(pixelRatio: 2);
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          await File(
            '$output-${choice.name}$suffix.png',
          ).writeAsBytes(data!.buffer.asUint8List());
          image.dispose();
        });
      }

      await capture('');
      await tester.ensureVisible(find.text('Sound credits'));
      await tester.pumpAndSettle();
      await capture('-footer');
      await tester.tap(find.text('Connection help'));
      await tester.pumpAndSettle();
      expect(find.text('Connection help'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
      debugDefaultTargetPlatformOverride = null;
    });
  }
  testWidgets('Settings fit narrow phones at large text sizes', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(640, 1280);
    tester.view.devicePixelRatio = 2;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = CompanionController.demo();
    await tester.pumpWidget(ThorCompanionApp(controller: c));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Appearance and settings'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Sound credits'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
    debugDefaultTargetPlatformOverride = null;
  });
}
