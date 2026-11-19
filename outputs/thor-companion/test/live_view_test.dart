import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thor_companion/gamepad_overlay.dart';
import 'package:thor_companion/live_view_page.dart';

void main() {
  test(
    'touch positions map to 0–10000 of the shown video and stay in range',
    () {
      const box = Size(400, 225);
      expect(liveFraction(Offset.zero, box), (0, 0));
      expect(liveFraction(const Offset(200, 112.5), box), (5000, 5000));
      expect(liveFraction(const Offset(400, 225), box), (10000, 10000));
      expect(liveFraction(const Offset(-20, 300), box), (0, 10000));
    },
  );

  test('focus picks top, bottom or both screens', () {
    expect(liveScreens(0), [0]);
    expect(liveScreens(1), [1]);
    expect(liveScreens(2), [0, 1]);
  });

  test('stick positions scale to ±1000 and clamp to the rim', () {
    expect(stickValue(Offset.zero, 50), (0, 0));
    expect(stickValue(const Offset(25, 0), 50), (500, 0));
    expect(stickValue(const Offset(0, -50), 50), (0, -1000));
    final (x, y) = stickValue(const Offset(300, 400), 50);
    expect((x, y), (600, 800));
  });

  test('controller key codes match the device gamepad layout', () {
    expect(
      [PadKey.a, PadKey.b, PadKey.x, PadKey.y, PadKey.start, PadKey.select],
      [96, 97, 99, 100, 108, 109],
    );
  });
}
