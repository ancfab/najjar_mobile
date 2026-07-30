import 'package:flutter/material.dart';

import '../localization/translations.dart';
import '../theme/app_colors.dart';

/// Decorative indigo textile panel shown between the Live Specialist
/// Support card and the info cards below.
///
/// No suitable fabric photo asset exists in this project yet, so this is a
/// gradient + subtle woven-line pattern built from Flutter primitives
/// rather than a downloaded stock image.
///
/// TODO: Swap for a real fabric/production photo asset once one is added
/// under `assets/`.
class SupportTextileVisual extends StatelessWidget {
  const SupportTextileVisual({super.key});

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AppColors.gradientNavyStart,
                AppColors.primaryNavy,
                AppColors.gradientNavyEnd,
              ],
            ),
          ),
          child: Stack(
            children: [
              Positioned.fill(child: CustomPaint(painter: _WovenLinePainter())),
              Positioned(
                left: 16,
                right: 16,
                bottom: 14,
                child: Text(
                  context.t('supportTextileVisual.tagline'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4,
                    color: Colors.white.withValues(alpha: 0.92),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Subtle diagonal "weave" line pattern painted over the gradient panel to
/// evoke fabric texture without an actual image asset.
class _WovenLinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.06)
      ..strokeWidth = 1;

    const spacing = 14.0;
    for (double x = -size.height; x < size.width; x += spacing) {
      canvas.drawLine(
        Offset(x, size.height),
        Offset(x + size.height, 0),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _WovenLinePainter oldDelegate) => false;
}
