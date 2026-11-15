import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thor_companion/companion_controller.dart';
import 'package:thor_companion/main.dart';
import 'package:thor_companion/telemetry.dart';

void main() {
  testWidgets(
    'live overview updates preserve offset and fling direction on iOS',
    (tester) async {
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
      scroll.jumpTo(400);
      await tester.pump();
      for (var i = 0; i < 6; i++) {
        c.receivedAt = DateTime.now();
        c.notifyListeners();
        await tester.pump(const Duration(milliseconds: 16));
        expect(scroll.pixels, closeTo(400, .1));
      }
      await tester.fling(
        find.byType(Scrollable).first,
        const Offset(0, -180),
        900,
      );
      var previous = scroll.pixels;
      for (var i = 0; i < 8; i++) {
        c.stats = DeviceStats.fromBytes(
          utf8.encode(
            jsonEncode({
              'seq': i,
              'ts_ms': DateTime.now().millisecondsSinceEpoch,
              'battery_pct': 70 + i,
              'status_code': 3,
              'plugged_code': 0,
              'temp_c': 30 + i / 10,
              'cpu_pct': 10 + i,
              'cpu_window_ms': 30000,
              'ram_free_bytes': 8000000000,
              'free_bytes': 500000000000,
              'sd_state': 'not_present',
            }),
          ),
        );
        c.notifyListeners();
        await tester.pump(const Duration(milliseconds: 16));
        expect(scroll.pixels, greaterThanOrEqualTo(previous - .1));
        previous = scroll.pixels;
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );
}
