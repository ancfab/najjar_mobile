import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// A small rounded pill showing an invoice's real
/// `BusinessCentralInvoiceLine.invoiceStatus` value (e.g. `"Paid"`) —
/// confirmed live 2026-09-03, present on Oman's real invoices page.
///
/// This app does not enumerate or claim to know every status value BC can
/// send: only the specific strings below get a color treatment, matched
/// case-insensitively; anything else — an unrecognized status, or `null` —
/// renders as a neutral gray pill showing the raw text (or nothing, if
/// `null`), never a guessed color implying paid/overdue/etc.
class InvoiceStatusPill extends StatelessWidget {
  const InvoiceStatusPill({super.key, required this.status});

  /// The raw `invoiceStatus` value, or `null` when the tenant didn't
  /// publish one for this row — this widget renders nothing at all in that
  /// case (see [build]), never a fabricated "Unknown" pill.
  final String? status;

  @override
  Widget build(BuildContext context) {
    final value = status;
    if (value == null || value.trim().isEmpty) return const SizedBox.shrink();

    final (Color bg, Color fg) = _colorsFor(value);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Text(
        value,
        style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: fg),
      ),
    );
  }

  /// Case-insensitive match against the handful of status words confirmed
  /// live so far. Falls through to a neutral gray for anything else.
  static (Color, Color) _colorsFor(String status) {
    switch (status.trim().toLowerCase()) {
      case 'paid':
      case 'completed':
      case 'closed':
        return (AppColors.mint, AppColors.darkTeal);
      case 'open':
      case 'pending':
      case 'unpaid':
        return (AppColors.warningYellow, AppColors.darkAmber);
      case 'overdue':
      case 'cancelled':
      case 'canceled':
        return (AppColors.stockOutBg, Colors.white);
      default:
        return (AppColors.background, AppColors.grayText);
    }
  }
}
