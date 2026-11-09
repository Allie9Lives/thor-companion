import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:thor_companion/companion_controller.dart';
import 'package:thor_companion/controls.dart';
import 'package:thor_companion/ui.dart';
import 'package:thor_companion/battery_history.dart';

void main() {
  test('rest markers retain their meaning, bounds and offline cache', () {
    final now = DateTime.now().millisecondsSinceEpoch, l = BatteryLedger();
    l.mergeSleep([
      SleepEvent(now - 600000, 1),
      SleepEvent(now - 500000, 2),
      SleepEvent(now - 400000, 3),
      SleepEvent(now - 300000, 0),
    ]);
    final restored = BatteryLedger()..loadSleep(l.encodeSleep());
    expect(restored.sleepEvents.map((e) => e.code), [1, 2, 3, 0]);
    expect(() => SleepEvent.fromList([now, 4]), throwsFormatException);
    expect(() => SleepEvent.fromList([now, 1, 0]), throwsFormatException);
    restored.mergeSleep([SleepEvent(now - 8 * 86400000, 1)]);
    expect(restored.sleepEvents.length, 4);
  });
  testWidgets('sleep and wake controls fit with larger text', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = CompanionController.demo();
    c.controls!.values.addAll({
      'sleep_policy': true,
      'wake_control': true,
      'screens_awake': false,
      'power_control': true,
      'sleep_end': 360,
      'sleep_exact': true,
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(Brightness.dark),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(1.6)),
          child: child!,
        ),
        home: Scaffold(
          body: SingleChildScrollView(child: ControlsPage(controller: c)),
        ),
      ),
    );
    await tester.pump();
    await tester.ensureVisible(find.text('Wake screens'));
    await tester.pump();
    expect(find.text('Allow deep sleep'), findsOneWidget);
    expect(find.textContaining('Restore keep-alive'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });
}
