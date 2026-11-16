import 'package:flutter/services.dart';
import 'ui.dart';

class AppThemeIcon {
  static const channel = MethodChannel('com.alan.thorCompanion/about');
  static Future<void> _tail = Future.value();
  static String? _last;
  static String resolve(AppAppearance appearance, Brightness system) =>
      appearance == AppAppearance.system
      ? system == Brightness.dark
            ? 'dark'
            : 'light'
      : appearance.name;
  static Future<void> sync(AppAppearance appearance, Brightness system) {
    final name = resolve(appearance, system);
    _tail = _tail.then((_) async {
      if (_last == name) return;
      try {
        await channel.invokeMethod<void>('appearanceIcon', name);
        _last = name;
      } catch (_) {
        /* Retry on the next selection or foreground transition. */
      }
    });
    return _tail;
  }
}
