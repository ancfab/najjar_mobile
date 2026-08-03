import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Purpose: The shared typography scale for the app — a named style per
/// concept (hero value, page title, body text, ...) instead of each screen
/// choosing its own `fontSize`/`fontWeight` combination ad hoc.
///
/// Responsibilities:
/// - Use the platform default font family (the app has no custom font
///   asset in `pubspec.yaml`); every style below relies on Flutter's
///   default `TextTheme` font, never a new font dependency.
/// - Carry no fixed `height`/line-height constraint that could clip taller
///   Arabic or French glyphs/diacritics — every style leaves `height`
///   unset (Flutter derives a safe default from the font's own metrics).
/// - Stay compatible with the system text-scale setting: a plain
///   `TextStyle.fontSize` is still scaled by the ambient `MediaQuery`
///   `TextScaler` wherever it's used inside a `Text`/`RichText` widget —
///   these styles never opt out of that via `TextScaler.noScaling` or
///   similar.
/// - Carry no literal copy — every field here is a style, never text.
///
/// Each style is intentionally colorless by default (color is supplied by
/// the call site via `.copyWith(color: ...)`) except where a concept has one
/// fixed, near-universal color in current usage (see [caption]/[label]).
class AppTypography {
  AppTypography._();

  /// Hero/display numeric value — e.g. the Home Balance card's amount.
  static const TextStyle displayValue = TextStyle(
    fontSize: 30,
    fontWeight: FontWeight.bold,
  );

  /// Page-level title — e.g. the Home header's user name.
  static const TextStyle pageTitle = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.bold,
  );

  /// Section title within a page — e.g. a card's own heading.
  static const TextStyle sectionTitle = TextStyle(
    fontSize: 17,
    fontWeight: FontWeight.bold,
  );

  /// Title of an individual card/list row — e.g. an Order card's order ID.
  static const TextStyle cardTitle = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.bold,
  );

  /// Standard body text.
  static const TextStyle body = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.normal,
  );

  /// De-emphasized secondary body text (e.g. a card's helper/subtitle line).
  static const TextStyle bodySecondary = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.normal,
    color: AppColors.grayText,
  );

  /// Small uppercase-style field/section label (e.g. a form field label,
  /// "RECENT SCAN").
  static const TextStyle label = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w600,
  );

  /// Smallest supporting text (e.g. a card's date/meta line).
  static const TextStyle caption = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.normal,
    color: AppColors.grayText,
  );

  /// Button label text.
  static const TextStyle buttonText = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.bold,
  );

  /// Emphasized numeric/currency value inline within content (e.g. an Order
  /// card's price) — distinct from [displayValue], which is for a single
  /// hero figure.
  static const TextStyle numericValue = TextStyle(
    fontSize: 17,
    fontWeight: FontWeight.bold,
  );
}
