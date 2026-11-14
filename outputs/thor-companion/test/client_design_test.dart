import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thor_companion/companion_controller.dart';
import 'package:thor_companion/main.dart';
import 'package:thor_companion/telemetry.dart';
import 'package:thor_companion/ui.dart';

void main() {
  setUpAll(() async {
    final font = File('/System/Library/Fonts/SFNS.ttf');
    if (font.existsSync()) {
      for (final name in ['CupertinoSystemText', 'CupertinoSystemDisplay']) {
        final loader = FontLoader(name)
          ..addFont(font.readAsBytes().then((b) => ByteData.sublistView(b)));
        await loader.load();
      }
    }
    final icons = File(
      '../../work/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    );
    if (icons.existsSync()) {
      await (FontLoader('MaterialIcons')
            ..addFont(icons.readAsBytes().then((b) => ByteData.sublistView(b))))
          .load();
    }
  });
  for (final appearance in [
    AppAppearance.clearPurple,
    AppAppearance.light,
    AppAppearance.dark,
    AppAppearance.rainbow,
  ]) {
    testWidgets(
      'client design navigation and theme previews: ${appearance.name}',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        tester.view.physicalSize = const Size(860, 1864);
        tester.view.devicePixelRatio = 2;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final c = CompanionController.demo(), key = GlobalKey();
        c.hardware = const DeviceHardware(
          model: 'AYN Thor',
          deviceName: "Allie's AYN Thor Max",
          variant: 'Max',
          android: '13',
          cpuName: 'Qualcomm Snapdragon 8 Gen 2',
          gpuName: 'Adreno 740',
          ramBytes: 15996096512,
          dataBytes: 1011194642432,
          ufsVersion: '4.0',
          storageCapacityBytes: 1000000000000,
        );
        await tester.pumpWidget(
          RepaintBoundary(
            key: key,
            child: ThorCompanionApp(
              controller: c,
              initialAppearance: appearance,
            ),
          ),
        );
        await tester.pumpAndSettle();
        Future<void> capture(String screen) async {
          final path = Platform.environment['THOR_DESIGN_PREVIEW'];
          if (path == null) return;
          await tester.runAsync(() async {
            final boundary =
                key.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary;
            final image = await boundary.toImage(pixelRatio: 2),
                data = await image.toByteData(format: ui.ImageByteFormat.png);
            await File(
              '$path-${appearance.name}-$screen.png',
            ).writeAsBytes(data!.buffer.asUint8List());
            image.dispose();
          });
        }

        expect(find.text("Allie's AYN Thor Max"), findsOneWidget);
        await capture('overview');
        await tester.tap(find.text('Battery'));
        await tester.pumpAndSettle();
        expect(find.text('Battery insights'), findsOneWidget);
        Navigator.of(tester.element(find.text('Battery insights'))).pop();
        await tester.pumpAndSettle();
        await tester.tap(find.text('Device'));
        await tester.pumpAndSettle();
        await capture('device');
        await tester.tap(find.text('Controls'));
        await tester.pumpAndSettle();
        await capture('controls');
        await tester.tap(find.byTooltip('Appearance and settings'));
        await tester.pumpAndSettle();
        await capture('settings');
        await tester.tap(find.text('Appearance'));
        await tester.pumpAndSettle();
        await capture('themes');
        expect(find.text('Clear Purple'), findsOneWidget);
        expect(find.text('Rainbow'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        c.dispose();
        debugDefaultTargetPlatformOverride = null;
      },
    );
  }
}
