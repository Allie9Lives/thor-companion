import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thor_companion/pairing_recovery.dart';

void main() {
  testWidgets('repair requires system-forget confirmation before fresh scan', (
    tester,
  ) async {
    bool? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await showPairingRecovery(context);
              },
              child: const Text('Fix connection'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Fix connection'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Settings → Bluetooth'), findsOneWidget);
    expect(find.textContaining('Automatic retries are paused'), findsOneWidget);
    final button = find.widgetWithText(FilledButton, 'Scan for device');
    await tester.ensureVisible(button);
    expect(tester.widget<FilledButton>(button).onPressed, isNull);
    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    expect(tester.widget<FilledButton>(button).onPressed, isNotNull);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(result, isTrue);
    expect(tester.takeException(), isNull);
  });
  testWidgets('host approval recovery keeps pairing and offers a read retry', (
    tester,
  ) async {
    bool? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await showPairingRecovery(
                  context,
                  hostAuthorization: true,
                );
              },
              child: const Text('Fix connection'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Fix connection'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Repair phone connection'), findsOneWidget);
    expect(find.textContaining('Settings → Bluetooth'), findsNothing);
    expect(find.text('Scan for device'), findsNothing);
    final button = find.widgetWithText(FilledButton, 'Try again');
    await tester.ensureVisible(button);
    expect(tester.widget<FilledButton>(button).onPressed, isNull);
    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(result, true);
  });
}
