import 'package:flutter_test/flutter_test.dart';
import 'package:thor_companion/battery_alerts.dart';
import 'package:thor_companion/battery_history.dart';

void main() {
  test('thresholds notify once per discharge and rearm with hysteresis', () {
    final t = BatteryAlertTracker(), o = BatteryAlertOptions(enabled: true);
    expect(t.observe(25, false, 1, o), isEmpty);
    expect(t.observe(20, false, 2, o).map((a) => a.key), ['low20']);
    expect(t.observe(19, false, 3, o), isEmpty);
    expect(t.observe(10, false, 4, o).map((a) => a.key), ['low10']);
    expect(t.observe(9, false, 4, o), isEmpty);
    expect(t.observe(24, false, 5, o), isEmpty);
    expect(t.observe(20, false, 6, o).map((a) => a.key), ['low20']);
  });
  test('large drops send only the lowest enabled low-battery alert', () {
    final t = BatteryAlertTracker(),
        o = BatteryAlertOptions(enabled: true, low10: false);
    t.observe(30, false, 1, o);
    expect(t.observe(8, false, 2, o).map((a) => a.key), ['low20']);
  });
  test(
    'power events and 80 percent use real transitions rather than initial state',
    () {
      final t = BatteryAlertTracker(), o = BatteryAlertOptions(enabled: true);
      expect(t.observe(79, false, 1, o), isEmpty);
      expect(t.observe(79, true, 2, o).map((a) => a.key), ['plugged']);
      expect(t.observe(80, true, 3, o).map((a) => a.key), ['charged80']);
      expect(t.observe(81, true, 4, o), isEmpty);
      expect(t.observe(81, false, 5, o).map((a) => a.key), ['unplugged']);
      expect(t.observe(78, false, 6, o), isEmpty);
      expect(t.observe(78, true, 7, o).map((a) => a.key), ['plugged']);
      expect(t.observe(80, true, 8, o).map((a) => a.key), ['charged80']);
    },
  );
  test(
    'disabled alerts track state and persisted latches prevent duplicate delivery',
    () {
      final t = BatteryAlertTracker(), o = BatteryAlertOptions();
      t.observe(21, false, 1, o);
      expect(t.observe(20, false, 2, o), isEmpty);
      final restored = BatteryAlertTracker()..load(t.toMap());
      o.enabled = true;
      expect(restored.observe(19, false, 3, o), isEmpty);
      expect(restored.observe(10, false, 4, o).single.key, 'low10');
    },
  );
  test(
    'history preserves gaps, measures only observed discharge, and deduplicates',
    () {
      final now = DateTime(2026, 11, 7, 12), ledger = BatteryLedger();
      BatteryPoint sample(
        int minute,
        double level, {
        bool plug = false,
        bool screen = false,
      }) => BatteryPoint(
        now.subtract(Duration(minutes: minute)).millisecondsSinceEpoch,
        level,
        plug,
        30,
        4000,
        -100000,
        3000000,
        0,
        screen,
      );
      final points = [
        sample(60, 80, screen: true),
        sample(55, 78, screen: true),
        sample(50, 76),
        sample(10, 60),
        sample(5, 59, plug: true),
        sample(0, 60, plug: true),
      ];
      ledger.merge([...points, points.first], now: now);
      expect(ledger.points.length, 6);
      final summary = ledger.summary(
        now.subtract(const Duration(hours: 1)),
        now,
      );
      expect(
        summary.drain,
        4,
      ); // No invented drain across the 40-minute gap or plugged transition.
      expect(summary.coverage.inMinutes, 20);
      expect(summary.screenOn.inMinutes, 10);
      expect(summary.charging.inMinutes, 5);
      expect(summary.hourlyDrain.values.fold<double>(0, (a, b) => a + b), 4);
    },
  );
  test('history parser rejects malformed and nonsensical levels', () {
    expect(
      () => BatteryPoint.fromList([1, 101, 0, null, null, null, null, null, 0]),
      throwsFormatException,
    );
    expect(() => BatteryPoint.fromList([1, 50]), throwsFormatException);
  });
}
