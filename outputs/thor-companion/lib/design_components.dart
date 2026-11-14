import 'package:flutter/material.dart';
import 'ui.dart';

const thorCurve = Cubic(.22, .8, .22, 1);
Duration motionDuration(BuildContext context, [int milliseconds = 240]) =>
    MediaQuery.disableAnimationsOf(context)
    ? Duration.zero
    : Duration(milliseconds: milliseconds);

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
  bool pressed = false;
  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context), color = widget.color ?? p.accent;
    return Listener(
      onPointerDown: widget.onPressed == null
          ? null
          : (_) => setState(() => pressed = true),
      onPointerUp: (_) => setState(() => pressed = false),
      onPointerCancel: (_) => setState(() => pressed = false),
      child: AnimatedScale(
        scale: pressed ? .975 : 1,
        duration: motionDuration(context, 140),
        curve: thorCurve,
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
                      color: widget.onPressed == null ? p.secondaryText : color,
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
