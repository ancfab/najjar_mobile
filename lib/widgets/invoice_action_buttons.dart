import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Side-by-side Print / Download PDF action buttons for the Invoice Details
/// screen. Both labels can wrap to a second line instead of overflowing on
/// narrow devices.
class InvoiceActionButtons extends StatelessWidget {
  const InvoiceActionButtons({
    super.key,
    required this.onPrint,
    required this.onDownloadPdf,
  });

  /// Called when Print is tapped. See the Invoice Details screen's handler
  /// for the current placeholder-vs-real-printing behavior.
  final VoidCallback onPrint;

  /// Called when Download PDF is tapped. See the Invoice Details screen's
  /// handler for the current placeholder-vs-real-download behavior.
  final VoidCallback onDownloadPdf;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: _buildPrintButton()),
        const SizedBox(width: 12),
        Expanded(child: _buildDownloadPdfButton()),
      ],
    );
  }

  Widget _buildPrintButton() {
    return Material(
      key: const ValueKey('invoice-action-print-button'),
      color: Colors.white,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onPrint,
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.darkTeal),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.print_outlined, color: AppColors.darkTeal, size: 18),
              SizedBox(width: 8),
              Flexible(
                child: Text(
                  'Print',
                  textAlign: TextAlign.center,
                  softWrap: true,
                  style: TextStyle(
                    color: AppColors.darkTeal,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDownloadPdfButton() {
    return Material(
      key: const ValueKey('invoice-action-download-pdf-button'),
      color: AppColors.primaryNavy,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onDownloadPdf,
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.download_outlined, color: Colors.white, size: 18),
              SizedBox(width: 8),
              Flexible(
                child: Text(
                  'Download PDF',
                  textAlign: TextAlign.center,
                  softWrap: true,
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
