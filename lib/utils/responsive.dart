import 'package:flutter/material.dart';

/// Screen width above which layouts are treated as "tablet" sized.
///
/// Matches Material's common 600dp breakpoint between compact (phone) and
/// medium (tablet) window size classes.
const double kTabletBreakpoint = 600;

/// Maximum width the app's primary content column is allowed to stretch to
/// on large/tablet screens, so cards, forms, and lists don't become
/// excessively wide/stretched while keeping the existing phone design as-is
/// below [kTabletBreakpoint].
const double kMaxContentWidth = 640;

/// The default cap applied to the system text-scale factor inside fixed-
/// height chrome (app bars, bottom navigation) that cannot grow to
/// accommodate arbitrarily large accessibility text sizes without
/// overflowing. Scrollable body content is never clamped.
const double kChromeMaxTextScaleFactor = 1.3;

/// Centers [child] and caps its width to [maxWidth] on wide/tablet screens,
/// while leaving phone-width layouts completely untouched (the constraint
/// is only ever tighter than the phone width, never looser).
class ResponsiveMaxWidth extends StatelessWidget {
  const ResponsiveMaxWidth({
    super.key,
    required this.child,
    this.maxWidth = kMaxContentWidth,
    this.alignment = Alignment.topCenter,
  });

  final Widget child;
  final double maxWidth;

  /// Where to position the width-capped child within the available space.
  /// Defaults to top-center, matching top-anchored scrollable content
  /// (lists/forms); pass [Alignment.center] for content that should stay
  /// vertically centered (e.g. a centered preview/empty state).
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignment,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}

/// Clamps the system text-scale factor for [child] to at most
/// [maxScaleFactor].
///
/// Intended for fixed-height navigational chrome (app bars, bottom nav)
/// where unbounded text scaling would overflow a slot the surrounding
/// Scaffold gives a fixed height to. Content still grows up to
/// [maxScaleFactor], so it never regresses to an unreadably small size —
/// it just stops short of the point where it would no longer fit.
class ClampedTextScale extends StatelessWidget {
  const ClampedTextScale({
    super.key,
    required this.child,
    this.maxScaleFactor = kChromeMaxTextScaleFactor,
  });

  final Widget child;
  final double maxScaleFactor;

  @override
  Widget build(BuildContext context) {
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: maxScaleFactor,
      child: child,
    );
  }
}

/// A scrollable column that keeps [child] vertically centered when it fits
/// within the available height (matching a plain centered `Column`), but
/// scrolls instead of overflowing when the viewport is shorter than the
/// content — e.g. landscape orientation on short phones, split-screen, or
/// large system text scale.
class CenteredScrollable extends StatelessWidget {
  const CenteredScrollable({
    super.key,
    required this.child,
    this.padding = EdgeInsets.zero,
    this.physics,
  });

  final Widget child;
  final EdgeInsets padding;
  final ScrollPhysics? physics;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final minHeight = (constraints.maxHeight - padding.vertical).clamp(
          0.0,
          double.infinity,
        );
        return SingleChildScrollView(
          padding: padding,
          physics: physics,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: minHeight),
            child: IntrinsicHeight(child: child),
          ),
        );
      },
    );
  }
}
