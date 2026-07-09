import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Frontend-only status filter for the Orders screen.
///
/// TODO: Replace with the real order status model/enum once the Orders
/// API and data layer are implemented; wire this filter to the actual
/// query/repository at that point.
enum OrderStatusFilter { all, active }

/// Minimal placeholder Orders list screen.
///
/// TODO: Replace with the real orders list backed by live data once the
/// Orders API/repository is implemented. This screen currently only
/// demonstrates that the [filter] is received and applied at the UI level.
class OrdersScreen extends StatelessWidget {
  const OrdersScreen({super.key, this.filter = OrderStatusFilter.all});

  final OrderStatusFilter filter;

  @override
  Widget build(BuildContext context) {
    final isActive = filter == OrderStatusFilter.active;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: AppColors.textNavy,
        elevation: 0,
        title: Text(isActive ? 'Active Orders' : 'Orders'),
      ),
      body: Center(
        child: Text(
          isActive
              ? 'Active orders list coming soon'
              : 'Orders list coming soon',
          style: const TextStyle(color: AppColors.grayText),
        ),
      ),
    );
  }
}
