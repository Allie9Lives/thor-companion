import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thor_companion/focused_apps.dart';
import 'package:thor_companion/app_icons.dart';

void main() {
  for (final scale in [1.0, 2.0]) {
    testWidgets('focused boxes stay compact and fit text at scale $scale', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(440, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: Scaffold(
              body: SingleChildScrollView(
                child: FocusedApps(
                  apps: const [
                    {'d': 0, 'name': 'Cocoon', 'cpu': 4.0},
                    {'d': 4, 'name': 'Cocoon', 'cpu': 4.0},
                  ],
                  onOpenDrawer: (_) {},
                ),
              ),
            ),
          ),
        ),
      );
      final top = tester.getSize(
            find.byKey(const ValueKey('focused-top-screen')),
          ),
          bottom = tester.getSize(
            find.byKey(const ValueKey('focused-bottom-screen')),
          );
      final frame = find.byKey(const ValueKey('focused-top-screen'));
      final icon = find.descendant(
        of: frame,
        matching: find.byType(CachedAppIcon),
      );
      final name = find.descendant(of: frame, matching: find.text('Cocoon'));
      expect(
        tester.getCenter(icon).dx,
        closeTo(tester.getCenter(frame).dx, .1),
      );
      expect(
        tester.getTopLeft(name).dy,
        greaterThan(tester.getBottomLeft(icon).dy),
      );
      expect(top.width, 220);
      expect(bottom.width, 180);
      expect(top.height, greaterThanOrEqualTo(140));
      expect(bottom.height, greaterThanOrEqualTo(128));
      expect(tester.takeException(), isNull);
    });
  }
}
