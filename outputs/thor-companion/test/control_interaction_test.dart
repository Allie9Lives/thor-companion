import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thor_companion/ble_transport.dart';
import 'package:thor_companion/companion_controller.dart';
import 'package:thor_companion/controls.dart';
import 'package:thor_companion/ui.dart';
import 'controls_test.dart' show ControlBle;

void main() {
  for (final setting in ['brightness', 'volume']) {
    testWidgets(
      'linked $setting previews together and other controls stay active',
      (tester) async {
        final ble = ControlBle();
        ble.state['power_control'] = true;
        final c = CompanionController(transport: ble, rememberDevice: false);
        var disposed = false;
        addTearDown(() async {
          if (!disposed) c.dispose();
          await ble.close();
        });
        tester.view.physicalSize = const Size(1000, 2400);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            theme: appTheme(Brightness.light),
            home: Scaffold(
              body: SingleChildScrollView(
                child: AnimatedBuilder(
                  animation: c,
                  builder: (_, _) => ControlsPage(controller: c),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        await c.connect(const NearbyThor('thor', 'Thor', -50));
        ble.links.add(LinkState.connected);
        await tester.pump();
        await tester.pump();
        tester
            .widget<SwitchListTile>(
              find.widgetWithText(
                SwitchListTile,
                setting == 'brightness' ? 'Sync screens' : 'Sync volume',
              ),
            )
            .onChanged!(true);
        await tester.pumpAndSettle();
        expect(
          c.controlNumber(setting == 'brightness' ? 'bb' : 'vb'),
          c.controlNumber(setting == 'brightness' ? 'bt' : 'vt'),
        );
        final offset = setting == 'brightness' ? 0 : 2;
        final sliders = find.byType(Slider);
        final before = ble.writes;
        ble.holdWrite = Completer<void>();
        tester.widget<Slider>(sliders.at(offset)).onChanged!(73);
        await tester.pump();
        expect(tester.widget<Slider>(sliders.at(offset)).value, 73);
        expect(tester.widget<Slider>(sliders.at(offset + 1)).value, 73);
        expect(
          ble.writes,
          before + 1,
        ); // The first live value reaches the transport before release.
        tester.widget<Slider>(sliders.at(offset)).onChangeEnd!(73);
        await tester.pump();
        expect(ble.writes, before + 1);
        expect(tester.widget<Slider>(sliders.at(offset + 1)).value, 73);
        for (final slider in tester.widgetList<Slider>(sliders)) {
          expect(slider.onChanged, isNotNull);
        }
        final toggle = tester.widget<SwitchListTile>(
          find.widgetWithText(SwitchListTile, 'Vibration'),
        );
        expect(toggle.onChanged, isNotNull);
        ble.holdWrite!.complete();
        await tester.pumpAndSettle();
        expect(c.controlError, isNull);
        expect(c.controlNumber(setting == 'brightness' ? 'bb' : 'vb'), 73);
        expect(tester.takeException(), isNull);
        ble.blocked = Completer<List<int>>();
        final refresh = c.refresh();
        await tester.pump();
        expect(c.reading, isTrue);
        final powerButtons = [
          'Sleep screens',
          'Restart',
          'Shut down',
        ].map((label) => find.widgetWithText(OutlinedButton, label)).toList();
        for (final button in powerButtons) {
          expect(tester.widget<OutlinedButton>(button).onPressed, isNotNull);
        }
        final rects = powerButtons.map(tester.getRect).toList();
        expect(rects[0].left, rects[1].left);
        expect(rects[1].left, rects[2].left);
        expect(rects[0].bottom, lessThan(rects[1].top));
        expect(rects[1].bottom, lessThan(rects[2].top));
        final shutdown = tester.widget<OutlinedButton>(powerButtons.last);
        final palette = Theme.of(tester.element(powerButtons.last)).colorScheme;
        expect(shutdown.style!.foregroundColor!.resolve({}), palette.error);
        expect(find.text('Device Power'), findsOneWidget);
        for (final slider in tester.widgetList<Slider>(sliders)) {
          expect(slider.onChanged, isNotNull);
        }
        ble.blocked!.complete(
          utf8.encode('{"seq":123,"ts_ms":1000,"battery_pct":69}'),
        );
        await refresh;
        await tester.pump();
        await tester.pumpWidget(const SizedBox());
        c.dispose();
        disposed = true;
      },
    );
  }
}
