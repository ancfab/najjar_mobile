import 'package:flutter/material.dart';

/// Purpose: The app's single source of truth for the established ANC color
/// palette — every screen/widget must reference these named tokens rather
/// than repeating a raw [Color]/hex literal.
///
/// Semantic role reference (confirmed against actual usage across the app
/// rather than invented): this class already covers every palette role the
/// shared design system needs.
/// - Primary text: [textNavy]. Secondary/muted text: [grayText].
/// - Success/positive state: [darkTeal] on a [mint] background — the
///   pairing already used for "paid"/credit/positive `StatusBadge` and
///   `QuickHistoryCard` states.
/// - Warning/negative-amount state: [darkRedBrown] on a [peach]
///   background — the pairing already used for overdue/debit states.
/// - Error/destructive state: [dangerRed] — used for validation errors and
///   destructive actions (e.g. sign-out).
/// - Card/elevated-component background: [surface] (opaque white),
///   distinct from the page-level [background].
/// - Disabled state: [disabled].
///
/// This class intentionally does not duplicate a same-valued constant under
/// a second name (e.g. a separate `success` constant equal to [darkTeal]) —
/// see the module doc comment on why: it would only add an ambiguous second
/// name for a color that already has an established, narrower-purpose name.
class AppColors {
  AppColors._();

  static const Color primaryNavy = Color(0xFF02006B);
  static const Color textNavy = Color(0xFF00045F);
  static const Color gradientNavyStart = Color(0xFF171A8B);
  static const Color gradientNavyEnd = Color(0xFF25268F);
  static const Color mint = Color(0xFF65E8D2);
  static const Color darkTeal = Color(0xFF006B64);
  static const Color peach = Color(0xFFFFDAD2);
  static const Color darkRedBrown = Color(0xFF6B1B08);
  static const Color background = Color(0xFFFAF8F8);
  static const Color border = Color(0xFFD8D6E4);
  static const Color grayText = Color(0xFF6E6E7A);
  static const Color dangerRed = Color(0xFFEE2B2B);

  /// Green used for primary "action" buttons on dark/navy surfaces (e.g. the
  /// Order Detail Price Breakdown card's Invoice button).
  static const Color actionGreen = Color(0xFF1E9E6B);

  /// Opaque white background for elevated components (cards, sheets, the
  /// bottom nav bar, the Home header) — distinct from [background], which is
  /// the page/scaffold-level off-white. Was previously written ad hoc as
  /// `Colors.white` at each call site; this is the semantic name for that
  /// same, already-in-use color, not a new visual value.
  static const Color surface = Color(0xFFFFFFFF);

  /// Muted gray for disabled interactive elements (text, icons, borders).
  /// No prior equivalent existed in the palette.
  static const Color disabled = Color(0xFFB9B9C3);
}
