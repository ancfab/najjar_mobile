import 'package:flutter/material.dart';

/// Purpose: The shared corner-radius scale for the app, matching the radius
/// values already most commonly used for each kind of element (confirmed by
/// inspection across existing screens/widgets, not invented) — adopting
/// these does not change any existing shape.
///
/// Exposes both the raw `double` (for APIs that want a bare radius, e.g.
/// [Radius.circular]) and a ready-made [BorderRadius] (for the common
/// `BorderRadius.circular(...)` call site) per token.
class AppRadius {
  AppRadius._();

  /// Small controls/chips (status badges, small pill buttons, filter chips).
  static const double small = 6;
  static const BorderRadius smallAll = BorderRadius.all(Radius.circular(small));

  /// Text inputs and input-shaped controls (matches every
  /// `OutlineInputBorder` in the login/contact/filter forms).
  static const double input = 10;
  static const BorderRadius inputAll = BorderRadius.all(Radius.circular(input));

  /// Standard buttons (primary/secondary login buttons).
  static const double button = 12;
  static const BorderRadius buttonAll = BorderRadius.all(
    Radius.circular(button),
  );

  /// Cards and other elevated content containers.
  static const double card = 12;
  static const BorderRadius cardAll = BorderRadius.all(Radius.circular(card));

  /// Bottom sheets and dialogs (top corners only, matching the existing
  /// `showModalBottomSheet` shape).
  static const double sheet = 16;
  static const BorderRadius sheetTop = BorderRadius.vertical(
    top: Radius.circular(sheet),
  );

  /// Fully circular/pill touch targets (icon buttons, circular avatars'
  /// tap area, filter-sheet option chips).
  static const double circular = 20;
  static const BorderRadius circularAll = BorderRadius.all(
    Radius.circular(circular),
  );
}
