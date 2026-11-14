import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/services.dart';

const iconBackground = Color(0xFF18181B);
const iconForeground = Color(0xFFF5F5F7);

enum AppAppearance { system, light, dark, clearPurple, rainbow }

AppAppearance appearanceFromName(String? name) => AppAppearance.values
    .firstWhere((a) => a.name == name, orElse: () => AppAppearance.system);

class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette(
    this.background,
    this.card,
    this.border,
    this.foreground,
    this.secondaryText,
    this.accent,
    this.onAccent,
    this.warning,
    this.warningSurface,
    this.warningBorder, {
    this.appearance = AppAppearance.system,
  });

  static const light = AppPalette(
    Color(0xFFF2F2F5),
    Color(0xFFFFFFFF),
    Color(0xFFDEDEE3),
    Color(0xFF19191C),
    Color(0xFF63636C),
    Color(0xFF252529),
    Color(0xFFFFFFFF),
    Color(0xFF8A4F00),
    Color(0xFFFFF4E3),
    Color(0xFFE8CC9E),
  );
  static const dark = AppPalette(
    Color(0xFF111113),
    Color(0xFF1C1C1F),
    Color(0xFF333337),
    Color(0xFFF5F5F7),
    Color(0xFFA2A2AA),
    Color(0xFFE7E7EB),
    Color(0xFF18181B),
    Color(0xFFF0BE7A),
    Color(0xFF2B241B),
    Color(0xFF6A5031),
  );
  static const clearPurple = AppPalette(
    Color(0xFF1D1825),
    Color(0xFF2C2438),
    Color(0xFF4D405F),
    Color(0xFFF5EFFB),
    Color(0xFFC5B9D3),
    Color(0xFFC6B2E5),
    Color(0xFF281B3A),
    Color(0xFFF0BE7A),
    Color(0xFF332A26),
    Color(0xFF70563E),
    appearance: AppAppearance.clearPurple,
  );
  static const rainbow = AppPalette(
    Color(0xFFFAFBFD),
    Colors.white,
    Color(0xFFDCE2EB),
    Color(0xFF202630),
    Color(0xFF596474),
    Color(0xFF285BC5),
    Colors.white,
    Color(0xFF8A4F00),
    Color(0xFFFFF4E3),
    Color(0xFFE8CC9E),
    appearance: AppAppearance.rainbow,
  );
  final AppAppearance appearance;
  Color get brandColor => appearance == AppAppearance.clearPurple
      ? const Color(0xFF6B5C87)
      : accent;
  bool get isRainbow => appearance == AppAppearance.rainbow;
  List<Color> get rainbowColors => const [
    Color(0xFFC08A00),
    Color(0xFF24794B),
    Color(0xFF285BC5),
    Color(0xFFBA4141),
  ];
  Color metricAccent(String metric) => !isRainbow
      ? accent
      : switch (metric) {
          'CPU' || 'Internal storage' => rainbowColors[0],
          'GPU' || 'microSD card' => rainbowColors[1],
          'RAM' => rainbowColors[3],
          _ => rainbowColors[2],
        };
  static AppPalette of(BuildContext context) =>
      Theme.of(context).extension<AppPalette>() ??
      (Theme.of(context).brightness == Brightness.dark ? dark : light);
  @override
  AppPalette copyWith() => this;
  @override
  AppPalette lerp(covariant AppPalette? other, double t) {
    if (other == null) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppPalette(
      mix(background, other.background),
      mix(card, other.card),
      mix(border, other.border),
      mix(foreground, other.foreground),
      mix(secondaryText, other.secondaryText),
      mix(accent, other.accent),
      mix(onAccent, other.onAccent),
      mix(warning, other.warning),
      mix(warningSurface, other.warningSurface),
      mix(warningBorder, other.warningBorder),
      appearance: t < .5 ? appearance : other.appearance,
    );
  }

  final Color background,
      card,
      border,
      foreground,
      secondaryText,
      accent,
      onAccent;
  final Color warning, warningSurface, warningBorder;
}

ThemeData appTheme(
  Brightness brightness, {
  AppAppearance appearance = AppAppearance.system,
}) {
  final p = switch (appearance) {
    AppAppearance.clearPurple => AppPalette.clearPurple,
    AppAppearance.rainbow => AppPalette.rainbow,
    _ => brightness == Brightness.dark ? AppPalette.dark : AppPalette.light,
  };
  final scheme = ColorScheme(
    brightness: brightness,
    primary: p.accent,
    onPrimary: p.onAccent,
    primaryContainer: p.appearance == AppAppearance.clearPurple
        ? p.brandColor
        : p.border,
    onPrimaryContainer: p.appearance == AppAppearance.clearPurple
        ? Colors.white
        : p.foreground,
    secondary: p.isRainbow ? p.rainbowColors[1] : p.accent,
    onSecondary: p.onAccent,
    secondaryContainer: p.border,
    onSecondaryContainer: p.foreground,
    tertiary: p.isRainbow ? p.rainbowColors[0] : p.accent,
    onTertiary: p.onAccent,
    error: brightness == Brightness.dark
        ? const Color(0xFFFFB4AB)
        : const Color(0xFFB3261E),
    onError: brightness == Brightness.dark
        ? const Color(0xFF690005)
        : Colors.white,
    surface: p.card,
    onSurface: p.foreground,
    onSurfaceVariant: p.secondaryText,
    surfaceContainerHighest: p.border,
    surfaceContainerHigh: p.card,
    surfaceContainer: p.card,
    surfaceContainerLow: p.background,
    surfaceContainerLowest: p.background,
    outline: p.border,
    outlineVariant: p.border,
    surfaceTint: Colors.transparent,
  );
  return ThemeData(
    useMaterial3: true,
    splashFactory: NoSplash.splashFactory,
    highlightColor: p.accent.withValues(alpha: .07),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
        TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
      },
    ),
    extensions: [p],
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: p.background,
    appBarTheme: AppBarTheme(
      backgroundColor: p.background,
      foregroundColor: p.foreground,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: p.foreground,
        fontSize: 20,
        fontWeight: FontWeight.w600,
        letterSpacing: -.3,
      ),
    ),
    textTheme: TextTheme(
      labelLarge: const TextStyle(fontSize: 16),
      labelMedium: const TextStyle(fontSize: 14),
      bodyMedium: const TextStyle(fontSize: 16, height: 1.45),
      bodySmall: TextStyle(fontSize: 14, height: 1.4, color: p.secondaryText),
      titleLarge: const TextStyle(
        fontSize: 26,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.5,
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.disabled)
            ? p.secondaryText
            : states.contains(WidgetState.selected)
            ? p.onAccent
            : p.foreground,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) ? p.accent : p.border,
      ),
      trackOutlineColor: WidgetStateProperty.resolveWith(
        (states) =>
            states.contains(WidgetState.selected) ? p.accent : p.secondaryText,
      ),
      trackOutlineWidth: const WidgetStatePropertyAll(1),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: p.appearance == AppAppearance.clearPurple
            ? p.brandColor
            : null,
        foregroundColor: p.appearance == AppAppearance.clearPurple
            ? Colors.white
            : null,
        minimumSize: const Size(0, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 48),
        side: BorderSide(color: p.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: p.background,
      indicatorColor: p.border.withValues(alpha: 0.55),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          color: states.contains(WidgetState.selected)
              ? p.foreground
              : p.secondaryText,
        ),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: p.card,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: p.card,
      surfaceTintColor: Colors.transparent,
    ),
  );
}

Widget surface({
  required Widget child,
  EdgeInsets padding = const EdgeInsets.all(18),
  String? copyText,
  String copyLabel = 'Stats',
  VoidCallback? onTap,
}) => Builder(
  builder: (context) {
    final p = AppPalette.of(context);
    final card = Material(
      color: p.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(color: p.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Padding(padding: padding, child: child),
      ),
    );
    if (copyText == null) return card;
    return Semantics(
      hint: 'Long press to copy ${copyLabel.toLowerCase()}',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onLongPress: () async {
          try {
            await Clipboard.setData(ClipboardData(text: copyText));
            if (!context.mounted) return;
            ScaffoldMessenger.maybeOf(context)?.showSnackBar(
              SnackBar(
                content: Text('$copyLabel copied'),
                duration: const Duration(seconds: 2),
              ),
            );
          } catch (_) {
            if (context.mounted) {
              ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                const SnackBar(content: Text('Could not copy stats.')),
              );
            }
          }
        },
        child: card,
      ),
    );
  },
);

Widget notice(
  String title,
  String description, {
  bool warning = false,
  Widget? trailing,
}) => Builder(
  builder: (context) {
    final p = AppPalette.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: warning ? p.warningSurface : p.card,
        border: Border.all(color: warning ? p.warningBorder : p.border),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    color: warning ? p.warning : p.foreground,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  description,
                  style: TextStyle(color: p.secondaryText, fontSize: 14),
                ),
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  },
);

Widget tag(String label) => Builder(
  builder: (context) {
    final p = AppPalette.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: p.background,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: p.foreground,
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  },
);

class BatteryRing extends CustomPainter {
  BatteryRing(
    this.level, {
    required this.color,
    required this.track,
    required this.lowColor,
  });
  final double? level;
  final Color color, track, lowColor;
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromCircle(
      center: size.center(Offset.zero),
      radius: size.shortestSide / 2 - 8,
    );
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round
      ..color = track;
    canvas.drawArc(rect, 0.75 * math.pi, 1.5 * math.pi, false, p);
    if (level != null) {
      p.color = level! < 20 ? lowColor : color;
      canvas.drawArc(
        rect,
        0.75 * math.pi,
        1.5 * math.pi * (level! / 100).clamp(0, 1),
        false,
        p,
      );
    }
  }

  @override
  bool shouldRepaint(BatteryRing oldDelegate) =>
      oldDelegate.level != level ||
      oldDelegate.color != color ||
      oldDelegate.track != track ||
      oldDelegate.lowColor != lowColor;
}

class HandheldPainter extends CustomPainter {
  const HandheldPainter({this.color = iconBackground});
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.7;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(2, 1, size.width - 4, size.height * 0.48),
        const Radius.circular(3),
      ),
      p,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          2,
          size.height * 0.57,
          size.width - 4,
          size.height * 0.38,
        ),
        const Radius.circular(3),
      ),
      p,
    );
    canvas.drawLine(
      Offset(6, size.height * 0.76),
      Offset(10, size.height * 0.76),
      p,
    );
    canvas.drawLine(
      Offset(8, size.height * 0.68),
      Offset(8, size.height * 0.84),
      p,
    );
    p.style = PaintingStyle.fill;
    canvas.drawCircle(Offset(size.width - 7, size.height * 0.76), 1.3, p);
  }

  @override
  bool shouldRepaint(HandheldPainter oldDelegate) => oldDelegate.color != color;
}
