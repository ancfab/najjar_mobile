import 'package:flutter/material.dart';

/// Purpose: The shared, subtle drop-shadow styles used across the app's
/// white cards — collecting the exact `BoxShadow` values already duplicated
/// verbatim across several widgets under one semantic name each, rather
/// than defining new visual values.
///
/// [standardCard] and [elevatedCard] match shadows already in production
/// use (see call sites migrated onto them). [popupMenu] and [modalSheet]
/// are provided to complete the requested set of four categories for
/// future use, but are intentionally not applied anywhere yet: today's
/// popup menu and bottom sheet rely on Flutter's built-in `elevation`
/// rendering, not a custom `BoxShadow`, and swapping that mechanism is a
/// visual-rendering change outside this task's low-risk scope.
class AppShadows {
  AppShadows._();

  /// Subtle shadow for a standard white card sitting directly on the page
  /// background (e.g. the Home "Check Availability" card, the Home "Last
  /// Payment" card).
  static const List<BoxShadow> standardCard = [
    BoxShadow(color: Color(0x0D000000), blurRadius: 6, offset: Offset(0, 2)),
  ];

  /// Slightly more pronounced shadow for a card meant to read as more
  /// prominent/tappable (e.g. an Order list card).
  static const List<BoxShadow> elevatedCard = [
    BoxShadow(color: Color(0x0D000000), blurRadius: 8, offset: Offset(0, 2)),
  ];

  /// Reserved for a future popup/menu surface that adopts a custom shadow
  /// instead of Material's `elevation`. Not applied anywhere today.
  static const List<BoxShadow> popupMenu = [
    BoxShadow(color: Color(0x14000000), blurRadius: 12, offset: Offset(0, 4)),
  ];

  /// Reserved for a future modal/sheet surface that adopts a custom shadow
  /// instead of Material's `elevation`. Not applied anywhere today.
  static const List<BoxShadow> modalSheet = [
    BoxShadow(color: Color(0x1F000000), blurRadius: 16, offset: Offset(0, -4)),
  ];
}
