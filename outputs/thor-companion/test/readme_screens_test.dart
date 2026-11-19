// Renders the README screenshots. Skipped unless THOR_README_SHOTS names an
// output folder, e.g.:
//   THOR_README_SHOTS=/tmp/shots flutter test test/readme_screens_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thor_companion/companion_controller.dart';
import 'package:thor_companion/device_switcher.dart';
import 'package:thor_companion/main.dart';
import 'package:thor_companion/saved_devices.dart';
import 'package:thor_companion/ui.dart';

final _out = Platform.environment['THOR_README_SHOTS'];

Future<void> _font(String family, List<String> files) async {
  final root =
      '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts';
  final loader = FontLoader(family);
  for (final f in files) {
    loader.addFont(
      Future.value(ByteData.sublistView(File('$root/$f').readAsBytesSync())),
    );
  }
  await loader.load();
}

Future<void> _save(WidgetTester tester, String name) async {
  await tester.runAsync(() async {
    final image = await captureImage(
      find.byType(MaterialApp).evaluate().single,
    );
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    File('$_out/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  setUpAll(() async {
    if (_out == null) return;
    await _font('Roboto', [
      'Roboto-Regular.ttf',
      'Roboto-Medium.ttf',
      'Roboto-Bold.ttf',
    ]);
    await _font('MaterialIcons', ['MaterialIcons-Regular.otf']);
  });

  testWidgets('README screenshots', (tester) async {
    tester.view.physicalSize = const Size(860, 1864);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = CompanionController.demo();
    await tester.pumpWidget(
      ThorCompanionApp(
        controller: c,
        initialThemeMode: ThemeMode.dark,
        initialAppearance: AppAppearance.clearPurple,
      ),
    );
    await tester.pumpAndSettle();
    await _save(tester, 'client-overview');

    c.activity = {
      'apps': [
        {'d': 0, 'p': 'org.retroarch', 'name': 'RetroArch', 'cpu': 12.4},
        {'d': 4, 'p': 'com.android.chrome', 'name': 'Chrome', 'cpu': 1.8},
      ],
    };
    c.notifyListeners();
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Focused apps'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.runAsync(
      () => Scrollable.ensureVisible(
        tester.element(find.text('Focused apps')),
        alignment: .02,
      ),
    );
    await tester.pumpAndSettle();
    await _save(tester, 'client-focused-apps');

    await tester.tap(find.text('Controls').last);
    await tester.pumpAndSettle();
    await _save(tester, 'client-controls');

    await tester.tap(find.byIcon(Icons.settings_outlined).first);
    await tester.pumpAndSettle();
    await _save(tester, 'client-settings');
    await tester.tap(find.text('Appearance').last);
    await tester.pumpAndSettle();
    await _save(tester, 'client-themes');
    Navigator.of(tester.element(find.text('Appearance').last)).pop();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Overview').last);
    await tester.pumpAndSettle();
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 4000));
    await tester.pumpAndSettle();
    c.devices = const [
      SavedDevice('demo', 'My AYN Thor', product: 'AYN Thor Max'),
      SavedDevice(
        'retroid',
        'Retroid Pocket Classic',
        product: 'Retroid Pocket Classic 6 GB',
        screens: 1,
      ),
      SavedDevice(
        'odin',
        'Living room handheld',
        product: 'Handheld Device',
        screens: 1,
      ),
    ];
    c.remembered = c.selected;
    unawaited(showDevices(tester.element(find.byType(Scaffold).first), c));
    await tester.pumpAndSettle();
    await _save(tester, 'client-devices');

    await tester.pumpWidget(const SizedBox());
    c.dispose();
  }, skip: _out == null);
}

void unawaited(Future<void> f) {}
