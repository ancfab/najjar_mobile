import 'package:flutter/material.dart';

import '../data/mock_user.dart';
import '../localization/translations.dart';
import '../models/account_statement_data.dart';
import '../models/account_transaction.dart';
import '../models/balance_history_point.dart';
import '../models/business_central/customer_details.dart';
import '../models/credit_utilization_data.dart';
import '../services/account_balance_service.dart';
import '../services/account_statement_exporter.dart';
import '../services/balance_history_data_source.dart';
import '../services/business_central_error_mapper.dart';
import '../services/current_user_avatar_controller.dart';
import '../services/ledger_entry_presentation_adapter.dart';
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

/// Quick History load state, tracked independently of the rest of the
/// screen's balance/credit/history data so a ledger failure never blanks
/// out those sections, and a 401 never shows any local error at all (the
/// centralized session coordinator is already navigating to Login by the
/// time [SessionExpiredException] reaches this screen — see
/// `_AccountBalanceScreenState._loadQuickHistory`).
enum _QuickHistoryState { loading, loaded, empty, error }

/// Balance History load state, tracked independently of Quick History and
/// the hero/credit summary for the same reason [_QuickHistoryState] is: a
/// ledger failure in one section must never blank out the others, and a 401
/// never shows any local error (see [_QuickHistoryState]'s doc comment).
enum _BalanceHistoryState { loading, loaded, empty, error }

/// Strips the time-of-day component so From/To comparisons and defaults are
/// always calendar-date-only — matches
/// `LedgerBalanceHistoryDataSource`'s own `_dateOnly` normalization.
DateTime _dateOnly(DateTime date) => DateTime(date.year, date.month, date.day);

/// Controlled, safe user-facing copy for a `BusinessCentralOutcome` — shared
/// by Quick History's and Balance History's error states so the two
/// ledger-backed sections never drift into different wording for the same
/// failure kind. The backend's raw `message` is never shown directly (see
/// `BusinessCentralOutcome`'s doc comments).
String _businessCentralOutcomeMessage(
  BuildContext context,
  BusinessCentralOutcome? outcome,
) {
  return switch (outcome) {
    BusinessCentralAccountNotLinked() => context.t(
      'accountBalance.errorAccountNotSetUp',
    ),
    BusinessCentralTemporarilyUnavailable() => context.t(
      'accountBalance.errorTemporarilyUnavailable',
    ),
    _ => context.t('accountBalance.errorGeneric'),
  };
}

// Bottom tab bar indexes, matching HomeScreen's. Account Balance itself
// isn't one of the four tabs — it's a drill-down reached from the Home
// balance card — so Home is kept as the selected tab, the natural "parent"
// section to return to.
const int _navIndexHome = 0;
const int _navIndexOrders = 1;
const int _navIndexSupport = 2;
const int _navIndexProfile = 3;

/// Account Balance screen: global balance hero card and Credit Utilization,
/// both backed by a single unfiltered Business Central customer-details
/// request (see `AccountBalanceService`/`CustomerDetailsService`); a
/// graph-only Balance History section (heading, From/To range, and the real
/// reconstructed-balance chart — no transaction list, see
/// `BalanceHistoryCard`'s doc comment) for a user-selected From/To range,
/// backed by real ledger entries filtered locally by `Posting_Date` (see
/// `LedgerBalanceHistoryDataSource`'s doc comment); and a live Quick History
/// list backed by the same ledger-entries endpoint (see
/// `LedgerQuickHistoryDataSource`) — Quick History, not Balance History, is
/// where individual ledger transactions are shown.
///
/// Displayed in [currencyCode] — the ledger-entries-derived `Currency_Code`
/// that Home's Current Balance card has *already* resolved (see
/// `CurrentBalanceAmount.currencyCode`/`computeCurrentBalance`), passed in
/// directly by the caller (`HomeScreen._openAccountBalance`) rather than
/// re-resolved here. This screen must never fetch ledger entries itself for
/// the hero/credit figures, derive currency from `AuthSession.country`, or
/// run its own multi-currency validation — `CurrentBalanceService` already
/// did that when Home loaded, and its result is simply reused. `customer-
/// details` itself exposes no currency field, so [currencyCode] is a
/// caller-supplied display-only annotation, never derived from that
/// response. Quick History's own rows keep each entry's own `Currency_Code`
/// individually (see `adaptLedgerEntryToAccountTransaction`) rather than
/// using [currencyCode].
///
/// The screen previously also showed a date-filtered "Balance by Period"
/// customer-details request. Live black-box testing on 2026-08-30 confirmed
/// that request returns identical figures for every range — only the
/// echoed `DateFilter` changed — so the backend does not actually scope
/// customer-details by date. Balance History is therefore never backed by
/// that endpoint; see [BalanceHistoryDataSource]'s doc comment for why it is
/// backed by locally-filtered ledger entries instead.
class AccountBalanceScreen extends StatefulWidget {
  AccountBalanceScreen({
    super.key,
    AccountBalanceService? service,
    AccountStatementExporter? exporter,
    this.avatarController,
    this.quickHistorySource,
    BalanceHistoryDataSource? balanceHistorySource,
    this.currencyCode,
  }) : service = service ?? LiveAccountBalanceService(),
       exporter = exporter ?? const LocalAccountStatementPdfExporter(),
       balanceHistorySource =
           balanceHistorySource ?? LedgerBalanceHistoryDataSource();

  /// Account balance data seam. Defaults to the live customer-details-backed
  /// implementation; overridable so tests can inject a fake.
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

  /// Quick History data seam. Defaults (lazily, in State) to
  /// [LedgerQuickHistoryDataSource] — the live Business Central
  /// ledger-entries endpoint; overridable so tests can inject a fake.
  final QuickHistoryDataSource? quickHistorySource;

  /// Balance History data seam. Defaults to [LedgerBalanceHistoryDataSource]
  /// — the live Business Central ledger-entries endpoint, filtered locally
  /// by `Posting_Date` (see that class's doc comment); overridable so tests
  /// can inject a fake.
  final BalanceHistoryDataSource balanceHistorySource;

  /// The display currency for the hero balance, Credit Utilization, and PDF
  /// export figures — `CurrentBalanceAmount.currencyCode` from Home's
  /// already-loaded Current Balance result, passed straight through by the
  /// caller. `null` when Home's Current Balance hasn't resolved a currency
  /// (still loading, errored, or every contributing ledger entry had a
  /// blank `Currency_Code`) — `formatCurrencyOrUnknown` then renders the
  /// existing "?" fallback, never a guessed code.
  final String? currencyCode;

  @override
  State<AccountBalanceScreen> createState() => _AccountBalanceScreenState();
}

class _AccountBalanceScreenState extends State<AccountBalanceScreen> {
  late final AccountBalanceService _service = widget.service;
  late final AccountStatementExporter _exporter = widget.exporter;
  late final CurrentUserAvatarController _avatarController =
      widget.avatarController ?? currentUserAvatarController;
  late final QuickHistoryDataSource _quickHistorySource =
      widget.quickHistorySource ?? LedgerQuickHistoryDataSource();
  late final BalanceHistoryDataSource _balanceHistorySource =
      widget.balanceHistorySource;

  CustomerDetails? _accountSummary;
  bool _isLoading = true;
  String? _error;

  _QuickHistoryState _quickHistoryState = _QuickHistoryState.loading;
  List<AccountTransaction> _quickHistory = const [];

  /// Set only when [_quickHistoryState] is [_QuickHistoryState.error] from a
  /// [BusinessCentralFailureException] — `null` for a generic/unexpected
  /// failure, which gets the same neutral retry copy as every outcome other
  /// than "account not linked"/"temporarily unavailable".
  BusinessCentralOutcome? _quickHistoryOutcome;

  /// The selected Balance History range's To date, defaulting to today, and
  /// From date, defaulting to the 30 days (inclusive) ending on [_historyTo]
  /// — a sensible default in the absence of any other product rule, and the
  /// same effective span the retired 30-day preset covered.
  late DateTime _historyTo = _dateOnly(DateTime.now());
  late DateTime _historyFrom = _historyTo.subtract(const Duration(days: 29));

  _BalanceHistoryState _historyState = _BalanceHistoryState.loading;
  List<BalanceHistoryPoint> _historyPoints = const [];
  bool _historyHasMultipleCurrencies = false;

  /// Set only when [_historyState] is [_BalanceHistoryState.error] from a
  /// [BusinessCentralFailureException] — `null` for a generic/unexpected
  /// failure, same convention as [_quickHistoryOutcome].
  BusinessCentralOutcome? _historyOutcome;

  /// Whether the account statement PDF is currently being generated and
  /// handed to the native share sheet, so the Export PDF button can show a
  /// loading state and reject a second tap until this resolves.
  bool _isExportingPdf = false;

  @override
  void initState() {
    super.initState();
    _loadSummary();
    _loadHistory();
    _loadQuickHistory();
  }

  Future<void> _loadSummary() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final summary = await _service.fetchAccountSummary();
      if (!mounted) return;
      setState(() {
        _accountSummary = summary;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = context.t('accountBalance.unableToLoad');
        _isLoading = false;
      });
    }
  }

  Future<void> _retryLoad() async {
    await _loadSummary();
  }

  /// Loads Quick History independently of [_loadSummary]/[_loadHistory] so
  /// a ledger-entries failure can never blank out the balance/credit/
  /// history sections, and so a runtime HTTP 401 — already fully handled by
  /// the centralized `SessionExpiryCoordinator` by the time
  /// [SessionExpiredException] reaches this catch — never shows any local
  /// error state or toast here.
  Future<void> _loadQuickHistory() async {
    setState(() {
      _quickHistoryState = _QuickHistoryState.loading;
      _quickHistoryOutcome = null;
    });
    try {
      final rows = await _quickHistorySource.fetchQuickHistoryRows();
      if (!mounted) return;
      setState(() {
        _quickHistory = rows;
        _quickHistoryState = rows.isEmpty
            ? _QuickHistoryState.empty
            : _QuickHistoryState.loaded;
      });
    } on SessionExpiredException {
      // The centralized session coordinator has already cleared the
      // session and is navigating to Login — show nothing here.
    } on BusinessCentralFailureException catch (error) {
      if (!mounted) return;
      setState(() {
        _quickHistoryOutcome = error.outcome;
        _quickHistoryState = _QuickHistoryState.error;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _quickHistoryOutcome = null;
        _quickHistoryState = _QuickHistoryState.error;
      });
    }
  }

  /// Loads Balance History for the currently selected [_historyFrom]/
  /// [_historyTo] range, independently of [_loadSummary]/[_loadQuickHistory]
  /// for the same reason [_loadQuickHistory] is independent of them — see
  /// that method's doc comment.
  Future<void> _loadHistory() async {
    setState(() {
      _historyState = _BalanceHistoryState.loading;
      _historyOutcome = null;
    });
    try {
      final data = await _balanceHistorySource.fetchBalanceHistory(
        from: _historyFrom,
        to: _historyTo,
      );
      if (!mounted) return;
      setState(() {
        _historyPoints = data.points;
        _historyHasMultipleCurrencies = data.hasMultipleCurrencies;
        _historyState = data.points.isEmpty && !data.hasMultipleCurrencies
            ? _BalanceHistoryState.empty
            : _BalanceHistoryState.loaded;
      });
    } on SessionExpiredException {
      // The centralized session coordinator has already cleared the
      // session and is navigating to Login — show nothing here.
    } on BusinessCentralFailureException catch (error) {
      if (!mounted) return;
      setState(() {
        _historyOutcome = error.outcome;
        _historyState = _BalanceHistoryState.error;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _historyOutcome = null;
        _historyState = _BalanceHistoryState.error;
      });
    }
  }

  /// Applies a newly picked From date: normalized to date-only, and never
  /// left after the current To date (defensive — `BalanceHistoryDateRangePicker`
  /// already constrains its From picker's `lastDate` to [_historyTo], but
  /// this guarantees the invariant regardless of picker platform behavior).
  void _handleFromChanged(DateTime picked) {
    final normalized = _dateOnly(picked);
    if (normalized == _historyFrom) return;
    setState(() {
      _historyFrom = normalized;
      if (_historyTo.isBefore(_historyFrom)) _historyTo = _historyFrom;
    });
    _loadHistory();
  }

  /// Applies a newly picked To date: normalized to date-only, and never left
  /// before the current From date (defensive — see [_handleFromChanged]).
  void _handleToChanged(DateTime picked) {
    final normalized = _dateOnly(picked);
    if (normalized == _historyTo) return;
    setState(() {
      _historyTo = normalized;
      if (_historyFrom.isAfter(_historyTo)) _historyFrom = _historyTo;
    });
    _loadHistory();
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
    final summary = _accountSummary;
    if (summary == null) return;

    setState(() => _isExportingPdf = true);
    try {
      await _exporter.export(
        AccountStatementData(
          customerBalance: summary.customerBalance,
          creditUtilization: CreditUtilizationData(
            availableCredit: summary.availableCredit,
            usedCredit: summary.usedCredit,
          ),
          historyFrom: _historyFrom,
          historyTo: _historyTo,
          quickHistory: _quickHistory,
          generatedAt: DateTime.now(),
          currencyCode: widget.currencyCode,
        ),
      );
    } catch (error) {
      debugPrint('Account statement export failed: $error');
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text(context.t('accountBalance.exportFailed'))),
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
      SnackBar(
        content: Text(context.t('accountBalance.fullHistoryUnavailable')),
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
        tooltip: context.t('common.back'),
        // No navigation drawer/menu content is defined yet for this screen,
        // so the menu affordance falls back to simple back navigation,
        // matching InvoiceDetailsScreen's convention.
        onPressed: () => Navigator.of(context).maybePop(),
      ),
      title: ClampedTextScale(child: _buildBrandTitle()),
      actions: [
        Padding(
          padding: const EdgeInsetsDirectional.only(end: 16),
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
    final summary = _accountSummary;
    if (summary == null) return const SizedBox.shrink();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: ResponsiveMaxWidth(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AccountBalanceHeroCard(
              balance: summary.customerBalance,
              onExportPdf: _exportPdf,
              isExporting: _isExportingPdf,
              currencyCode: widget.currencyCode,
            ),
            const SizedBox(height: 16),
            CreditUtilizationCard(
              data: CreditUtilizationData(
                availableCredit: summary.availableCredit,
                usedCredit: summary.usedCredit,
              ),
              currencyCode: widget.currencyCode,
            ),
            const SizedBox(height: 16),
            BalanceHistoryCard(
              from: _historyFrom,
              to: _historyTo,
              onFromChanged: _handleFromChanged,
              onToChanged: _handleToChanged,
              state: switch (_historyState) {
                _BalanceHistoryState.loading => BalanceHistoryLoadState.loading,
                _BalanceHistoryState.loaded => BalanceHistoryLoadState.loaded,
                _BalanceHistoryState.empty => BalanceHistoryLoadState.empty,
                _BalanceHistoryState.error => BalanceHistoryLoadState.error,
              },
              points: _historyPoints,
              hasMultipleCurrencies: _historyHasMultipleCurrencies,
              errorMessage: _historyState == _BalanceHistoryState.error
                  ? _businessCentralOutcomeMessage(context, _historyOutcome)
                  : null,
              onRetry: _loadHistory,
            ),
            const SizedBox(height: 16),
            _buildQuickHistorySection(),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickHistorySection() {
    switch (_quickHistoryState) {
      case _QuickHistoryState.loading:
        return const _QuickHistorySectionShell(
          key: ValueKey('quick-history-loading'),
          child: Center(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: CircularProgressIndicator(),
            ),
          ),
        );
      case _QuickHistoryState.empty:
        return _QuickHistorySectionShell(
          key: const ValueKey('quick-history-empty'),
          message: context.t('accountBalance.noStatementEntries'),
        );
      case _QuickHistoryState.error:
        return _QuickHistorySectionShell(
          key: const ValueKey('quick-history-error'),
          message: _businessCentralOutcomeMessage(
            context,
            _quickHistoryOutcome,
          ),
          onRetry: _loadQuickHistory,
        );
      case _QuickHistoryState.loaded:
        return QuickHistoryCard(
          transactions: _quickHistory,
          onTransactionTap: _openTransactionDetails,
          onSeeAll: _openFullTransactionHistory,
        );
    }
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
              _error ?? context.t('accountBalance.unableToLoad'),
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
              child: Text(context.t('common.retry')),
            ),
          ],
        ),
      ),
    );
  }
}

/// Quick History section placeholder for the loading/empty/error states,
/// reusing [QuickHistoryCard]'s exact outer chrome (white card, border,
/// radius 12, "QUICK HISTORY" header) so the section never visually jumps
/// once real rows arrive. [QuickHistoryCard] itself is untouched — this is
/// a sibling widget shown in its place, never a modification of it.
class _QuickHistorySectionShell extends StatelessWidget {
  const _QuickHistorySectionShell({
    super.key,
    this.child,
    this.message,
    this.onRetry,
  });

  final Widget? child;
  final String? message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.t('accountBalance.quickHistoryTitle'),
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: AppColors.textNavy,
            ),
          ),
          const SizedBox(height: 12),
          ?child,
          if (message != null) ...[
            Text(
              message!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.grayText, fontSize: 13),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 8),
              Center(
                child: TextButton(
                  onPressed: onRetry,
                  child: Text(context.t('common.retry')),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}
