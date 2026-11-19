import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thor_companion/design_components.dart';

void main() {
  testWidgets('press glow skips scroll drags and still pulses on taps', (
    tester,
  ) async {
    final seen = <bool>[];
    await tester.pumpWidget(
      MaterialApp(
        home: PressGlow(
          builder: (context, pressed) {
            seen.add(pressed);
            return const ColoredBox(
              color: Colors.blue,
              child: SizedBox(width: 100, height: 100),
            );
          },
        ),
      ),
    );
    final center = tester.getCenter(find.byType(ColoredBox).last);

    final drag = await tester.startGesture(center);
    await tester.pump(const Duration(milliseconds: 30));
    await drag.moveBy(const Offset(0, kTouchSlop + 4));
    await tester.pump(kPressTimeout * 2);
    expect(seen.last, isFalse, reason: 'scrolling must not light the tile');
    await drag.up();

    final hold = await tester.startGesture(center);
    await tester.pump(kPressTimeout + const Duration(milliseconds: 10));
    await tester.pump();
    expect(seen.last, isTrue);
    await hold.up();
    await tester.pump();
    expect(seen.last, isFalse);

    final tap = await tester.startGesture(center);
    await tester.pump(const Duration(milliseconds: 20));
    await tap.up();
    await tester.pump();
    expect(seen.last, isTrue, reason: 'quick taps still glow briefly');
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pump();
    expect(seen.last, isFalse);
  });
}
