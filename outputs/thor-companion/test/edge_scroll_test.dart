import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thor_companion/companion_controller.dart';
import 'package:thor_companion/main.dart';

void main() {
  for (final bottom in [false, true]) {
    testWidgets(
      'live updates preserve ${bottom ? 'bottom' : 'top'} rubber band until release',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        tester.view.physicalSize = const Size(430, 932);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final c = CompanionController.demo();
        await tester.pumpWidget(ThorCompanionApp(controller: c));
        await tester.pumpAndSettle();
        final scroll = tester
            .state<ScrollableState>(find.byType(Scrollable).first)
            .position;
        scroll.jumpTo(bottom ? scroll.maxScrollExtent : 0);
        await tester.pump();
        final gesture = await tester.startGesture(const Offset(215, 450));
        await gesture.moveBy(Offset(0, bottom ? -40 : 40));
        await tester.pump(const Duration(milliseconds: 16));
        await gesture.moveBy(Offset(0, bottom ? -140 : 140));
        await tester.pump(const Duration(milliseconds: 16));
        final before = scroll.pixels;
        expect(bottom ? before > scroll.maxScrollExtent : before < 0, true);
        c.receivedAt = DateTime.now().subtract(const Duration(seconds: 12));
        c.notifyListeners();
        await tester.pump(const Duration(milliseconds: 16));
        expect(
          scroll.pixels,
          closeTo(before, .1),
          reason: 'A live update must not clamp the rubber-band position.',
        );
        await gesture.up();
        await tester.pumpAndSettle();
        expect(scroll.pixels, closeTo(bottom ? scroll.maxScrollExtent : 0, .5));
        expect(find.text('Updated 12s ago'), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
        c.dispose();
        debugDefaultTargetPlatformOverride = null;
      },
    );
  }
}
