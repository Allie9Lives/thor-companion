import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thor_companion/ble_transport.dart';
import 'package:thor_companion/companion_controller.dart';
import 'package:thor_companion/controls.dart';
import 'controls_test.dart' show ControlBle;

void main() {
  testWidgets(
    'locator locks volume only and restores sliders after host dismissal',
    (tester) async {
      final ble = ControlBle();
      ble.state['finder'] = true;
      ble.state['find'] = 1;
      final c = CompanionController(transport: ble, rememberDevice: false);
      tester.view.physicalSize = const Size(1000, 2800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
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
      await c.connect(const NearbyThor('thor', 'Thor', -50));
      ble.links.add(LinkState.connected);
      await tester.pump();
      await tester.pump();
      await c.refreshControls();
      await tester.pump();
      final sliders = find.byType(Slider);
      expect(sliders, findsNWidgets(4));
      expect(tester.widget<Slider>(sliders.at(0)).onChanged, isNotNull);
      expect(tester.widget<Slider>(sliders.at(1)).onChanged, isNotNull);
      expect(tester.widget<Slider>(sliders.at(2)).onChanged, isNull);
      expect(tester.widget<Slider>(sliders.at(3)).onChanged, isNull);
      expect(
        find.text('Volume locked · Find my Thor is playing'),
        findsOneWidget,
      );
      final before = ble.writes;
      await c.setControl('volume', 5, target: 'both');
      expect(ble.writes, before);
      ble.state['find'] = 0;
      await c.refreshControls();
      await tester.pump();
      expect(tester.widget<Slider>(sliders.at(2)).onChanged, isNotNull);
      expect(tester.widget<Slider>(sliders.at(3)).onChanged, isNotNull);
      await c.setControl('volume', 50, target: 'both');
      expect(ble.writes, before + 1);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
      await ble.close();
    },
  );
}
