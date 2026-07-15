import 'package:flutter/material.dart';

import '../models/invoice.dart';
import '../theme/app_colors.dart';
import '../utils/date_time_format.dart';
import 'invoice_info_section.dart';

/// Bordered white card showing an invoice's Logistics Status fields: STATUS
/// and EST. DELIVERY. Rendered as its own card in [InvoiceDetailsScreen],
/// separate from and after [InvoiceInfoCard] — it is not part of, and must
/// not be confused with, the invoice's payment [InvoiceStatus]/PAID badge.
///
/// Matches [InvoiceInfoCard]'s container styling (white background, border
/// radius, subtle grey border, no shadow) so the two cards read as one
/// visual system.
///
/// Reusable: takes the logistics info through the constructor rather than
/// reading invoice data directly, matching [PaymentTimeline]'s convention.
/// Renders nothing when [logistics] is null or has no fields set. A missing
/// individual field (status or delivery date) is omitted entirely — label,
/// value, and spacing — rather than shown with a placeholder like "—" or
/// "N/A", since a blank field isn't a confirmed real-world case yet.
class InvoiceLogisticsStatusCard extends StatelessWidget {
  const InvoiceLogisticsStatusCard({super.key, required this.logistics});

  final InvoiceLogisticsInfo? logistics;

  /// Card content width (available width inside the card's padding) below
  /// which STATUS and EST. DELIVERY stack vertically instead of sitting
  /// side-by-side, so long status text or a large system text scale never
  /// overflows a narrow phone width.
  static const double _stackedLayoutBreakpoint = 260;

  @override
  Widget build(BuildContext context) {
    final info = logistics;
    final statusLabel = info?.statusLabel?.trim();
    final estimatedDeliveryDate = info?.estimatedDeliveryDate;
    final hasStatus = statusLabel != null && statusLabel.isNotEmpty;
    final hasDelivery = estimatedDeliveryDate != null;
    if (!hasStatus && !hasDelivery) return const SizedBox.shrink();

    final statusField = hasStatus
        ? InvoiceInfoSection(
            label: 'STATUS',
            child: _ValueText(statusLabel, key: const ValueKey('invoice-logistics-status')),
          )
        : null;
    final deliveryField = hasDelivery
        ? InvoiceInfoSection(
            label: 'EST. DELIVERY',
            child: _ValueText(
              formatDateOnly(estimatedDeliveryDate),
              key: const ValueKey('invoice-logistics-est-delivery'),
            ),
          )
        : null;

    return Container(
      key: const ValueKey('invoice-logistics-status-card'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Logistics Status',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: AppColors.textNavy,
            ),
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              // Only worth a two-column layout when there are two fields to
              // place side by side; a lone field just renders as-is either
              // way.
              final canFitTwoColumns =
                  statusField != null &&
                  deliveryField != null &&
                  constraints.maxWidth >= _stackedLayoutBreakpoint;

              if (canFitTwoColumns) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: statusField),
                    const SizedBox(width: 12),
                    Expanded(child: deliveryField),
                  ],
                );
              }

              final fields = [?statusField, ?deliveryField];
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < fields.length; i++) ...[
                    if (i > 0) const SizedBox(height: 16),
                    fields[i],
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _ValueText extends StatelessWidget {
  const _ValueText(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w700,
        color: AppColors.textNavy,
      ),
    );
  }
}
