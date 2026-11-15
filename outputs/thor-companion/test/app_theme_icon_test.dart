import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thor_companion/app_theme_icon.dart';
import 'package:thor_companion/ui.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('theme and system brightness map to launcher icons in order', () async {
    final names = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(AppThemeIcon.channel, (call) async {
          expect(call.method, 'appearanceIcon');
          names.add(call.arguments as String);
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(AppThemeIcon.channel, null),
    );
    expect(
      AppThemeIcon.resolve(AppAppearance.system, Brightness.light),
      'light',
    );
    expect(AppThemeIcon.resolve(AppAppearance.system, Brightness.dark), 'dark');
    await Future.wait([
      AppThemeIcon.sync(AppAppearance.dark, Brightness.light),
      AppThemeIcon.sync(AppAppearance.light, Brightness.dark),
      AppThemeIcon.sync(AppAppearance.clearPurple, Brightness.light),
      AppThemeIcon.sync(AppAppearance.rainbow, Brightness.dark),
    ]);
    expect(names, ['dark', 'light', 'clearPurple', 'rainbow']);
    await AppThemeIcon.sync(AppAppearance.rainbow, Brightness.dark);
    expect(names.length, 4);
  });
}
