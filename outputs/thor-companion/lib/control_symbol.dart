import 'package:flutter/material.dart';
import 'control_symbol_paths.dart';

/// Shared Web Ops/client artwork. Explicit vector paths avoid platform font glyphs.
class ControlSymbol extends StatelessWidget {
  const ControlSymbol(
    this.name, {
    super.key,
    required this.color,
    this.size = 30,
  });
  final String name;
  final Color color;
  final double size;
  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: CustomPaint(painter: ControlSymbolPainter(name, color)),
  );
}

class ControlSymbolPainter extends CustomPainter {
  ControlSymbolPainter(this.name, this.color);
  final String name;
  final Color color;
  static final paths = controlSymbolPaths.map(
    (key, data) => MapEntry(key, data.map(_path).toList()),
  );
  static Path _path(String data) {
    final tokens = RegExp(
      r'[MLCZ]|-?[0-9]+(?:\.[0-9]+)?',
    ).allMatches(data).map((m) => m.group(0)!).toList();
    final path = Path();
    var i = 0;
    double number() => double.parse(tokens[i++]);
    while (i < tokens.length) {
      switch (tokens[i++]) {
        case 'M':
          path.moveTo(number(), number());
        case 'L':
          path.lineTo(number(), number());
        case 'C':
          path.cubicTo(
            number(),
            number(),
            number(),
            number(),
            number(),
            number(),
          );
        case 'Z':
          path.close();
        default:
          throw StateError('Invalid control symbol');
      }
    }
    return path;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.7
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.save();
    canvas.scale(size.width / 24, size.height / 24);
    for (final path in paths[name] ?? const <Path>[]) {
      canvas.drawPath(path, paint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(ControlSymbolPainter old) =>
      old.name != name || old.color != color;
}
