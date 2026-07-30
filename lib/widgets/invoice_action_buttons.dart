import 'package:flutter/material.dart';

import '../localization/translations.dart';
import '../theme/app_colors.dart';

/// Side-by-side Print / Download PDF action buttons for the Invoice Details
/// screen. Both labels can wrap to a second line instead of overflowing on
/// narrow devices.
class InvoiceActionButtons extends StatelessWidget {
  const InvoiceActionButtons({
    super.key,
    required this.onPrint,
    required this.onDownloadPdf,
    this.isPrinting = false,
    this.isDownloading = false,
  });

  /// Called when Print is tapped. See the Invoice Details screen's handler
  /// for how the invoice PDF is prepared and handed to the native print
  /// flow.
  final VoidCallback onPrint;

  /// Called when Download PDF is tapped. See the Invoice Details screen's
  /// handler for how the invoice PDF is prepared and handed to the native
  /// save/share flow.
  final VoidCallback onDownloadPdf;

  /// Whether the invoice PDF is currently being prepared for printing.
  /// Shows a spinner in place of the icon/label and disables both buttons
  /// so a second PDF preparation can't be triggered mid-flight.
  final bool isPrinting;

  /// Whether the invoice PDF is currently being prepared for download.
  /// Shows a spinner in place of the icon/label and disables both buttons
  /// so a second PDF preparation can't be triggered mid-flight.
  final bool isDownloading;

  bool get _isBusy => isPrinting || isDownloading;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: _buildPrintButton(context)),
        const SizedBox(width: 12),
        Expanded(child: _buildDownloadPdfButton(context)),
      ],
    );
  }

  Widget _buildPrintButton(BuildContext context) {
    return Material(
      key: const ValueKey('invoice-action-print-button'),
      color: Colors.white,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: _isBusy ? null : onPrint,
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.darkTeal),
            borderRadius: BorderRadius.circular(10),
          ),
          child: isPrinting
              ? const SizedBox(
                  key: ValueKey('invoice-action-print-loading'),
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: AppColors.darkTeal,
                  ),
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.print_outlined,
                      color: AppColors.darkTeal,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        context.t('invoiceWidgets.print'),
                        textAlign: TextAlign.center,
                        softWrap: true,
                        style: const TextStyle(
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

  Widget _buildDownloadPdfButton(BuildContext context) {
    return Material(
      key: const ValueKey('invoice-action-download-pdf-button'),
      color: AppColors.primaryNavy,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: _isBusy ? null : onDownloadPdf,
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: isDownloading
              ? const SizedBox(
                  key: ValueKey('invoice-action-download-pdf-loading'),
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: Colors.white,
                  ),
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.download_outlined,
                      color: Colors.white,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        context.t('invoiceWidgets.downloadPdf'),
                        textAlign: TextAlign.center,
                        softWrap: true,
                        style: const TextStyle(
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
