import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thor_companion/companion_controller.dart';
import 'package:thor_companion/dashboard.dart';
import 'package:thor_companion/stats_copy.dart';
import 'package:thor_companion/ui.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final copies = <String>[];
  setUp(() {
    copies.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            copies.add((call.arguments as Map)['text'] as String);
          }
          return null;
        });
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null),
  );
  test(
    'copied device details preserve full names and inference; each card exports only its stats',
    () {
      final c = CompanionController.demo();
      final device = statsForClipboard(c, StatsSection.device);
      expect(device, contains('CPU: Qualcomm Snapdragon 8 Gen 2'));
      expect(
        device,
        contains('Model detection: Inferred from processor and RAM'),
      );
      expect(device, contains('Demo data'));
      final battery = statsForClipboard(c, StatsSection.battery);
      expect(battery, contains('Battery: 69%'));
      expect(battery, contains('USB input: 6.4 W'));
      expect(battery, isNot(contains('Snapdragon')));
      c.dispose();
    },
  );
  testWidgets(
    'hardware card copies from padding and from a value; values share one column',
    (tester) async {
      final c = CompanionController.demo();
      tester.view.physicalSize = const Size(430, 2200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme(
            Brightness.dark,
            appearance: AppAppearance.clearPurple,
          ),
          home: Scaffold(
            body: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: DevicePage(controller: c),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      final model = find.text('Processor + RAM'),
          gpu = find.text('Adreno 740'),
          cpu = find.text('Snapdragon 8 Gen 2');
      expect(
        tester.getTopLeft(model).dx,
        closeTo(tester.getTopLeft(gpu).dx, .5),
      );
      expect(tester.getTopLeft(cpu).dx, closeTo(tester.getTopLeft(gpu).dx, .5));
      final card = find
          .byWidgetPredicate(
            (w) => w is GestureDetector && w.onLongPress != null,
          )
          .first;
      await tester.longPressAt(tester.getTopLeft(card) + const Offset(7, 7));
      await tester.pump();
      expect(copies.single, contains('Device information'));
      expect(copies.single, contains('Qualcomm Snapdragon 8 Gen 2'));
      await tester.longPress(model);
      await tester.pump();
      expect(copies, hasLength(2));
      expect(find.text('Device stats copied'), findsWidgets);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );
  testWidgets('battery gauge itself copies the complete battery card', (
    tester,
  ) async {
    final c = CompanionController.demo();
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(Brightness.light),
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(24),
            child: Dashboard(controller: c).batteryPanel(),
          ),
        ),
      ),
    );
    await tester.pump();
    final gauge = find.byWidgetPredicate(
      (w) => w is CustomPaint && w.painter is BatteryRing,
    );
    await tester.longPress(gauge);
    await tester.pump();
    expect(copies.single, contains('Battery: 69%'));
    expect(copies.single, contains('Temperature: 30.0 °C'));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });
}
