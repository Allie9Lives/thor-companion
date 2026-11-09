import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thor_companion/companion_controller.dart';
import 'package:thor_companion/main.dart';
import 'package:thor_companion/ui.dart';

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
    final icons = File(
      '../../work/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    );
    if (icons.existsSync()) {
      final loader = FontLoader('MaterialIcons')
        ..addFont(icons.readAsBytes().then((b) => ByteData.sublistView(b)));
      await loader.load();
    }
  });

  for (final choice in [AppAppearance.clearPurple, AppAppearance.rainbow]) {
    testWidgets(
      'color theme ${choice.name} renders and switches without replacing connection',
      (tester) async {
        tester.view.physicalSize = const Size(780, 1688);
        tester.view.devicePixelRatio = 2;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final c = CompanionController.demo(), boundaryKey = GlobalKey();
        await tester.pumpWidget(
          RepaintBoundary(
            key: boundaryKey,
            child: ThorCompanionApp(controller: c, initialAppearance: choice),
          ),
        );
        await tester.pumpAndSettle();
        final palette = AppPalette.of(
          tester.element(find.byType(Scaffold).first),
        );
        expect(palette.appearance, choice);
        expect(
          palette.brandColor,
          choice == AppAppearance.clearPurple
              ? const Color(0xFF6B5C87)
              : const Color(0xFF285BC5),
        );
        expect(
          Theme.of(tester.element(find.byType(Scaffold).first)).brightness,
          choice == AppAppearance.clearPurple
              ? Brightness.dark
              : Brightness.light,
        );
        double contrast(Color a, Color b) {
          final x = a.computeLuminance(), y = b.computeLuminance();
          return ((x > y ? x : y) + .05) / ((x < y ? x : y) + .05);
        }

        expect(contrast(palette.foreground, palette.card), greaterThan(4.5));
        expect(contrast(palette.secondaryText, palette.card), greaterThan(4.5));
        expect(contrast(palette.onAccent, palette.accent), greaterThan(4.5));
        final output = Platform.environment['THOR_COLOR_PREVIEW_PATH'];
        Future<void> capture(String suffix) async {
          if (output != null) {
            await tester.runAsync(() async {
              final boundary =
                  boundaryKey.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary;
              final rendered = await boundary.toImage(pixelRatio: 2);
              final bytes = await rendered.toByteData(
                format: ui.ImageByteFormat.png,
              );
              await File(
                '$output-${choice.name}$suffix.png',
              ).writeAsBytes(bytes!.buffer.asUint8List());
              rendered.dispose();
            });
          }
        }

        await capture('');
        await tester.ensureVisible(find.text('RAM'));
        await tester.pumpAndSettle();
        await capture('-performance');
        tester
            .state<ScrollableState>(find.byType(Scrollable).first)
            .position
            .jumpTo(0);
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Appearance and settings'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Appearance'));
        await tester.pumpAndSettle();
        expect(find.text('Clear Purple'), findsOneWidget);
        expect(find.text('Rainbow'), findsOneWidget);
        await tester.tap(find.text('Dark'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Close settings'));
        await tester.pumpAndSettle();
        expect(
          tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
          ThemeMode.dark,
        );
        expect(c.stats!.battery, 69);
        expect(find.text('Demo data'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        c.dispose();
      },
    );
  }

  for (final mode in [ThemeMode.dark, ThemeMode.light]) {
    testWidgets('dashboard renders and switches appearance: ${mode.name}', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(780, 1688);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final c = CompanionController.demo();
      final boundaryKey = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundaryKey,
          child: ThorCompanionApp(controller: c, initialThemeMode: mode),
        ),
      );
      await tester.pump();
      expect(find.text('Demo data'), findsOneWidget);
      expect(find.text('Charging'), findsOneWidget);
      expect(find.text('UFS 4.0'), findsOneWidget);
      expect(find.text('Performance'), findsOneWidget);
      expect(find.text('CPU'), findsOneWidget);
      expect(find.text('GPU'), findsOneWidget);
      expect(find.text('RAM'), findsOneWidget);
      expect(find.text('microSD card'), findsOneWidget);
      expect(tester.takeException(), isNull);
      final output = Platform.environment['THOR_PREVIEW_PATH'];
      if (output != null) {
        final boundary =
            boundaryKey.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 2);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File(
            output.replaceFirst('.png', '-${mode.name}.png'),
          ).writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
        await tester.ensureVisible(find.textContaining('usable total').last);
        await tester.pumpAndSettle();
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 2);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File(
            output.replaceFirst('.png', '-storage-${mode.name}.png'),
          ).writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position
          .jumpTo(0);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Appearance and settings'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Appearance'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(mode == ThemeMode.dark ? 'Light' : 'Dark'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Close settings'));
      await tester.pumpAndSettle();
      expect(
        Theme.of(tester.element(find.text('Charging'))).brightness,
        mode == ThemeMode.dark ? Brightness.light : Brightness.dark,
      );
      expect(c.stats?.battery, 69);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });
  }

  testWidgets('device details fit a narrow phone with large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(640, 1280);
    tester.view.devicePixelRatio = 2;
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = CompanionController.demo();
    await tester.pumpWidget(ThorCompanionApp(controller: c));
    await tester.pump();
    await tester.ensureVisible(find.text('microSD card'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Device'));
    await tester.pumpAndSettle();
    expect(find.text('Device information'), findsOneWidget);
    expect(tester.widget<Text>(find.text('Processor + RAM')).maxLines, 1);
    expect(tester.widget<Text>(find.text('Snapdragon 8 Gen 2')).maxLines, 1);
    expect(find.textContaining('10-minute timer'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });
  testWidgets('controls fit a narrow phone with large text', (tester) async {
    tester.view.physicalSize = const Size(640, 1280);
    tester.view.devicePixelRatio = 2;
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = CompanionController.demo();
    await tester.pumpWidget(ThorCompanionApp(controller: c));
    await tester.pump();
    await tester.tap(find.text('Controls'));
    await tester.pumpAndSettle();
    expect(find.text('Sync screens'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('Controller layout'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });
  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets('sync switch stays visible when on and off: ${mode.name}', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(780, 1688);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final c = CompanionController.demo();
      final boundaryKey = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundaryKey,
          child: ThorCompanionApp(controller: c, initialThemeMode: mode),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('Controls'));
      await tester.pumpAndSettle();
      Future<void> capture(String state) async {
        final output = Platform.environment['THOR_SWITCH_PREVIEW'];
        if (output == null) return;
        final boundary =
            boundaryKey.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 2);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File(
            '$output-${mode.name}-$state.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }

      final toggle = find.widgetWithText(SwitchListTile, 'Sync screens');
      expect(c.brightnessLinked, isFalse);
      await tester.ensureVisible(toggle);
      await tester.pumpAndSettle();
      await capture('off');
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(c.brightnessLinked, isTrue);
      await capture('on');
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(c.brightnessLinked, isFalse);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });
  }
}
