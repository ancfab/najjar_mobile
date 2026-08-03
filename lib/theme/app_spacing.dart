/// Purpose: The shared spacing scale for the app — the small, fixed set of
/// gap/padding values already used, ad hoc, throughout the codebase (as
/// bare numeric literals in `SizedBox`/`EdgeInsets`), collected here under
/// one semantic name each rather than as a new set of values.
///
/// Each constant below was chosen to match the value already most commonly
/// used for that purpose across the app (confirmed by inspection, not
/// invented), so adopting it does not change any existing layout.
///
/// Must not:
/// - Grow into an arbitrary/large set of one-off values — if a spacing need
///   doesn't fit this scale, that is a signal to reconsider the layout, not
///   to add a new constant here.
class AppSpacing {
  AppSpacing._();

  /// Tightest gap — e.g. between a label and the value directly below it.
  static const double xs = 4;

  /// Gap between closely related inline elements (an icon and its label,
  /// two buttons in a row).
  static const double sm = 8;

  /// Gap between a row's leading visual (icon/thumbnail) and its content,
  /// or between stacked lines within one card.
  static const double md = 12;

  /// The most common container padding and inter-section gap across the
  /// app (e.g. the Home screen's scroll padding, most card padding).
  static const double lg = 16;

  /// Larger container padding, used where a screen intentionally gives
  /// content more breathing room (e.g. bottom-sheet content padding).
  static const double xl = 20;

  /// Spacing between major, visually distinct page sections.
  static const double xxl = 24;

  /// Horizontal padding applied to a page's primary scrollable content
  /// column. Matches [lg] — kept as a separate, semantically named alias
  /// (rather than a new value) so call sites can express intent.
  static const double pageHorizontal = lg;
}
