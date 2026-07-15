import 'package:flutter/material.dart';

import '../data/mock_user.dart';
import '../models/invoice.dart';
import '../services/mock_invoice_service.dart';
import '../theme/app_colors.dart';
import '../utils/responsive.dart';
import '../widgets/invoice_action_buttons.dart';
import '../widgets/invoice_breadcrumb.dart';
import '../widgets/invoice_info_card.dart';
import 'invoices_screen.dart';
import 'profile_screen.dart';

/// Invoice Details screen: breadcrumb + title, Print/Download PDF actions,
/// and the invoice information card (status/number/issued date, Billed To,
/// Due Date, Payment Method).
///
/// This is only the first section of the Invoice Details screen — later
/// tasks will add invoice line items, totals, notes, payment history, and a
/// footer once their screenshots/scope are provided.
///
/// TODO: Replace mock invoice fetching with the real Invoice Details API
/// once the endpoint is confirmed. All fetching on this screen is
/// mock/frontend-only until then.
class InvoiceDetailsScreen extends StatefulWidget {
  const InvoiceDetailsScreen({
    super.key,
    required this.invoiceNumber,
    MockInvoiceService? invoiceService,
  }) : invoiceService = invoiceService ?? const MockInvoiceService();

  /// [Invoice.invoiceNumber] of the invoice to load (e.g. "#INV-8821").
  final String invoiceNumber;

  /// Invoice query service/repository boundary. Defaults to the mock
  /// implementation; overridable so tests can inject a fake.
  final MockInvoiceService invoiceService;

  @override
  State<InvoiceDetailsScreen> createState() => _InvoiceDetailsScreenState();
}

class _InvoiceDetailsScreenState extends State<InvoiceDetailsScreen> {
  late final MockInvoiceService _invoiceService = widget.invoiceService;

  Invoice? _invoice;
  bool _isLoading = true;
  String? _error;

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
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const ProfileScreen(userName: kCurrentUserName),
      ),
    );
  }

  /// Handles the Print button tap.
  ///
  /// No invoice printing integration exists yet anywhere in this app, so
  /// this shows a safe placeholder message instead of invoking a printer.
  ///
  /// TODO: Wire up real invoice printing once a printing package (e.g.
  /// `printing`) and the invoice's print-ready layout/PDF source are
  /// confirmed with product/backend.
  void _printInvoice() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Invoice printing is not available yet.')),
    );
  }

  /// Handles the Download PDF button tap.
  ///
  /// No PDF generation/download integration exists yet anywhere in this
  /// app, so this shows a safe placeholder message instead of fetching or
  /// generating a fake file.
  ///
  /// TODO: Wire up real invoice PDF download once the backend/API team
  /// confirms the PDF source (generated client-side vs. a backend endpoint
  /// returning a file/URL) and the required file-saving permissions/
  /// package (e.g. `path_provider`).
  void _downloadInvoicePdf() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Invoice PDF download is not available yet.'),
      ),
    );
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
            child: const CircleAvatar(
              radius: 16,
              backgroundColor: AppColors.background,
              child: Icon(Icons.person, color: AppColors.grayText, size: 18),
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
            ),
            const SizedBox(height: 16),
            InvoiceInfoCard(invoice: invoice, onEmailTap: _emailBilledContact),
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
