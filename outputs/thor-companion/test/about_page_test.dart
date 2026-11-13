import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thor_companion/about_page.dart';

void main() {
  testWidgets('About shows author, version and the GitHub action', (
    tester,
  ) async {
    final calls = <String>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(aboutBridge, (call) async {
      calls.add(call.method);
      return call.method == 'version'
          ? {'version': '0.16.2', 'build': '32'}
          : null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(aboutBridge, null));
    await tester.pumpWidget(const MaterialApp(home: AboutPage()));
    await tester.pumpAndSettle();
    expect(find.text('© 2026 Allie Stark (Allie9Lives)'), findsOneWidget);
    expect(find.text('Version 0.16.2 (32)'), findsOneWidget);
    expect(find.text('@Allie9Lives'), findsOneWidget);
    expect(
      find.image(const AssetImage('assets/author-avatar.png')),
      findsOneWidget,
    );
    await tester.tap(find.text('GitHub'));
    await tester.pump();
    expect(calls, ['version', 'github']);
    expect(tester.takeException(), isNull);
  });
}
