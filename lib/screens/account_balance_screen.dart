import 'package:flutter/material.dart';

import '../data/mock_user.dart';
import '../models/account_balance_summary.dart';
import '../models/account_statement_data.dart';
import '../models/account_transaction.dart';
import '../models/balance_history_point.dart';
import '../models/balance_history_range.dart';
import '../models/credit_utilization_data.dart';
import '../services/account_balance_service.dart';
import '../services/account_statement_exporter.dart';
import '../services/current_user_avatar_controller.dart';
import '../theme/app_colors.dart';
import '../utils/responsive.dart';
import '../utils/user_initials.dart';
import '../widgets/account_balance_hero_card.dart';
import '../widgets/avatar_initials_badge.dart';
import '../widgets/balance_history_card.dart';
import '../widgets/credit_utilization_card.dart';
import '../widgets/custom_bottom_nav.dart';
import '../widgets/quick_history_card.dart';
import 'account_transaction_details_screen.dart';
import 'edit_profile_screen.dart';
import 'orders_screen.dart';
import 'support_screen.dart';

// Bottom tab bar indexes, matching HomeScreen's. Account Balance itself
// isn't one of the four tabs — it's a drill-down reached from the Home
// balance card — so Home is kept as the selected tab, the natural "parent"
// section to return to.
const int _navIndexHome = 0;
const int _navIndexOrders = 1;
const int _navIndexSupport = 2;
const int _navIndexProfile = 3;

/// Account Balance screen: global balance hero card, credit utilization, a
/// Balance History chart with a 30-day/90-day/1-year range selector, and a
/// Quick History list of recent transactions.
///
/// TODO(api): Replace mock account-balance summary and credit-utilization
/// data after the backend endpoint and response contract are confirmed.
class AccountBalanceScreen extends StatefulWidget {
  const AccountBalanceScreen({
    super.key,
    AccountBalanceService? service,
    AccountStatementExporter? exporter,
    this.avatarController,
  }) : service = service ?? const MockAccountBalanceService(),
       exporter = exporter ?? const LocalAccountStatementPdfExporter();

  /// Account balance data seam. Defaults to the mock implementation;
  /// overridable so tests can inject a fake.
  final AccountBalanceService service;

  /// Export PDF seam: generates the account statement PDF and hands it to
  /// the native share/save/print flow. Defaults to on-device generation;
  /// overridable so tests can inject a fake instead of invoking the real
  /// platform plugin.
  final AccountStatementExporter exporter;

  /// Shared current-user avatar state. Defaults (lazily, in State) to the
  /// app-wide [currentUserAvatarController] singleton; overridable so tests
  /// can inject a fresh instance instead of sharing that mutable singleton
  /// across test cases.
  final CurrentUserAvatarController? avatarController;

  @override
  State<AccountBalanceScreen> createState() => _AccountBalanceScreenState();
}

class _AccountBalanceScreenState extends State<AccountBalanceScreen> {
  late final AccountBalanceService _service = widget.service;
  late final AccountStatementExporter _exporter = widget.exporter;
  late final CurrentUserAvatarController _avatarController =
      widget.avatarController ?? currentUserAvatarController;

  AccountBalanceSummary? _summary;
  CreditUtilizationData? _creditUtilization;
  List<AccountTransaction> _quickHistory = const [];
  bool _isLoading = true;
  String? _error;

  BalanceHistoryRange _selectedRange = BalanceHistoryRange.thirtyDays;
  List<BalanceHistoryPoint> _historyPoints = const [];
  bool _isHistoryLoading = true;

  /// Whether the account statement PDF is currently being generated and
  /// handed to the native share sheet, so the Export PDF button can show a
  /// loading state and reject a second tap until this resolves.
  bool _isExportingPdf = false;

  @override
  void initState() {
    super.initState();
    _loadSummary();
    _loadHistory(_selectedRange);
  }

  Future<void> _loadSummary() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final summary = await _service.fetchSummary();
      final utilization = await _service.fetchCreditUtilization();
      final quickHistory = await _service.fetchQuickHistory();
      if (!mounted) return;
      setState(() {
        _summary = summary;
        _creditUtilization = utilization;
        _quickHistory = quickHistory;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Unable to load account balance.';
        _isLoading = false;
      });
    }
  }

  Future<void> _retryLoad() async {
    await _loadSummary();
  }

  Future<void> _loadHistory(BalanceHistoryRange range) async {
    setState(() => _isHistoryLoading = true);
    try {
      final points = await _service.fetchBalanceHistory(range);
      if (!mounted) return;
      setState(() {
        _historyPoints = points;
        _isHistoryLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isHistoryLoading = false);
    }
  }

  void _handleRangeChanged(BalanceHistoryRange range) {
    if (range == _selectedRange) return;
    setState(() => _selectedRange = range);
    _loadHistory(range);
  }

  void _openProfile() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => EditProfileScreen()));
  }

  // Handles bottom tab bar taps. Home returns to the screen this was pushed
  // from (matching the menu/back button); Orders/Support/Profile push their
  // screens the same way HomeScreen's bottom nav does.
  void _handleBottomNavTap(int tabIndex) {
    switch (tabIndex) {
      case _navIndexHome:
        Navigator.of(context).maybePop();
        break;
      case _navIndexOrders:
        Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const OrdersScreen()));
        break;
      case _navIndexSupport:
        Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const SupportScreen()));
        break;
      case _navIndexProfile:
        Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => EditProfileScreen()));
        break;
    }
  }

  /// Handles the Export PDF tap: generates an account statement PDF from
  /// currently available screen data and opens the native share/save/print
  /// sheet. Guards against duplicate taps while a generation is in flight
  /// and always restores the button afterwards, whether export succeeds or
  /// throws.
  Future<void> _exportPdf() async {
    if (_isExportingPdf) return;
    final summary = _summary;
    final utilization = _creditUtilization;
    if (summary == null || utilization == null) return;

    setState(() => _isExportingPdf = true);
    try {
      await _exporter.export(
        AccountStatementData(
          summary: summary,
          creditUtilization: utilization,
          selectedRange: _selectedRange,
          quickHistory: _quickHistory,
          generatedAt: DateTime.now(),
        ),
      );
    } catch (error) {
      debugPrint('Account statement export failed: $error');
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text(
              'Could not generate the account statement. Please try again.',
            ),
          ),
        );
    } finally {
      if (mounted) setState(() => _isExportingPdf = false);
    }
  }

  void _openTransactionDetails(AccountTransaction transaction) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            AccountTransactionDetailsScreen(transaction: transaction),
      ),
    );
  }

  // No full transaction-history screen exists yet anywhere in the app, so
  // "See all" shows a safe placeholder instead of inventing one.
  //
  // TODO(scope): Replace this placeholder when the full transaction-history
  // screen and route are confirmed as part of the project scope.
  void _openFullTransactionHistory() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Full transaction history is not available yet.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: _buildAppBar(),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(child: _buildBody()),
            CustomBottomNav(
              currentIndex: _navIndexHome,
              onTap: _handleBottomNavTap,
            ),
          ],
        ),
      ),
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
        key: const ValueKey('account-balance-menu-button'),
        icon: const Icon(Icons.menu_rounded),
        tooltip: 'Back',
        // No navigation drawer/menu content is defined yet for this screen,
        // so the menu affordance falls back to simple back navigation,
        // matching InvoiceDetailsScreen's convention.
        onPressed: () => Navigator.of(context).maybePop(),
      ),
      title: ClampedTextScale(child: _buildBrandTitle()),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 16),
          child: ListenableBuilder(
            listenable: _avatarController,
            builder: (context, _) => AvatarInitialsBadge(
              key: const ValueKey('account-balance-avatar'),
              initials: userInitials(kCurrentUserName),
              image: _avatarController.imageProvider,
              onTap: _openProfile,
            ),
          ),
        ),
      ],
    );
  }

  // "Indigo Loom" brand mark, matching the IL badge convention used on the
  // Invoice Details screen's header.
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
        key: ValueKey('account-balance-loading'),
        child: CircularProgressIndicator(),
      );
    }
    if (_error != null) {
      return _buildErrorState();
    }
    final summary = _summary;
    final utilization = _creditUtilization;
    if (summary == null || utilization == null) return const SizedBox.shrink();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: ResponsiveMaxWidth(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AccountBalanceHeroCard(
              balance: summary.currentBalance,
              percentChange: summary.percentChangeFromLastMonth,
              changePeriodLabel: summary.changePeriodLabel,
              onExportPdf: _exportPdf,
              isExporting: _isExportingPdf,
            ),
            const SizedBox(height: 16),
            CreditUtilizationCard(data: utilization),
            const SizedBox(height: 16),
            BalanceHistoryCard(
              points: _historyPoints,
              selectedRange: _selectedRange,
              onRangeChanged: _handleRangeChanged,
              isLoading: _isHistoryLoading,
            ),
            const SizedBox(height: 16),
            QuickHistoryCard(
              transactions: _quickHistory,
              onTransactionTap: _openTransactionDetails,
              onSeeAll: _openFullTransactionHistory,
            ),
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
              _error ?? 'Unable to load account balance.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.grayText),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _retryLoad,
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
