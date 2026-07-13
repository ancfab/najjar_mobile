import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../utils/responsive.dart';

/// Frontend-only status filter for the Invoices screen.
///
/// TODO: The "overdue" business rule is not yet defined anywhere in the
/// app (no Invoice model, no due-date/status logic exists). Confirm with
/// backend/business whether "overdue" means a specific status field or a
/// due-date comparison, then wire this filter to the real data layer.
enum InvoiceStatusFilter { all, overdue }

/// Minimal placeholder Invoices list screen.
///
/// TODO: Replace with the real invoices list backed by live data once the
/// Invoices API/repository and the overdue business rule are implemented.
class InvoicesScreen extends StatelessWidget {
  const InvoicesScreen({super.key, this.filter = InvoiceStatusFilter.all});

  final InvoiceStatusFilter filter;

  @override
  Widget build(BuildContext context) {
    final isOverdue = filter == InvoiceStatusFilter.overdue;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: AppColors.textNavy,
        elevation: 0,
        title: Text(isOverdue ? 'Overdue Invoices' : 'Invoices'),
      ),
      body: SafeArea(
        child: CenteredScrollable(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: Text(
              isOverdue
                  ? 'Overdue invoices list coming soon'
                  : 'Invoices list coming soon',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.grayText),
            ),
          ),
        ),
      ),
    );
  }
}
