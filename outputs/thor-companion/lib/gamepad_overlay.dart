import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Android gamepad key codes, matching the Thor's built-in controller layout.
abstract final class PadKey {
  static const a = 96, b = 97, x = 99, y = 100, l1 = 102, r1 = 103;
  static const l2 = 104, r2 = 105, l3 = 106, r3 = 107;
  static const start = 108, select = 109, mode = 110;
}

/// Stick position (−1..1 each axis, y down) to the ±1000 integers Thor Monitor accepts.
(int, int) stickValue(Offset delta, double radius) {
  var d = delta / radius;
  if (d.distance > 1) d = d / d.distance;
  return ((d.dx * 1000).round(), (d.dy * 1000).round());
}

/// Translucent virtual controller. Each control tracks its own pointer, so several
/// can be held at once. Touches outside the controls fall through to the video.
class GamepadOverlay extends StatefulWidget {
  const GamepadOverlay({
    super.key,
    required this.onButton,
    required this.onAxes,
  });
  final void Function(int key, bool down) onButton;
  final void Function(Map<String, int> axes) onAxes;
  @override
  State<GamepadOverlay> createState() => _GamepadOverlayState();
}

class _GamepadOverlayState extends State<GamepadOverlay> {
  int hatX = 0, hatY = 0;

  void hat(int x, int y, bool down) {
    if (down) {
      if (x != 0) hatX = x;
      if (y != 0) hatY = y;
    } else {
      if (x != 0 && hatX == x) hatX = 0;
      if (y != 0 && hatY == y) hatY = 0;
    }
    widget.onAxes({'hx': hatX, 'hy': hatY});
  }

  void trigger(int key, String axis, bool down) {
    widget.onButton(key, down);
    widget.onAxes({axis: down ? 1000 : 0});
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final s = math.min(box.maxWidth / 2, box.maxHeight).clamp(120.0, 260.0);
      final b = s * 0.24; // face button size
      Widget button(String label, int key) => _PadButton(
        label: label,
        size: b,
        onChanged: (down) => widget.onButton(key, down),
      );
      Widget dpad(IconData icon, int x, int y) =>
          _PadButton(icon: icon, size: b, onChanged: (down) => hat(x, y, down));
      Widget diamond(Widget top, Widget left, Widget right, Widget bottom) =>
          SizedBox(
            width: b * 3,
            height: b * 3,
            child: Stack(
              children: [
                Positioned(left: b, top: 0, child: top),
                Positioned(left: 0, top: b, child: left),
                Positioned(left: b * 2, top: b, child: right),
                Positioned(left: b, top: b * 2, child: bottom),
              ],
            ),
          );
      Widget shoulder(String label, int key, [String? axis]) => _PadButton(
        label: label,
        size: b,
        wide: true,
        onChanged: (down) => axis == null
            ? widget.onButton(key, down)
            : trigger(key, axis, down),
      );
      return Stack(
        children: [
          Positioned(
            left: 8,
            top: 8,
            child: Row(
              children: [
                shoulder('L2', PadKey.l2, 'l'),
                const SizedBox(width: 6),
                shoulder('L1', PadKey.l1),
              ],
            ),
          ),
          Positioned(
            right: 8,
            top: 8,
            child: Row(
              children: [
                shoulder('R1', PadKey.r1),
                const SizedBox(width: 6),
                shoulder('R2', PadKey.r2, 'r'),
              ],
            ),
          ),
          Positioned(
            left: 8,
            bottom: 8,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _Stick(
                  size: b * 2.6,
                  onMove: (x, y) => widget.onAxes({'x': x, 'y': y}),
                  onPress: (down) => widget.onButton(PadKey.l3, down),
                ),
                SizedBox(height: b * 0.3),
                diamond(
                  dpad(Icons.keyboard_arrow_up, 0, -1),
                  dpad(Icons.keyboard_arrow_left, -1, 0),
                  dpad(Icons.keyboard_arrow_right, 1, 0),
                  dpad(Icons.keyboard_arrow_down, 0, 1),
                ),
              ],
            ),
          ),
          Positioned(
            right: 8,
            bottom: 8,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                diamond(
                  button('Y', PadKey.y),
                  button('X', PadKey.x),
                  button('B', PadKey.b),
                  button('A', PadKey.a),
                ),
                SizedBox(height: b * 0.3),
                _Stick(
                  size: b * 2.6,
                  onMove: (x, y) => widget.onAxes({'z': x, 'rz': y}),
                  onPress: (down) => widget.onButton(PadKey.r3, down),
                ),
              ],
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 8,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _PadButton(
                  label: 'Select',
                  size: b * 0.8,
                  wide: true,
                  onChanged: (d) => widget.onButton(PadKey.select, d),
                ),
                const SizedBox(width: 8),
                _PadButton(
                  icon: Icons.sports_esports_outlined,
                  size: b * 0.8,
                  semantic: 'Controller home',
                  onChanged: (d) => widget.onButton(PadKey.mode, d),
                ),
                const SizedBox(width: 8),
                _PadButton(
                  label: 'Start',
                  size: b * 0.8,
                  wide: true,
                  onChanged: (d) => widget.onButton(PadKey.start, d),
                ),
              ],
            ),
          ),
        ],
      );
    },
  );
}

class _PadButton extends StatefulWidget {
  const _PadButton({
    this.label,
    this.icon,
    required this.size,
    required this.onChanged,
    this.wide = false,
    this.semantic,
  });
  final String? label, semantic;
  final IconData? icon;
  final double size;
  final bool wide;
  final ValueChanged<bool> onChanged;
  @override
  State<_PadButton> createState() => _PadButtonState();
}

class _PadButtonState extends State<_PadButton> {
  int? pointer;
  void set(int? p) {
    final down = p != null;
    if ((pointer != null) == down) return;
    setState(() => pointer = p);
    widget.onChanged(down);
  }

  @override
  void dispose() {
    if (pointer != null) widget.onChanged(false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: widget.semantic ?? widget.label,
    child: Listener(
      onPointerDown: (e) => set(e.pointer),
      onPointerUp: (e) => e.pointer == pointer ? set(null) : null,
      onPointerCancel: (e) => e.pointer == pointer ? set(null) : null,
      child: Container(
        width: widget.size * (widget.wide ? 1.6 : 1),
        height: widget.size * (widget.wide ? 0.7 : 1),
        margin: const EdgeInsets.all(2),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: pointer != null ? 0.45 : 0.18),
          border: Border.all(color: Colors.white.withValues(alpha: 0.5)),
          borderRadius: BorderRadius.circular(widget.size),
        ),
        child: widget.icon != null
            ? Icon(widget.icon, color: Colors.white, size: widget.size * 0.55)
            : Text(
                widget.label!,
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: widget.size * (widget.wide ? 0.28 : 0.4),
                ),
              ),
      ),
    ),
  );
}

class _Stick extends StatefulWidget {
  const _Stick({
    required this.size,
    required this.onMove,
    required this.onPress,
  });
  final double size;
  final void Function(int x, int y) onMove;
  final ValueChanged<bool> onPress;
  @override
  State<_Stick> createState() => _StickState();
}

class _StickState extends State<_Stick> {
  int? pointer;
  Offset knob = Offset.zero;
  DateTime sent = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime? downAt;

  void move(Offset local, {bool force = false}) {
    final r = widget.size / 2;
    final (x, y) = stickValue(local - Offset(r, r), r * 0.8);
    setState(() => knob = Offset(x / 1000, y / 1000) * r * 0.8);
    final now = DateTime.now();
    // About 30 updates a second keeps the link light; the final position always goes out.
    if (force || now.difference(sent) >= const Duration(milliseconds: 33)) {
      sent = now;
      widget.onMove(x, y);
    }
  }

  void release() {
    pointer = null;
    setState(() => knob = Offset.zero);
    widget.onMove(0, 0);
    // A quick tap without moving clicks the stick (L3/R3).
    if (downAt != null &&
        DateTime.now().difference(downAt!) <
            const Duration(milliseconds: 200)) {
      widget.onPress(true);
      widget.onPress(false);
    }
    downAt = null;
  }

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Analog stick',
    child: Listener(
      onPointerDown: (e) {
        if (pointer != null) return;
        pointer = e.pointer;
        downAt = DateTime.now();
      },
      onPointerMove: (e) {
        if (e.pointer != pointer) return;
        if (e.delta.distance > 0) downAt = null;
        move(e.localPosition);
      },
      onPointerUp: (e) => e.pointer == pointer ? release() : null,
      onPointerCancel: (e) => e.pointer == pointer ? release() : null,
      child: Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withValues(alpha: 0.12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.4)),
        ),
        child: Center(
          child: Transform.translate(
            offset: knob,
            child: Container(
              width: widget.size * 0.4,
              height: widget.size * 0.4,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.4),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
