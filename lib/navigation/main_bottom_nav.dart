import 'package:flutter/material.dart';

import '../screens/edit_profile_screen.dart';
import '../screens/orders_screen.dart';
import '../screens/support_screen.dart';

/// Indexes for [CustomBottomNav]'s four destinations, in the order it
/// renders them (see `CustomBottomNav._items`) — shared so every screen
/// that shows the footer stays in sync with the tab order.
const int kMainNavIndexHome = 0;
const int kMainNavIndexOrders = 1;
const int kMainNavIndexSupport = 2;
const int kMainNavIndexProfile = 3;

/// Shared `CustomBottomNav` tap handler for the Orders and Support
/// screens — the two main root screens wired up to the footer here. (Home,
/// Account Balance, and Edit Profile already had their own established,
/// separately-tested tap handling before this file existed and are
/// intentionally left as-is.)
///
/// [ownTabIndex] is the tab this screen itself already *is* the
/// destination for — tapping it again is a no-op, so a duplicate instance
/// is never pushed. Every other tab first collapses the back stack down to
/// the app's single root (Home) — via `popUntil(isFirst)` — before pushing
/// its screen, so hopping between tabs any number of times, from any
/// depth, never leaves more than one extra screen on the stack.
void handleMainBottomNavTap(
  BuildContext context,
  int tappedIndex, {
  required int ownTabIndex,
}) {
  if (tappedIndex == ownTabIndex) return;
  final navigator = Navigator.of(context);
  navigator.popUntil((route) => route.isFirst);
  switch (tappedIndex) {
    case kMainNavIndexHome:
      break;
    case kMainNavIndexOrders:
      navigator.push(MaterialPageRoute(builder: (_) => const OrdersScreen()));
    case kMainNavIndexSupport:
      navigator.push(MaterialPageRoute(builder: (_) => const SupportScreen()));
    case kMainNavIndexProfile:
      navigator.push(MaterialPageRoute(builder: (_) => EditProfileScreen()));
  }
}
