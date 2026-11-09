import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:thor_companion/battery_history.dart';
import 'package:thor_companion/battery_runtime.dart';
import 'package:thor_companion/telemetry.dart';

void main() {
  final end = DateTime(2026, 11, 7, 12).millisecondsSinceEpoch;
  BatteryPoint point(int ago, double level, {bool plugged = false}) =>
      BatteryPoint(
        end - ago * 60000,
        level,
        plugged,
        35,
        4000,
        -500000,
        4000000,
        null,
        true,
      );
  DeviceStats current(double level, {int plug = 0}) => DeviceStats.fromBytes(
    utf8.encode(
      jsonEncode({
        'seq': 1,
        'ts_ms': end,
        'battery_pct': level,
        'plugged_code': plug,
      }),
    ),
  );
  final steady = [
    point(60, 80),
    point(55, 79),
    point(50, 78),
    point(45, 77),
    point(40, 76),
    point(35, 75),
    point(30, 74),
    point(25, 73),
    point(20, 72),
    point(15, 71),
    point(10, 70),
    point(5, 69),
  ];
  test('steady measured discharge gives a bounded runtime range', () {
    final r = estimateBatteryRuntime(steady, current(68));
    expect(r.available, isTrue);
    expect(r.drainPerHour, closeTo(12, .001));
    expect(r.minimum!.inMinutes, greaterThan(240));
    expect(r.maximum!.inMinutes, lessThanOrEqualTo(460));
    expect(r.window!.inMinutes, 60);
  });
  test('charging and stale readings never predict runtime', () {
    expect(
      estimateBatteryRuntime(steady, current(68, plug: 2)).available,
      isFalse,
    );
    expect(
      estimateBatteryRuntime(steady, current(68), fresh: false).available,
      isFalse,
    );
  });
  test(
    'gaps, charge transitions and short histories do not borrow old usage',
    () {
      expect(
        estimateBatteryRuntime([
          point(60, 80),
          point(5, 69),
        ], current(68)).available,
        isFalse,
      );
      expect(
        estimateBatteryRuntime([
          ...steady.take(9),
          point(15, 75, plugged: true),
          point(5, 69),
        ], current(68)).available,
        isFalse,
      );
      expect(
        estimateBatteryRuntime([point(5, 69)], current(68)).available,
        isFalse,
      );
    },
  );
  test(
    'tiny drops and calibration rises are not treated as measured discharge',
    () {
      expect(
        estimateBatteryRuntime([
          for (var i = 30; i >= 5; i -= 5) point(i, 68.5),
        ], current(68)).available,
        isFalse,
      );
      expect(
        estimateBatteryRuntime([
          ...steady,
          point(2, 75),
        ], current(74)).available,
        isFalse,
      );
    },
  );
  test('clock offset on the phone does not determine the discharge window', () {
    final r = estimateBatteryRuntime([...steady, point(-30, 20)], current(68));
    expect(r.available, isTrue);
    expect(r.drainPerHour, 12);
  });
}
