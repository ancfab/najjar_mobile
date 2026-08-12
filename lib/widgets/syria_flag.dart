import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Paints the current flag of Syria: green-white-black horizontal stripes
/// with three red five-pointed stars centered in the white stripe.
///
/// Rendered locally with [CustomPaint] instead of the 🇸🇾 Unicode flag emoji,
/// whose glyph is supplied by the platform/font and can still render the
/// pre-2024 flag (red-white-black, two green stars) on devices with an
/// outdated emoji font. Painting it ourselves guarantees the current design
/// shows consistently on every platform.
class SyriaFlag extends StatelessWidget {
  const SyriaFlag({super.key, required this.size});

  /// Visual height of the flag, matching the emoji font size used elsewhere
  /// for other countries' flags.
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size * 1.5,
      height: size,
      child: const CustomPaint(painter: _SyriaFlagPainter()),
    );
  }
}

class _SyriaFlagPainter extends CustomPainter {
  const _SyriaFlagPainter();

  static const _green = Color(0xFF007A3D);
  static const _white = Color(0xFFFFFFFF);
  static const _black = Color(0xFF000000);
  static const _red = Color(0xFFCE1126);

  @override
  void paint(Canvas canvas, Size size) {
    final stripeHeight = size.height / 3;

    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, stripeHeight),
      Paint()..color = _green,
    );
    canvas.drawRect(
      Rect.fromLTWH(0, stripeHeight, size.width, stripeHeight),
      Paint()..color = _white,
    );
    canvas.drawRect(
      Rect.fromLTWH(0, stripeHeight * 2, size.width, stripeHeight),
      Paint()..color = _black,
    );

    final starPaint = Paint()..color = _red;
    final starRadius = stripeHeight * 0.38;
    final centerY = stripeHeight * 1.5;
    for (final fraction in const [0.25, 0.5, 0.75]) {
      _drawStar(
        canvas,
        Offset(size.width * fraction, centerY),
        starRadius,
        starPaint,
      );
    }
  }

  void _drawStar(Canvas canvas, Offset center, double outerRadius, Paint paint) {
    const points = 5;
    final innerRadius = outerRadius * 0.382;
    final path = Path();
    for (var i = 0; i < points * 2; i++) {
      final radius = i.isEven ? outerRadius : innerRadius;
      final angle = -math.pi / 2 + i * math.pi / points;
      final point = Offset(
        center.dx + radius * math.cos(angle),
        center.dy + radius * math.sin(angle),
      );
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _SyriaFlagPainter oldDelegate) => false;
}
