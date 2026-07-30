import 'package:flutter/material.dart';

import '../localization/translations.dart';
import '../models/invoice.dart';
import '../theme/app_colors.dart';
import '../utils/date_time_format.dart';

/// Bordered white card showing an invoice's Logistics fields: STATUS and
/// EST. DELIVERY, each in its own full-width, stacked field box. Rendered as
/// its own card in [InvoiceDetailsScreen], immediately after the Payment
/// Timeline card — it is not part of, and must not be confused with, the
/// invoice's payment [InvoiceStatus]/PAID badge.
///
/// Matches [InvoiceInfoCard]/`PaymentTimeline`'s outer card styling (white
/// background, border radius, subtle grey border, no shadow) so all of the
/// screen's cards read as one visual system.
///
/// Reusable: takes the logistics info through the constructor rather than
/// reading invoice data directly, matching `PaymentTimeline`'s convention.
/// Renders nothing when [logistics] is null or has no fields set. A missing
/// individual field (status or delivery date) is omitted entirely — box,
/// label, value, and spacing — rather than shown with a placeholder like
/// "—" or "N/A", since a blank field isn't a confirmed real-world case yet.
class InvoiceLogisticsStatusCard extends StatelessWidget {
  const InvoiceLogisticsStatusCard({super.key, required this.logistics});

  final InvoiceLogisticsInfo? logistics;

  /// Outer card padding, matching `PaymentTimeline`'s.
  static const double _cardPadding = 28;

  /// Inner field-box padding.
  static const double _fieldBoxPadding = 20;

  /// Vertical gap between the STATUS and EST. DELIVERY field boxes.
  static const double _fieldBoxSpacing = 18;

  @override
  Widget build(BuildContext context) {
    final info = logistics;
    final statusLabel = info?.statusLabel?.trim();
    final estimatedDeliveryDate = info?.estimatedDeliveryDate;
    final hasStatus = statusLabel != null && statusLabel.isNotEmpty;
    final hasDelivery = estimatedDeliveryDate != null;
    if (!hasStatus && !hasDelivery) return const SizedBox.shrink();

    return Container(
      key: const ValueKey('invoice-logistics-card'),
      padding: const EdgeInsets.all(_cardPadding),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            context.t('invoiceWidgets.logisticsHeading'),
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: AppColors.textNavy,
            ),
          ),
          const SizedBox(height: 16),
          if (hasStatus) _StatusBox(statusLabel: statusLabel),
          if (hasStatus && hasDelivery)
            const SizedBox(height: _fieldBoxSpacing),
          if (hasDelivery)
            _DeliveryBox(estimatedDeliveryDate: estimatedDeliveryDate),
        ],
      ),
    );
  }
}

/// Uppercase, dark-grey, semibold field label shared by [_StatusBox] and
/// [_DeliveryBox] (e.g. "STATUS", "EST. DELIVERY").
class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.0,
        color: AppColors.grayText,
      ),
    );
  }
}

/// Light-grey, full-width, bordered field box shared by [_StatusBox] and
/// [_DeliveryBox].
class _FieldBox extends StatelessWidget {
  const _FieldBox({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(
        InvoiceLogisticsStatusCard._fieldBoxPadding,
      ),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.border),
      ),
      child: child,
    );
  }
}

/// STATUS field box: label, then a small teal dot beside the (bold, teal)
/// status value. Deliberately not a colored pill/badge — see
/// [InvoiceLogisticsInfo] for why the full status list/styling isn't
/// confirmed yet, and this must stay visually distinct from the invoice's
/// payment PAID badge.
class _StatusBox extends StatelessWidget {
  const _StatusBox({required this.statusLabel});

  final String statusLabel;

  @override
  Widget build(BuildContext context) {
    return _FieldBox(
      key: const ValueKey('invoice-logistics-status-box'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _FieldLabel(context.t('invoiceWidgets.status')),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                key: const ValueKey('invoice-logistics-status-dot'),
                width: 10,
                height: 10,
                decoration: const BoxDecoration(
                  color: AppColors.darkTeal,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  statusLabel,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.darkTeal,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// EST. DELIVERY field box: label, then the formatted delivery date below
/// it, bold and dark near-black.
class _DeliveryBox extends StatelessWidget {
  const _DeliveryBox({required this.estimatedDeliveryDate});

  final DateTime estimatedDeliveryDate;

  @override
  Widget build(BuildContext context) {
    return _FieldBox(
      key: const ValueKey('invoice-logistics-delivery-box'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _FieldLabel(context.t('invoiceWidgets.estDelivery')),
          const SizedBox(height: 10),
          Text(
            formatDateOnly(estimatedDeliveryDate),
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: Colors.black87,
            ),
          ),
        ],
      ),
    );
  }
}
