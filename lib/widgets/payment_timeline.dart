import 'package:flutter/material.dart';

import '../models/invoice.dart';
import '../theme/app_colors.dart';
import '../utils/date_time_format.dart';

/// Bordered white card showing the invoice's "Payment Timeline": a
/// left-aligned heading followed by a vertical stack of completed
/// [InvoiceTimelineEvent]s, connected by a thin grey line between (but never
/// below) markers.
///
/// Rendered as its own card in [InvoiceDetailsScreen], separate from and
/// after [InvoiceInfoCard], matching that card's white background/border/
/// radius so the two read as one visual system.
///
/// Reusable: takes its event list through the constructor rather than
/// reading invoice data directly, so it isn't tied to the Invoice Details
/// screen. Renders nothing when [events] is empty.
class PaymentTimeline extends StatelessWidget {
  const PaymentTimeline({super.key, required this.events});

  /// Events in the order they should be displayed (newest first for the
  /// Invoice Details screen's mock data, but this widget just renders
  /// whatever order it's given).
  final List<InvoiceTimelineEvent> events;

  /// Internal card padding, larger than [InvoiceInfoCard]'s to match the
  /// more spacious card styling used for this and the Logistics card.
  static const double _cardPadding = 28;

  @override
  Widget build(BuildContext context) {
    if (events.isEmpty) return const SizedBox.shrink();

    return Container(
      key: const ValueKey('payment-timeline-card'),
      padding: const EdgeInsets.all(_cardPadding),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Payment Timeline',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: AppColors.textNavy,
            ),
          ),
          const SizedBox(height: 16),
          for (var i = 0; i < events.length; i++)
            _PaymentTimelineItem(
              event: events[i],
              isLast: i == events.length - 1,
            ),
        ],
      ),
    );
  }
}

/// One marker+connector / title+timestamp row within [PaymentTimeline].
class _PaymentTimelineItem extends StatelessWidget {
  const _PaymentTimelineItem({required this.event, required this.isLast});

  final InvoiceTimelineEvent event;
  final bool isLast;

  static const double _markerSize = 32;

  @override
  Widget build(BuildContext context) {
    // IntrinsicHeight + a stretched Row lets the connector column match the
    // height of the text content beside it, so the line reaches exactly
    // down to the next marker (rows are stacked with no gap between them)
    // without ever extending past the last marker.
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ExcludeSemantics(
            child: SizedBox(
              width: _markerSize,
              child: Column(
                children: [
                  Container(
                    key: const ValueKey('payment-timeline-marker'),
                    width: _markerSize,
                    height: _markerSize,
                    decoration: BoxDecoration(
                      color: AppColors.darkTeal,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    alignment: Alignment.center,
                    child: const Icon(
                      Icons.check,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                  if (!isLast)
                    Expanded(
                      child: Center(
                        child: Container(
                          key: const ValueKey('payment-timeline-connector'),
                          width: 2,
                          color: AppColors.border,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    event.title,
                    style: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textNavy,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    formatEventTimestamp(event.occurredAt),
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: AppColors.grayText,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
