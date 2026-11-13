import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thor_companion/companion_controller.dart';
import 'package:thor_companion/dashboard.dart';
import 'package:thor_companion/ui.dart';

void main() {
  for (final width in [390.0, 440.0]) {
    testWidgets(
      'battery gauge is enlarged and centered in the right area at $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 1400);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final c = CompanionController.demo();
        await tester.pumpWidget(
          MaterialApp(
            theme: appTheme(
              Brightness.dark,
              appearance: AppAppearance.clearPurple,
            ),
            home: Scaffold(
              body: Padding(
                padding: const EdgeInsets.all(24),
                child: Dashboard(controller: c).batteryPanel(),
              ),
            ),
          ),
        );
        final gauge = tester.getRect(
          find.byKey(const ValueKey('overview-battery-gauge')),
        );
        expect(gauge.width, greaterThanOrEqualTo(126));
        expect(gauge.center.dx, closeTo(width * .67, 15));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        c.dispose();
      },
    );
  }
}
