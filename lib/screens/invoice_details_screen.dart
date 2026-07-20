import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models/invoice.dart';
import '../services/current_user_avatar_controller.dart';
import '../services/invoice_document_actions.dart';
import '../services/invoice_pdf_service.dart';
import '../services/mock_invoice_service.dart';
import '../theme/app_colors.dart';
import '../utils/filename.dart';
import '../utils/responsive.dart';
import '../widgets/invoice_action_buttons.dart';
import '../widgets/invoice_breadcrumb.dart';
import '../widgets/invoice_info_card.dart';
import '../widgets/invoice_logistics_status_card.dart';
import '../widgets/invoice_notes_section.dart';
import '../widgets/payment_timeline.dart';
import 'edit_profile_screen.dart';
import 'invoices_screen.dart';

/// Invoice Details screen: breadcrumb + title, Print/Download PDF actions,
/// and the invoice information card (status/number/issued date, Billed To,
/// Due Date, Payment Method, line-items table, and Subtotal/Tax/Total
/// Amount summary).
///
/// These are only the first sections of the Invoice Details screen — later
/// tasks will add notes, payment history, and a footer once their
/// screenshots/scope are provided.
///
/// TODO: Replace mock invoice fetching with the real Invoice Details API
/// once the endpoint is confirmed. All fetching on this screen is
/// mock/frontend-only until then.
class InvoiceDetailsScreen extends StatefulWidget {
  const InvoiceDetailsScreen({
    super.key,
    required this.invoiceNumber,
    MockInvoiceService? invoiceService,
    InvoicePdfService? pdfService,
    InvoiceDocumentActions? documentActions,
    this.avatarController,
  }) : invoiceService = invoiceService ?? const MockInvoiceService(),
       pdfService = pdfService ?? const LocalInvoicePdfService(),
       documentActions =
           documentActions ?? const PrintingInvoiceDocumentActions();

  /// [Invoice.invoiceNumber] of the invoice to load (e.g. "#INV-8821").
  final String invoiceNumber;

  /// Invoice query service/repository boundary. Defaults to the mock
  /// implementation; overridable so tests can inject a fake.
  final MockInvoiceService invoiceService;

  /// Prepares the PDF bytes shared by Print and Download PDF. Defaults to
  /// on-device generation; overridable so tests can inject a fake.
  final InvoicePdfService pdfService;

  /// Hands prepared PDF bytes to the native print/save flows. Defaults to
  /// the real `printing`-plugin-backed implementation; overridable so
  /// tests can inject a fake instead of invoking the real platform plugin.
  final InvoiceDocumentActions documentActions;

  /// Shared current-user avatar state. Defaults (lazily, in State) to the
  /// app-wide [currentUserAvatarController] singleton; overridable so tests
  /// can inject a fresh instance instead of sharing that mutable singleton
  /// across test cases.
  final CurrentUserAvatarController? avatarController;

  @override
  State<InvoiceDetailsScreen> createState() => _InvoiceDetailsScreenState();
}

/// Which invoice PDF action is currently being prepared, if any. Only one
/// can be active at a time — see [_InvoiceDetailsScreenState._activePdfAction].
enum _InvoicePdfAction { print, download }

class _InvoiceDetailsScreenState extends State<InvoiceDetailsScreen> {
  late final MockInvoiceService _invoiceService = widget.invoiceService;
  late final InvoicePdfService _pdfService = widget.pdfService;
  late final InvoiceDocumentActions _documentActions = widget.documentActions;
  late final CurrentUserAvatarController _avatarController =
      widget.avatarController ?? currentUserAvatarController;

  Invoice? _invoice;
  bool _isLoading = true;
  String? _error;

  /// Non-null while an invoice PDF is being generated and handed to the
  /// native print/save flow, so both buttons can show a loading state and
  /// reject a second tap until this resolves.
  _InvoicePdfAction? _activePdfAction;

  @override
  void initState() {
    super.initState();
    _loadInvoice();
  }

  Future<void> _loadInvoice() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final invoice = await _invoiceService.fetchInvoice(widget.invoiceNumber);
      if (!mounted) return;
      setState(() {
        _invoice = invoice;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Unable to load invoice details.';
        _isLoading = false;
      });
    }
  }

  Future<void> _retryLoadInvoice() async {
    await _loadInvoice();
  }

  // Navigates to the Invoices list screen. No per-invoice entry point exists
  // there yet (it's still a placeholder list), so this simply opens it
  // rather than trying to pop back to a specific prior instance of it.
  void _openInvoices() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const InvoicesScreen()));
  }

  void _openProfile() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const EditProfileScreen()));
  }

  /// Handles the Print button tap: generates the invoice PDF (shared with
  /// Download PDF) and opens the native print dialog.
  Future<void> _printInvoice() async {
    await _runPdfAction(
      action: _InvoicePdfAction.print,
      perform: (bytes, filename) =>
          _documentActions.printPdf(bytes, filename),
      cancelledMessage: 'Printing was cancelled.',
      failureMessage: 'Unable to print the invoice. Please try again.',
    );
  }

  /// Handles the Download PDF button tap: generates the invoice PDF (shared
  /// with Print) and opens the native save/share sheet so the user can
  /// export it.
  Future<void> _downloadInvoicePdf() async {
    await _runPdfAction(
      action: _InvoicePdfAction.download,
      perform: (bytes, filename) => _documentActions.savePdf(bytes, filename),
      cancelledMessage: 'Download was cancelled.',
      failureMessage: 'Unable to prepare the invoice PDF. Please try again.',
    );
  }

  /// Shared Print/Download PDF flow: generates the invoice PDF once, hands
  /// it to [perform] (the native print or save flow), and manages the
  /// loading state/snackbar feedback both actions need identically.
  ///
  /// Guards against duplicate requests (an action already in flight is
  /// ignored) and always restores the buttons afterwards, whether [perform]
  /// succeeds, is cancelled by the user, or throws.
  Future<void> _runPdfAction({
    required _InvoicePdfAction action,
    required Future<bool> Function(Uint8List bytes, String filename) perform,
    required String cancelledMessage,
    required String failureMessage,
  }) async {
    final invoice = _invoice;
    if (invoice == null || _activePdfAction != null) return;

    setState(() => _activePdfAction = action);
    try {
      final bytes = await _pdfService.generate(invoice);
      final filename = invoicePdfFilename(invoice.invoiceNumber);
      final completed = await perform(bytes, filename);
      if (!mounted) return;
      if (!completed) {
        _showSnackBar(cancelledMessage);
      }
    } catch (error) {
      debugPrint('Invoice PDF action failed: $error');
      if (!mounted) return;
      _showSnackBar(failureMessage);
    } finally {
      if (mounted) setState(() => _activePdfAction = null);
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// Handles tapping the Billed To email link.
  ///
  /// No email-launching helper exists yet anywhere in this app (only
  /// `PhoneLauncher`/`WhatsAppLauncher` for `tel:`/WhatsApp deep links), so
  /// this shows a safe placeholder message instead of a fake `mailto:`
  /// launch.
  ///
  /// TODO: Add a `mailto:` email-launching helper (mirroring
  /// `PhoneLauncher`/`WhatsAppLauncher`, built on the existing
  /// `UrlLauncherClient`) once product/backend confirms the desired
  /// behavior.
  void _emailBilledContact() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Emailing the billing contact is not available yet.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: _buildAppBar(),
      body: SafeArea(top: false, child: _buildBody()),
    );
  }

  AppBar _buildAppBar() {
    return AppBar(
      backgroundColor: Colors.white,
      foregroundColor: AppColors.textNavy,
      elevation: 0,
      toolbarHeight: 68,
      titleSpacing: 0,
      leading: IconButton(
        key: const ValueKey('invoice-details-menu-button'),
        icon: const Icon(Icons.menu_rounded),
        tooltip: 'Back',
        // No navigation drawer/menu content is defined yet for this screen,
        // so the menu affordance falls back to simple back navigation.
        onPressed: () => Navigator.of(context).maybePop(),
      ),
      title: ClampedTextScale(child: _buildBrandTitle()),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 16),
          child: GestureDetector(
            key: const ValueKey('invoice-details-avatar'),
            onTap: _openProfile,
            child: ListenableBuilder(
              listenable: _avatarController,
              builder: (context, _) {
                final image = _avatarController.imageProvider;
                return CircleAvatar(
                  radius: 16,
                  backgroundColor: AppColors.background,
                  backgroundImage: image,
                  child: image == null
                      ? const Icon(
                          Icons.person,
                          color: AppColors.grayText,
                          size: 18,
                        )
                      : null,
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  // "Indigo Loom" brand mark shown in the header, matching the IL badge
  // convention used across the app's other screens.
  Widget _buildBrandTitle() {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: AppColors.primaryNavy,
            borderRadius: BorderRadius.circular(10),
          ),
          alignment: Alignment.center,
          child: const Text(
            'IL',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ),
        const SizedBox(width: 10),
        const Expanded(
          child: Text(
            'Indigo Loom',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppColors.textNavy,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        key: ValueKey('invoice-details-loading'),
        child: CircularProgressIndicator(),
      );
    }
    if (_error != null) {
      return _buildErrorState();
    }
    final invoice = _invoice;
    if (invoice == null) return const SizedBox.shrink();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: ResponsiveMaxWidth(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InvoiceBreadcrumb(
              invoiceNumber: invoice.invoiceNumber,
              onInvoicesTap: _openInvoices,
            ),
            const SizedBox(height: 12),
            const Text(
              'Invoice Details',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: AppColors.textNavy,
              ),
            ),
            const SizedBox(height: 16),
            InvoiceActionButtons(
              onPrint: _printInvoice,
              onDownloadPdf: _downloadInvoicePdf,
              isPrinting: _activePdfAction == _InvoicePdfAction.print,
              isDownloading: _activePdfAction == _InvoicePdfAction.download,
            ),
            const SizedBox(height: 16),
            InvoiceInfoCard(invoice: invoice, onEmailTap: _emailBilledContact),
            if (invoice.timelineEvents.isNotEmpty) ...[
              const SizedBox(height: 16),
              PaymentTimeline(events: invoice.timelineEvents),
            ],
            // TODO(product): Revisit this visibility rule when the confirmed
            // backend contract defines whether partial logistics information
            // should be shown.
            if (invoice.logisticsInfo != null) ...[
              const SizedBox(height: 16),
              InvoiceLogisticsStatusCard(logistics: invoice.logisticsInfo),
            ],
            // TODO(product): Confirm whether invoice notes are client-visible
            // or back-office-only. If confirmed as back-office-only, stop
            // exposing this field in the mobile app and remove
            // InvoiceNotesSection from InvoiceDetailsScreen.
            if (invoice.clientVisibleNote?.trim().isNotEmpty ?? false) ...[
              const SizedBox(height: 16),
              InvoiceNotesSection(note: invoice.clientVisibleNote),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              color: AppColors.dangerRed,
              size: 28,
            ),
            const SizedBox(height: 8),
            Text(
              _error ?? 'Unable to load invoice details.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.grayText),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _retryLoadInvoice,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryNavy,
                foregroundColor: Colors.white,
              ),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
