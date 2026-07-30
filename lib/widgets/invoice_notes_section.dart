import 'package:flutter/material.dart';

import '../localization/translations.dart';
import '../theme/app_colors.dart';

/// Bordered white card showing the invoice's "Internal Notes": a heading
/// followed by a single free-text note.
///
// TODO(product): Confirm whether invoice notes are client-visible or
// back-office-only. If confirmed as back-office-only, stop exposing this
// field in the mobile app and remove InvoiceNotesSection from
// InvoiceDetailsScreen.
///
/// Rendered as its own card in `InvoiceDetailsScreen`, after the Logistics
/// card, matching `PaymentTimeline`/`InvoiceLogisticsStatusCard`'s outer card
/// styling (white background, border radius, subtle grey border, no shadow)
/// so all of the screen's cards read as one visual system.
///
/// Reusable: takes the note text through the constructor rather than reading
/// invoice data directly, matching `PaymentTimeline`'s convention. Renders
/// nothing when [note] is null or empty.
class InvoiceNotesSection extends StatelessWidget {
  const InvoiceNotesSection({super.key, required this.note});

  /// The note text to display, or null/empty to render nothing.
  final String? note;

  /// Outer card padding, matching `PaymentTimeline`/
  /// `InvoiceLogisticsStatusCard`'s.
  static const double _cardPadding = 28;

  @override
  Widget build(BuildContext context) {
    final trimmedNote = note?.trim();
    if (trimmedNote == null || trimmedNote.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      key: const ValueKey('invoice-notes-card'),
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
            context.t('invoiceWidgets.internalNotes'),
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: AppColors.textNavy,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            key: const ValueKey('invoice-notes-content'),
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.border),
            ),
            child: Text(
              trimmedNote,
              style: const TextStyle(fontSize: 13.5, color: AppColors.grayText),
            ),
          ),
        ],
      ),
    );
  }
}
