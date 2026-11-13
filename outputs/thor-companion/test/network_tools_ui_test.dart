import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thor_companion/companion_controller.dart';
import 'package:thor_companion/controls.dart';
import 'package:thor_companion/file_transfer.dart';
import 'package:thor_companion/screenshot_page.dart';
import 'package:thor_companion/ui.dart';
import 'controls_test.dart' show ControlBle;

void main() {
  testWidgets('Tools have equal dimensions at large text size', (tester) async {
    final ble = ControlBle();
    final c = CompanionController(transport: ble, rememberDevice: false);
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(Brightness.light),
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: Scaffold(
            body: SingleChildScrollView(child: ControlsPage(controller: c)),
          ),
        ),
      ),
    );
    await tester.pump();
    final labels = [
      'Find my Thor',
      'Open files',
      'Open keyboard',
      'Screen capture',
      'Connection health',
      'Battery insights',
    ];
    final sizes = labels
        .map(
          (label) => tester.getSize(
            find
                .ancestor(
                  of: find.text(label),
                  matching: find.byWidgetPredicate(
                    (w) => w is OutlinedButton || w is FilledButton,
                  ),
                )
                .first,
          ),
        )
        .toList();
    expect(sizes.every((size) => size == sizes.first), isTrue);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
    await ble.close();
  });
  testWidgets('Screenshots stay disabled without network credentials', (
    tester,
  ) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(fileBridge, (call) async => null);
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(fileBridge, null),
    );
    final ble = ControlBle();
    final c = CompanionController(transport: ble, rememberDevice: false);
    await tester.pumpWidget(MaterialApp(home: ScreenshotPage(controller: c)));
    await tester.pumpAndSettle();
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Capture & save'),
    );
    expect(button.onPressed, isNull);
    expect(ble.writes, 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
    await ble.close();
  });
}
