import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'ui.dart';

const thorCurve = Cubic(.22, .8, .22, 1);
Duration motionDuration(BuildContext context, [int milliseconds = 240]) =>
    MediaQuery.disableAnimationsOf(context)
    ? Duration.zero
    : Duration(milliseconds: milliseconds);

/// Soft accent glow for pressed (strength 1) and selected (about .5) controls,
/// matching the Web Ops tiles. Empty when off, so AnimatedContainer fades it.
List<BoxShadow> glow(Color color, double strength) => strength <= 0
    ? const []
    : [
        BoxShadow(
          color: color.withValues(alpha: .5 * strength),
          blurRadius: 26,
          spreadRadius: -3,
          offset: const Offset(0, 6),
        ),
      ];

/// Slide-up for bottom-sheet menus: a little longer, with Thor's ease-out curve.
AnimationStyle thorSheetAnimation(BuildContext context) =>
    MediaQuery.disableAnimationsOf(context)
    ? AnimationStyle.noAnimation
    : const AnimationStyle(
        duration: Duration(milliseconds: 380),
        reverseDuration: Duration(milliseconds: 240),
        curve: thorCurve,
        reverseCurve: Curves.easeInCubic,
      );

/// Tracks a finger on [child] without taking the tap, for press glows.
class PressGlow extends StatefulWidget {
  const PressGlow({super.key, required this.builder, this.enabled = true});
  final Widget Function(BuildContext context, bool pressed) builder;
  final bool enabled;
  @override
  State<PressGlow> createState() => _PressGlowState();
}

class _PressGlowState extends State<PressGlow> {
  bool pressed = false;
  Offset? down;
  Timer? delay;
  void set(bool value) {
    if (pressed != value && mounted) setState(() => pressed = value);
  }

  // A finger that starts a scroll must not light the tile: the glow would
  // repaint its blurred shadow every frame of the drag. Wait like InkWell
  // does, and drop the press once the finger moves past touch slop.
  void release({bool tapped = false}) {
    final waiting = delay?.isActive ?? false;
    delay?.cancel();
    down = null;
    if (tapped && waiting) {
      set(true);
      delay = Timer(const Duration(milliseconds: 120), () => set(false));
    } else {
      set(false);
    }
  }

  @override
  void dispose() {
    delay?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: widget.enabled
        ? (e) {
            down = e.position;
            delay?.cancel();
            delay = Timer(kPressTimeout, () => set(true));
          }
        : null,
    onPointerMove: (e) {
      if (down != null && (e.position - down!).distance > kTouchSlop) {
        release();
      }
    },
    onPointerUp: (_) => release(tapped: down != null),
    onPointerCancel: (_) => release(),
    child: widget.builder(context, pressed && widget.enabled),
  );
}

/// Slider thumb that blooms a soft glow while it is dragged.
class GlowThumbShape extends SliderComponentShape {
  const GlowThumbShape();
  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) =>
      const Size.fromRadius(12);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final canvas = context.canvas, t = activationAnimation.value;
    final color = enableAnimation.value < 1
        ? sliderTheme.disabledThumbColor ?? Colors.grey
        : sliderTheme.thumbColor ?? Colors.white;
    if (t > 0) {
      canvas.drawCircle(
        center,
        12 + 10 * t,
        Paint()
          ..color = color.withValues(alpha: .38 * t)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
      );
    }
    canvas.drawCircle(center, 10 + 2 * t, Paint()..color = color);
  }
}

class SectionHeading extends StatelessWidget {
  const SectionHeading(this.title, this.icon, {super.key, this.trailing});
  final String title;
  final IconData icon;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: p.accent.withValues(alpha: .08),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 19, color: p.accent),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              letterSpacing: -.2,
            ),
          ),
        ),
        ?trailing,
      ],
    );
  }
}

/// A shared tile for Settings and Tools, with a quiet press response.
class ActionTile extends StatefulWidget {
  const ActionTile({
    super.key,
    required this.label,
    required this.icon,
    this.subtitle,
    this.onPressed,
    this.selected = false,
    this.nested = false,
    this.color,
  });
  final String label;
  final IconData icon;
  final String? subtitle;
  final VoidCallback? onPressed;
  final bool selected, nested;
  final Color? color;
  @override
  State<ActionTile> createState() => _ActionTileState();
}

class _ActionTileState extends State<ActionTile> {
  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context), color = widget.color ?? p.accent;
    return PressGlow(
      enabled: widget.onPressed != null,
      builder: (context, pressed) => AnimatedScale(
        scale: pressed ? .975 : 1,
        duration: motionDuration(context, 140),
        curve: thorCurve,
        child: AnimatedContainer(
          duration: motionDuration(context, 220),
          curve: thorCurve,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            boxShadow: glow(
              color,
              pressed
                  ? 1
                  : widget.selected
                  ? .5
                  : 0,
            ),
          ),
          child: OutlinedButton(
            onPressed: widget.onPressed,
            style: OutlinedButton.styleFrom(
              foregroundColor: p.foreground,
              backgroundColor: widget.selected
                  ? color.withValues(alpha: .10)
                  : widget.nested
                  ? p.background
                  : p.card,
              side: BorderSide(
                color: widget.selected ? color : p.border,
                width: widget.selected ? 1.5 : 1,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              padding: const EdgeInsets.all(16),
              alignment: Alignment.centerLeft,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: .09),
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: Icon(
                        widget.icon,
                        size: 21,
                        color: widget.onPressed == null
                            ? p.secondaryText
                            : color,
                      ),
                    ),
                    const Spacer(),
                    if (widget.selected)
                      Icon(Icons.check_circle_rounded, size: 18, color: color),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  widget.label,
                  maxLines: 2,
                  style: const TextStyle(
                    fontSize: 16,
                    height: 1.2,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (widget.subtitle != null) ...[
                  const SizedBox(height: 5),
                  Text(
                    widget.subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.25,
                      color: p.secondaryText,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class AnimatedReadingBar extends StatelessWidget {
  const AnimatedReadingBar({
    super.key,
    required this.value,
    this.minHeight = 6,
    this.backgroundColor,
    this.valueColor,
  });
  final double value, minHeight;
  final Color? backgroundColor;
  final Animation<Color?>? valueColor;
  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 0, end: value.clamp(0, 1)),
    duration: motionDuration(context, 420),
    curve: thorCurve,
    builder: (context, reading, _) => LinearProgressIndicator(
      value: reading,
      minHeight: minHeight,
      backgroundColor: backgroundColor,
      valueColor: valueColor,
    ),
  );
}
