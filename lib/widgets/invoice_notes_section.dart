import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// "Internal Notes" section: a heading followed by a single free-text note
/// about the invoice.
///
// TODO(product): Confirm whether invoice notes are client-visible or
// back-office-only. If confirmed as back-office-only, stop exposing this
// field in the mobile app and remove InvoiceNotesSection from InvoiceInfoCard.
///
/// Reusable: takes the note text through the constructor rather than reading
/// invoice data directly, matching [PaymentTimeline]'s convention. Renders
/// nothing when [note] is null or empty.
class InvoiceNotesSection extends StatelessWidget {
  const InvoiceNotesSection({super.key, required this.note});

  /// The note text to display, or null/empty to render nothing.
  final String? note;

  @override
  Widget build(BuildContext context) {
    final trimmedNote = note?.trim();
    if (trimmedNote == null || trimmedNote.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Internal Notes',
          style: TextStyle(
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
    );
  }
}
