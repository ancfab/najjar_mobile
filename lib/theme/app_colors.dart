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
///   `QuickHistoryCard` states, and for an available (above-threshold)
///   stock-quantity row.
/// - Negative-amount state: [darkRedBrown] on a [peach] background — the
///   pairing already used for overdue/debit states.
/// - Low-stock warning state: [darkAmber] on a [warningYellow] background —
///   a distinct pairing from the negative-amount one above: this is a
///   caution ("contact support"), not a debit/overdue amount, so reusing
///   [peach]/[darkRedBrown] here would misrepresent the meaning.
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

  /// Light yellow background for the low-stock warning ("contact support")
  /// state — paired with [darkAmber] foreground text. No prior equivalent
  /// existed in the palette; see the class doc comment for why this is not
  /// the same pairing as [peach]/[darkRedBrown].
  static const Color warningYellow = Color(0xFFFFF3B0);

  /// Dark amber foreground text/icon color for content on a [warningYellow]
  /// background — chosen for sufficient contrast against it.
  static const Color darkAmber = Color(0xFF7A5B00);

  // --- "Check Availability" per-variation status pills (Home screen) ---
  //
  // A dedicated, saturated set used ONLY by the Home Check Availability
  // status pills — intentionally not the cyan-leaning [mint]/pale
  // [warningYellow] pairings used elsewhere (scan overlay, badges,
  // QuickHistoryCard, ...), which keep their existing values. Each fill is
  // paired with a foreground chosen for legible text directly on it.

  /// Forest-green fill for the in-stock status (summed remaining quantity
  /// above the low-stock threshold). Paired with [stockAvailableText].
  static const Color stockAvailableBg = Color(0xFF2E7D32);

  /// White foreground for text on [stockAvailableBg].
  static const Color stockAvailableText = Color(0xFFFFFFFF);

  /// Traffic-light yellow fill for the low-stock ("contact support") status
  /// (summed remaining quantity at/below the threshold, but above zero).
  /// Paired with [stockLowText].
  static const Color stockLowBg = Color(0xFFFFC400);

  /// Near-black foreground for text on [stockLowBg].
  static const Color stockLowText = Color(0xFF3D2E00);

  /// Solid red fill for the out-of-stock status (nothing remaining across
  /// any location). Paired with [stockOutText].
  static const Color stockOutBg = Color(0xFFD32F2F);

  /// White foreground for text on [stockOutBg].
  static const Color stockOutText = Color(0xFFFFFFFF);
}
