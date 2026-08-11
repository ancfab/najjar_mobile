import 'package:flutter/material.dart';

import '../config/demo_config.dart';
import '../data/mock_user.dart';
import '../localization/translations.dart';
import '../models/business_central/business_central_item_search_group.dart';
import '../models/business_central/payment_entry.dart';
import '../models/home_dashboard_data.dart';
import '../services/api_stock_lookup_service.dart';
import '../services/business_central_error_mapper.dart';
import '../services/current_balance_data_source.dart';
import '../services/current_balance_service.dart';
import '../services/demo_current_balance_data_source.dart';
import '../services/home_dashboard_service.dart';
import '../services/item_catalogue_search_service.dart';
import '../services/last_payment_data_source.dart';
import '../services/stock_lookup_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_radius.dart';
import '../theme/app_shadows.dart';
import '../theme/app_spacing.dart';
import '../utils/currency.dart';
import '../utils/date_time_format.dart';
import '../utils/responsive.dart';
import '../widgets/availability_search_card.dart';
import '../widgets/balance_card.dart';
import '../widgets/custom_bottom_nav.dart';
import '../widgets/home_header.dart';
import '../widgets/last_payment_card.dart';
import '../widgets/metric_card.dart';
import '../widgets/scan_fabric_button.dart';
import 'account_balance_screen.dart';
import 'edit_profile_screen.dart';
import 'invoices_screen.dart';
import 'orders_screen.dart';
import 'scan_stock_screen.dart';
import 'support_screen.dart';

// Bottom tab bar indexes, kept in one place so they stay in sync with the
// tab order rendered by CustomBottomNav.
const int _navIndexHome = 0;
const int _navIndexOrders = 1;
const int _navIndexSupport = 2;
const int _navIndexProfile = 3;

/// UI state for the Check Availability catalogue lookup card, derived from
/// the [StockLookupResult] the shared [StockLookupService] returns — see
/// `_HomeScreenState._stageFor`. Mirrors `ScanStockScreen`'s `_LookupStage`
/// convention, folding the categories that show identical generic
/// error+retry copy on this compact card ([StockLookupUnexpectedFailure],
/// [StockLookupMappingNotConfigured]) into [retryableFailure].
enum _CheckAvailabilityUiState {
  idle,
  loading,
  invalidInput,
  success,
  notFound,
  retryableFailure,
  temporarilyUnavailable,
}

/// UI state for the Check Availability *catalogue search* step, derived
/// from the [ItemCatalogueSearchResult] `ItemCatalogueSearchService`
/// returns — this is the step ahead of [_CheckAvailabilityUiState], which
/// now only covers the final stock lookup once a variation is selected. See
/// `_HomeScreenState.searchFabricAvailabilityByCatalogueCode`.
enum _CatalogueSearchUiState {
  idle,
  loading,
  invalidInput,
  noResults,
  error,
  temporarilyUnavailable,
  exactMatch,
  suggestions,
}

/// UI state for the Last Payment row, tracked independently of the rest of
/// the dashboard (balance/orders/invoices) so a Payments API failure never
/// blanks out those mock-backed sections, and vice versa — mirrors
/// `AccountBalanceScreen`'s `_QuickHistoryState` convention.
enum _LastPaymentUiState { loading, loaded, empty, error }

/// UI state for the Current Balance card, tracked independently of Last
/// Payment and the (still mock-backed) Active Orders/Overdue Invoices cards
/// so a ledger-entries failure never blanks out those, and vice versa. No
/// distinct "empty" state: a zero balance is a legitimate calculated result,
/// rendered the same way as any other loaded amount — never an empty card.
enum _CurrentBalanceUiState { loading, loaded, error }

/// Resolves the [CurrentBalanceDataSource] `HomeScreen` falls back to when no
/// source is injected by a caller (every existing test already injects one,
/// so this only ever runs in the real app). Defaults [useDemo] to
/// [DemoConfig.useDemoCurrentBalance] but accepts it as a parameter so both
/// branches stay unit-testable regardless of the flag's current compiled-in
/// value.
///
/// TEMPORARY CLIENT DEMO MODE indirection: when `useDemo` is true this
/// returns [DemoCurrentBalanceDataSource] instead of
/// [LiveCurrentBalanceDataSource] — the live service, data source, and
/// calculation are untouched and fully restored once the flag is set back to
/// `false`.
CurrentBalanceDataSource resolveDefaultCurrentBalanceDataSource({
  bool useDemo = DemoConfig.useDemoCurrentBalance,
}) {
  return useDemo
      ? const DemoCurrentBalanceDataSource()
      : LiveCurrentBalanceDataSource();
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    this.lastPaymentSource,
    this.currentBalanceSource,
    this.checkAvailabilityService,
    this.catalogueSearchService,
  });

  /// Last Payment data seam. Defaults (lazily, in State) to
  /// [LiveLastPaymentDataSource] — the live Business Central Payments
  /// endpoint; overridable so tests can inject a fake.
  final LastPaymentDataSource? lastPaymentSource;

  /// Current Balance data seam. Defaults (lazily, in State) via
  /// [resolveDefaultCurrentBalanceDataSource] to [LiveCurrentBalanceDataSource]
  /// — the live Business Central ledger-entries endpoint, paged in full and
  /// reduced per the confirmed Current Balance rules — unless
  /// [DemoConfig.useDemoCurrentBalance] (TEMPORARY CLIENT DEMO MODE) is
  /// `true`, in which case [DemoCurrentBalanceDataSource] is used instead;
  /// overridable so tests (and the demo flag) can inject a fake instead of
  /// exercising real HTTP/secure storage.
  final CurrentBalanceDataSource? currentBalanceSource;

  /// Check Availability card's stock-lookup seam — the same shared
  /// [StockLookupService] contract `ScanStockScreen` depends on for its
  /// camera/barcode and manual-entry lookups. Left `null` here (rather than
  /// defaulted in this constructor) and resolved lazily in
  /// [_HomeScreenState.initState] instead, mirroring
  /// `ScanStockScreen.stockLookupService`'s exact ownership-disposal
  /// pattern: the production default, [ApiStockLookupService], owns a real
  /// `AncApiClient`/`SecureAuthSessionStore` that must be closed on
  /// [State.dispose]. Overridable so tests can inject a fake instead of
  /// making a real network call.
  final StockLookupService? checkAvailabilityService;

  /// Check Availability card's catalogue-search seam, called first once the
  /// user searches — resolves to an exact `commonItemNo` match or a set of
  /// catalogue suggestions before any variation is looked up via
  /// [checkAvailabilityService]. Left `null` here and resolved lazily in
  /// [_HomeScreenState.initState], mirroring [checkAvailabilityService]'s
  /// exact ownership-disposal pattern.
  final ItemCatalogueSearchService? catalogueSearchService;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final HomeDashboardService _dashboardService = const HomeDashboardService();
  final TextEditingController _catalogueCodeController =
      TextEditingController();
  late final LastPaymentDataSource _lastPaymentSource =
      widget.lastPaymentSource ?? LiveLastPaymentDataSource();
  late final CurrentBalanceDataSource _currentBalanceSource =
      widget.currentBalanceSource ?? resolveDefaultCurrentBalanceDataSource();

  /// Check Availability's stock-lookup seam actually used by
  /// [searchFabricAvailabilityByCatalogueCode] — resolved in [initState],
  /// not here; see [HomeScreen.checkAvailabilityService]'s doc comment for
  /// why.
  late final StockLookupService _checkAvailabilityService;

  /// Set only when this State created its own [ApiStockLookupService] (no
  /// [HomeScreen.checkAvailabilityService] was injected) — the only
  /// instance this screen ever closes; a caller-injected [StockLookupService]
  /// is left alone since this screen doesn't own it.
  ApiStockLookupService? _ownedCheckAvailabilityService;

  /// Check Availability's catalogue-search seam actually used by
  /// [searchFabricAvailabilityByCatalogueCode] — resolved in [initState],
  /// mirroring [_checkAvailabilityService]'s exact pattern; see
  /// [HomeScreen.catalogueSearchService]'s doc comment for why.
  late final ItemCatalogueSearchService _catalogueSearchService;

  /// Set only when this State created its own [ApiItemCatalogueSearchService]
  /// (no [HomeScreen.catalogueSearchService] was injected) — the only
  /// instance this screen ever closes.
  ApiItemCatalogueSearchService? _ownedCatalogueSearchService;

  int _selectedNavIndex = _navIndexHome;

  // Home dashboard summary state (active orders, overdue invoices — still
  // mock-backed). Current Balance and Last Payment are loaded and tracked
  // independently below — see _CurrentBalanceUiState/_LastPaymentUiState.
  HomeDashboardData? _dashboardData;
  bool _isDashboardLoading = true;
  String? _dashboardError;

  // Current Balance card state — loaded live from the ledger-entries API.
  _CurrentBalanceUiState _currentBalanceState = _CurrentBalanceUiState.loading;
  CurrentBalanceAmount? _currentBalanceAmount;

  /// Set only when [_currentBalanceState] is [_CurrentBalanceUiState.error]
  /// from a [BusinessCentralFailureException] — `null` for a generic/
  /// unexpected failure (including
  /// [CurrentBalanceInconsistentCurrencyException]), which gets the same
  /// neutral retry copy as every outcome other than "temporarily
  /// unavailable".
  BusinessCentralOutcome? _currentBalanceOutcome;

  /// Bumped at the start of every [_loadCurrentBalance] call, so a stale
  /// in-flight request (e.g. a slow initial load that resolves after a
  /// pull-to-refresh already started a newer one) can recognize itself as
  /// superseded and discard its result instead of corrupting fresher state.
  int _currentBalanceRequestId = 0;

  // Last Payment row state — loaded live from the Payments API.
  _LastPaymentUiState _lastPaymentState = _LastPaymentUiState.loading;
  PaymentEntry? _lastPaymentEntry;

  /// Set only when [_lastPaymentState] is [_LastPaymentUiState.error] from a
  /// [BusinessCentralFailureException] — `null` for a generic/unexpected
  /// failure, which gets the same neutral retry copy as every outcome other
  /// than "temporarily unavailable".
  BusinessCentralOutcome? _lastPaymentOutcome;

  /// Bumped at the start of every [_loadLastPayment] call, so a stale
  /// in-flight request (e.g. a slow initial load that resolves after a
  /// pull-to-refresh already started a newer one) can recognize itself as
  /// superseded and discard its result instead of corrupting fresher state.
  int _lastPaymentRequestId = 0;

  // Check Availability card state. Two steps: catalogue search (this
  // screen's own ItemCatalogueSearchService) resolves the entered code to an
  // exact commonItemNo group or a set of suggested groups; picking a
  // variation from that group then runs the existing exact-itemNo stock
  // lookup below via the shared StockLookupService — unchanged from before
  // this feature, and identical to ScanStockScreen's lookup contract.
  _CatalogueSearchUiState _catalogueSearchState = _CatalogueSearchUiState.idle;

  /// The raw (untrimmed) search text the most recent catalogue search was
  /// performed for — used only to render "{code}" in no-match copy.
  String _catalogueSearchQuery = '';

  /// The groups behind the current [_catalogueSearchState]: the single
  /// exact match (as a one-element list) when
  /// [_CatalogueSearchUiState.exactMatch], or every suggested group when
  /// [_CatalogueSearchUiState.suggestions]. Empty otherwise.
  List<BusinessCentralItemSearchGroup> _catalogueGroups = const [];

  /// The catalogue group whose variations are currently shown — set
  /// automatically on an exact match, or when the user taps a suggestion.
  /// `null` means no group's variations are shown yet (idle, loading, an
  /// error/no-results state, or unresolved suggestions).
  BusinessCentralItemSearchGroup? _selectedCatalogueGroup;

  /// True while a catalogue search is in flight — guards against a second
  /// search starting concurrently (e.g. a rapid double-tap of the search
  /// button).
  bool _isCatalogueSearching = false;

  /// Bumped at the start of every [searchFabricAvailabilityByCatalogueCode]
  /// call, so a catalogue search that resolves after a newer one has
  /// already started (or after dispose) can recognize itself as stale and
  /// discard its result instead of corrupting fresher state.
  int _catalogueSearchGeneration = 0;

  /// The variation the user picked from [_selectedCatalogueGroup] — its
  /// `itemNo` is what was actually sent to [_checkAvailabilityService]. Also
  /// the value cleared whenever a new catalogue search starts or a
  /// different group is selected, so a stale availability result is never
  /// left showing.
  BusinessCentralItemVariation? _selectedVariation;

  // Final stock-availability state (once a variation has been selected) —
  // loaded live from the Inventory API via the shared StockLookupService.
  // Unchanged from before this feature except that the code it looks up is
  // now always a variation's confirmed itemNo, never raw search text.
  _CheckAvailabilityUiState _checkAvailabilityState =
      _CheckAvailabilityUiState.idle;

  /// The most recent lookup result, or null when [_checkAvailabilityState]
  /// is [_CheckAvailabilityUiState.idle] or [_CheckAvailabilityUiState.loading].
  StockLookupResult? _checkAvailabilityResult;

  /// True while a lookup is in flight — guards against a second lookup
  /// starting concurrently (e.g. a rapid double-tap on a variation row).
  bool _isCheckingAvailability = false;

  /// Bumped at the start of every [_selectVariation] call (and whenever a
  /// new catalogue search supersedes the current selection), so a lookup
  /// that resolves after a newer one has already started (or after
  /// dispose) can recognize itself as stale and discard its result instead
  /// of corrupting fresher state.
  int _checkAvailabilityGeneration = 0;

  @override
  void initState() {
    super.initState();
    loadHomeDashboardData();
    _loadCurrentBalance();
    _loadLastPayment();
    final injectedCheckAvailabilityService = widget.checkAvailabilityService;
    if (injectedCheckAvailabilityService != null) {
      _checkAvailabilityService = injectedCheckAvailabilityService;
    } else {
      final owned = ApiStockLookupService();
      _ownedCheckAvailabilityService = owned;
      _checkAvailabilityService = owned;
    }
    final injectedCatalogueSearchService = widget.catalogueSearchService;
    if (injectedCatalogueSearchService != null) {
      _catalogueSearchService = injectedCatalogueSearchService;
    } else {
      final owned = ApiItemCatalogueSearchService();
      _ownedCatalogueSearchService = owned;
      _catalogueSearchService = owned;
    }
  }

  @override
  void dispose() {
    _catalogueCodeController.dispose();
    // Bumping both generations here means an in-flight catalogue search or
    // stock lookup's continuation recognizes itself as stale (see
    // [searchFabricAvailabilityByCatalogueCode]/[_selectVariation]) and
    // never calls setState after dispose.
    _catalogueSearchGeneration++;
    _checkAvailabilityGeneration++;
    _ownedCheckAvailabilityService?.close();
    _ownedCatalogueSearchService?.close();
    super.dispose();
  }

  /// Loads Home dashboard summary data from API or mock fallback.
  Future<void> loadHomeDashboardData() async {
    setState(() {
      _isDashboardLoading = true;
      _dashboardError = null;
    });
    try {
      final data = await _dashboardService.fetchHomeDashboardData();
      if (!mounted) return;
      setState(() {
        _dashboardData = data;
        _isDashboardLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _dashboardError = context.t('home.unableToLoadDashboard');
        _isDashboardLoading = false;
      });
    }
  }

  /// Refreshes Home dashboard data when user pulls down on the Home screen.
  /// Fans out to the mock Active Orders/Overdue Invoices summary and the
  /// live Current Balance and Last Payment sources in parallel, since all
  /// three load independently (see [_loadCurrentBalance]/[_loadLastPayment]).
  Future<void> refreshHomeDashboardData() async {
    await Future.wait([
      _refreshDashboardSummary(),
      _loadCurrentBalance(),
      _loadLastPayment(),
    ]);
  }

  Future<void> _refreshDashboardSummary() async {
    try {
      final data = await _dashboardService.fetchHomeDashboardData();
      if (!mounted) return;
      setState(() {
        _dashboardData = data;
        _dashboardError = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(
        () => _dashboardError = context.t('home.unableToRefreshDashboard'),
      );
    }
  }

  /// Retries loading Home dashboard data after an error.
  Future<void> retryLoadHomeDashboardData() async {
    await loadHomeDashboardData();
  }

  /// Loads Current Balance from the live ledger-entries API (every page,
  /// reduced per the confirmed Current Balance rules). Independent of
  /// [loadHomeDashboardData]/[_loadLastPayment], so a ledger-entries failure
  /// never blanks out Active Orders/Overdue Invoices/Last Payment, and vice
  /// versa. Also serves as the retry action after an error.
  ///
  /// On HTTP 401, [CurrentBalanceDataSource] throws [SessionExpiredException]
  /// only after the centralized session coordinator has already cleared the
  /// session and is navigating to Login — this shows no local error state
  /// for that case, matching [_loadLastPayment].
  Future<void> _loadCurrentBalance() async {
    final requestId = ++_currentBalanceRequestId;
    setState(() {
      _currentBalanceState = _CurrentBalanceUiState.loading;
      _currentBalanceOutcome = null;
    });
    try {
      final result = await _currentBalanceSource.fetchCurrentBalance();
      if (!mounted || requestId != _currentBalanceRequestId) return;
      setState(() {
        _currentBalanceAmount = result;
        _currentBalanceState = _CurrentBalanceUiState.loaded;
      });
    } on SessionExpiredException {
      // The centralized session coordinator has already cleared the
      // session and is navigating to Login — show nothing here.
    } on BusinessCentralFailureException catch (error) {
      if (!mounted || requestId != _currentBalanceRequestId) return;
      setState(() {
        _currentBalanceOutcome = error.outcome;
        _currentBalanceState = _CurrentBalanceUiState.error;
      });
    } catch (_) {
      // Covers CurrentBalanceInconsistentCurrencyException and any other
      // unexpected failure with the same generic, safe retry copy.
      if (!mounted || requestId != _currentBalanceRequestId) return;
      setState(() {
        _currentBalanceOutcome = null;
        _currentBalanceState = _CurrentBalanceUiState.error;
      });
    }
  }

  /// Maps [_currentBalanceOutcome] to controlled, safe user-facing copy —
  /// the backend's raw `message` is never shown directly (see
  /// `BusinessCentralOutcome`'s doc comments).
  String _currentBalanceErrorMessage() {
    return switch (_currentBalanceOutcome) {
      BusinessCentralTemporarilyUnavailable() => context.t(
        'currentBalance.errorTemporarilyUnavailable',
      ),
      _ => context.t('currentBalance.errorGeneric'),
    };
  }

  /// Formats a successfully-loaded [CurrentBalanceAmount] using the
  /// confirmed currency rules: the ledger's own currency code exactly as
  /// returned, or a visible "?" indicator when no relevant entry had a
  /// nonblank currency code — never a guessed symbol, never USD by default.
  String _formatCurrentBalanceAmount(CurrentBalanceAmount result) {
    return formatCurrencyOrUnknown(
      result.amount,
      currencyCode: result.currencyCode,
    );
  }

  /// Loads the most recent payment from the live Payments API for the Last
  /// Payment row. Independent of [loadHomeDashboardData]/
  /// [refreshHomeDashboardData]'s mock dashboard summary, so a Payments API
  /// failure never blanks out Balance/Orders/Invoices, and a mock-fetch
  /// failure never blocks or clears a successfully loaded payment. Also
  /// serves as the retry action after an error.
  ///
  /// On HTTP 401, [LastPaymentDataSource] throws [SessionExpiredException]
  /// only after the centralized session coordinator has already cleared the
  /// session and is navigating to Login — this shows no local error state
  /// for that case, matching `AccountBalanceScreen._loadQuickHistory`.
  Future<void> _loadLastPayment() async {
    final requestId = ++_lastPaymentRequestId;
    setState(() {
      _lastPaymentState = _LastPaymentUiState.loading;
      _lastPaymentOutcome = null;
    });
    try {
      final entry = await _lastPaymentSource.fetchLatestPayment();
      if (!mounted || requestId != _lastPaymentRequestId) return;
      setState(() {
        _lastPaymentEntry = entry;
        _lastPaymentState = entry == null
            ? _LastPaymentUiState.empty
            : _LastPaymentUiState.loaded;
      });
    } on SessionExpiredException {
      // The centralized session coordinator has already cleared the
      // session and is navigating to Login — show nothing here.
    } on BusinessCentralFailureException catch (error) {
      if (!mounted || requestId != _lastPaymentRequestId) return;
      setState(() {
        _lastPaymentOutcome = error.outcome;
        _lastPaymentState = _LastPaymentUiState.error;
      });
    } catch (_) {
      if (!mounted || requestId != _lastPaymentRequestId) return;
      setState(() {
        _lastPaymentOutcome = null;
        _lastPaymentState = _LastPaymentUiState.error;
      });
    }
  }

  /// Maps [_lastPaymentOutcome] to controlled, safe user-facing copy — the
  /// backend's raw `message` is never shown directly (see
  /// `BusinessCentralOutcome`'s doc comments).
  String _lastPaymentErrorMessage() {
    return switch (_lastPaymentOutcome) {
      BusinessCentralTemporarilyUnavailable() => context.t(
        'lastPayment.errorTemporarilyUnavailable',
      ),
      _ => context.t('lastPayment.errorGeneric'),
    };
  }

  /// Formats [entry.amount] as an absolute, never-negative value per the
  /// confirmed display rule, using [entry.currencyCode] exactly as returned
  /// — never trimmed, never defaulted to USD/`$`. [formatCurrency] only adds
  /// its own `$` fallback when passed a `null` currency code, which this
  /// never does; a blank (but non-null) code instead reuses that same
  /// numeric formatting with the incidental leading separator space
  /// trimmed, so a missing currency still reads as a plain number rather
  /// than a fabricated symbol.
  String _formatLastPaymentAmount(PaymentEntry entry) {
    final formatted = formatCurrency(
      entry.amount.abs(),
      currencyCode: entry.currencyCode,
    );
    return entry.currencyCode.trim().isEmpty ? formatted.trimLeft() : formatted;
  }

  /// Validates that the catalogue code input is not empty (after trimming
  /// surrounding whitespace) — rejected locally, before any API call.
  bool validateCatalogueCodeInput(String input) {
    return input.trim().isNotEmpty;
  }

  /// Looks up fabric availability from the Home screen using the entered
  /// catalogue code — the single entry point both the search button and
  /// keyboard submission call (see `AvailabilitySearchCard.onSubmitted`).
  ///
  /// Unlike before this feature, the entered text is no longer treated as
  /// an exact `itemNo`: it is first resolved to a catalogue group via
  /// [_catalogueSearchService] (`GET /items?search=...`). An exact
  /// `commonItemNo` match shows that group's variations directly; anything
  /// else shows every returned group as a suggestion. Only once the user
  /// picks a concrete variation does [_selectVariation] call the existing,
  /// unchanged [StockLookupService] exact-`itemNo` lookup — see that
  /// method.
  ///
  /// Starting a new search always clears any selection/result left over
  /// from a previous one (never leaves a stale variation or availability
  /// result showing), and bumps both [_catalogueSearchGeneration] and
  /// [_checkAvailabilityGeneration] so a slow in-flight request from the
  /// previous query can never land after this one starts.
  Future<void> searchFabricAvailabilityByCatalogueCode() async {
    final rawInput = _catalogueCodeController.text;
    final trimmedCode = rawInput.trim();

    if (trimmedCode.isEmpty) {
      _catalogueSearchGeneration++;
      _checkAvailabilityGeneration++;
      setState(() {
        _catalogueSearchState = _CatalogueSearchUiState.invalidInput;
        _catalogueGroups = const [];
        _selectedCatalogueGroup = null;
        _selectedVariation = null;
        _checkAvailabilityState = _CheckAvailabilityUiState.idle;
        _checkAvailabilityResult = null;
      });
      return;
    }

    // Duplicate-submission guard: ignored while a search is already in
    // flight, whether triggered again by the button or the keyboard.
    if (_isCatalogueSearching) return;
    _isCatalogueSearching = true;
    // Supersede any in-flight variation lookup from a previous query too —
    // its continuation (see [_selectVariation]) will recognize itself as
    // stale and never overwrite this fresh search's state.
    _checkAvailabilityGeneration++;
    final requestId = ++_catalogueSearchGeneration;

    setState(() {
      _catalogueSearchState = _CatalogueSearchUiState.loading;
      _catalogueGroups = const [];
      _selectedCatalogueGroup = null;
      _selectedVariation = null;
      _checkAvailabilityState = _CheckAvailabilityUiState.idle;
      _checkAvailabilityResult = null;
    });

    ItemCatalogueSearchResult result;
    try {
      result = await _catalogueSearchService.search(trimmedCode);
    } catch (error) {
      // A truly unexpected exception (an implementation bug) must not crash
      // the screen; treat it like any other unexpected failure.
      debugPrint('Catalogue search threw unexpectedly: $error');
      result = ItemCatalogueRetryableFailure(trimmedCode);
    }

    _isCatalogueSearching = false;
    // Discards a response that arrived after a newer search started (or
    // after dispose bumped the generation) rather than overwriting fresher
    // state with stale data.
    if (!mounted || requestId != _catalogueSearchGeneration) return;

    if (result is ItemCatalogueSessionExpired) {
      // A real adapter hands off to the session coordinator (which
      // navigates to Login) before ever returning this — matching
      // SessionExpiredException elsewhere in the app, there is nothing
      // controlled to show here.
      setState(() {
        _catalogueSearchState = _CatalogueSearchUiState.idle;
        _catalogueGroups = const [];
      });
      return;
    }

    setState(() {
      _catalogueSearchQuery = result.rawQuery;
      switch (result) {
        case ItemCatalogueExactMatch(:final group):
          _catalogueSearchState = _CatalogueSearchUiState.exactMatch;
          _catalogueGroups = [group];
          _selectedCatalogueGroup = group;
        case ItemCatalogueSuggestions(:final groups):
          _catalogueSearchState = _CatalogueSearchUiState.suggestions;
          _catalogueGroups = groups;
        case ItemCatalogueNoResults():
          _catalogueSearchState = _CatalogueSearchUiState.noResults;
          _catalogueGroups = const [];
        case ItemCatalogueInvalidQuery():
          _catalogueSearchState = _CatalogueSearchUiState.invalidInput;
          _catalogueGroups = const [];
        case ItemCatalogueRetryableFailure():
          _catalogueSearchState = _CatalogueSearchUiState.error;
          _catalogueGroups = const [];
        case ItemCatalogueTemporarilyUnavailable():
          _catalogueSearchState =
              _CatalogueSearchUiState.temporarilyUnavailable;
          _catalogueGroups = const [];
        case ItemCatalogueSessionExpired():
          break; // unreachable — handled above
      }
    });
  }

  /// Error text shown below the helper text for the catalogue-search
  /// invalid-input/error/unavailable states — `null` for every other state,
  /// per `AvailabilitySearchCard`'s errorText/resultText mutual-exclusivity.
  String? _catalogueSearchErrorText() {
    return switch (_catalogueSearchState) {
      _CatalogueSearchUiState.invalidInput => context.t(
        'home.enterCatalogueCodeValidation',
      ),
      _CatalogueSearchUiState.error => context.t('home.catalogueSearchError'),
      _CatalogueSearchUiState.temporarilyUnavailable => context.t(
        'home.catalogueSearchUnavailable',
      ),
      _ => null,
    };
  }

  /// Result text shown below the helper text for the catalogue no-results
  /// state — `null` for every other state.
  String? _catalogueSearchResultText() {
    if (_catalogueSearchState != _CatalogueSearchUiState.noResults) {
      return null;
    }
    return context.t(
      'home.catalogueNoMatchFound',
      params: {'code': _catalogueSearchQuery},
    );
  }

  /// Selects a suggested catalogue group (the user tapped it from the
  /// [_CatalogueSearchUiState.suggestions] list), showing its variations.
  /// Clears any previously selected variation/availability result — never
  /// leaves a stale one visible under the newly selected group.
  void _selectCatalogueGroup(BusinessCentralItemSearchGroup group) {
    _checkAvailabilityGeneration++;
    setState(() {
      _selectedCatalogueGroup = group;
      _selectedVariation = null;
      _checkAvailabilityState = _CheckAvailabilityUiState.idle;
      _checkAvailabilityResult = null;
    });
  }

  /// Returns from a selected suggestion's variations back to the
  /// suggestions list — only reachable when [_catalogueSearchState] is
  /// [_CatalogueSearchUiState.suggestions] (an exact match has no
  /// suggestions list to return to).
  void _clearSelectedCatalogueGroup() {
    _checkAvailabilityGeneration++;
    setState(() {
      _selectedCatalogueGroup = null;
      _selectedVariation = null;
      _checkAvailabilityState = _CheckAvailabilityUiState.idle;
      _checkAvailabilityResult = null;
    });
  }

  /// Runs the final, unchanged exact-`itemNo` stock lookup for a variation
  /// the user picked from [_selectedCatalogueGroup] — the same
  /// [StockLookupService] contract `ScanStockScreen` uses, never a second,
  /// duplicated inventory-fetch/filter/aggregate path.
  Future<void> _selectVariation(BusinessCentralItemVariation variation) async {
    // Duplicate-submission guard: ignored while a lookup is already in
    // flight, whether triggered again by the same or a different variation.
    if (_isCheckingAvailability) return;
    _isCheckingAvailability = true;
    final requestId = ++_checkAvailabilityGeneration;


    setState(() {
      _selectedVariation = variation;
      _checkAvailabilityState = _CheckAvailabilityUiState.loading;
      _checkAvailabilityResult = null;
    });

    StockLookupResult result;
    try {
      // TEMPORARY DIAGNOSTIC — see above. Logged immediately before the
      // call so it is unambiguous that this is the exact-itemNo inventory
      // lookup, never a second catalogue search.
      result = await _checkAvailabilityService.lookup(variation.itemNo);
    } catch (error) {
      // A truly unexpected exception (an implementation bug) must not crash
      // the screen; treat it like any other unexpected failure.
      debugPrint('Check Availability lookup threw unexpectedly: $error');
      result = StockLookupUnexpectedFailure(variation.itemNo);
    }

    _isCheckingAvailability = false;
    // Discards a response that arrived after a newer lookup/search started
    // (or after dispose bumped the generation) rather than overwriting
    // fresher state with stale data.
    if (!mounted || requestId != _checkAvailabilityGeneration) return;

    if (result is StockLookupSessionExpired) {
      // A real adapter hands off to the session coordinator (which
      // navigates to Login) before ever returning this — matching
      // SessionExpiredException elsewhere in the app, there is nothing
      // controlled to show here.
      setState(() {
        _checkAvailabilityState = _CheckAvailabilityUiState.idle;
        _checkAvailabilityResult = null;
      });
      return;
    }

    setState(() {
      _checkAvailabilityResult = result;
      _checkAvailabilityState = _stageForCheckAvailability(result);
    });
  }

  /// Maps every [StockLookupResult] subtype the shared [StockLookupService]
  /// contract defines to this card's UI state — exhaustive, so a future
  /// subtype forces this switch to be updated rather than silently falling
  /// through. Mirrors `ScanStockScreen._stageFor`.
  static _CheckAvailabilityUiState _stageForCheckAvailability(
    StockLookupResult result,
  ) => switch (result) {
    StockLookupSuccess() => _CheckAvailabilityUiState.success,
    StockLookupNotFound() => _CheckAvailabilityUiState.notFound,
    StockLookupInvalidCode() => _CheckAvailabilityUiState.invalidInput,
    StockLookupRetryableFailure() => _CheckAvailabilityUiState.retryableFailure,
    StockLookupUnexpectedFailure() =>
      _CheckAvailabilityUiState.retryableFailure,
    StockLookupTemporarilyUnavailable() =>
      _CheckAvailabilityUiState.temporarilyUnavailable,
    // Unreachable via the production ApiStockLookupService default (only
    // UnconfiguredStockLookupService returns this) — handled defensively
    // with the same generic retry copy rather than omitted, so this switch
    // stays exhaustive if a future StockLookupService swap ever returns it.
    StockLookupMappingNotConfigured() =>
      _CheckAvailabilityUiState.retryableFailure,
    StockLookupSessionExpired() => _CheckAvailabilityUiState.idle,
  };

  /// Error text shown below the helper text for validation/retryable/
  /// unavailable states — `null` for every other state, per
  /// `AvailabilitySearchCard`'s errorText/resultText mutual-exclusivity.
  String? _checkAvailabilityErrorText() {
    return switch (_checkAvailabilityState) {
      _CheckAvailabilityUiState.invalidInput => context.t(
        'home.enterCatalogueCodeValidation',
      ),
      _CheckAvailabilityUiState.retryableFailure => context.t(
        'home.catalogueLookupError',
      ),
      _CheckAvailabilityUiState.temporarilyUnavailable => context.t(
        'home.checkAvailabilityUnavailable',
      ),
      _ => null,
    };
  }

  /// Result text shown below the helper text for the no-results/success
  /// states — `null` for every other state.
  String? _checkAvailabilityResultText() {
    final result = _checkAvailabilityResult;
    if (result == null) return null;
    return switch (_checkAvailabilityState) {
      _CheckAvailabilityUiState.notFound => context.t(
        'home.noAvailabilityFound',
        params: {'code': result.rawCode},
      ),
      _CheckAvailabilityUiState.success when result is StockLookupSuccess =>
        _formatCheckAvailabilityResult(result) ??
            // Defensive only: the confirmed ApiStockLookupService contract
            // never returns a success with an empty availabilityByLocation
            // (see StockLookupSuccess's doc comment) — but a StockLookupResult
            // is a shared interface, so this falls back to the same "nothing
            // available" copy rather than rendering blank text if some future
            // implementation ever did.
            context.t(
              'home.noAvailabilityFound',
              params: {'code': result.rawCode},
            ),
      _ => null,
    };
  }

  /// Formats a successful lookup as the item's description (when present —
  /// never fabricated) followed by one line per open location/unit-of-measure
  /// combination — see `StockLookupSuccess.availabilityByLocation`. Multiple
  /// locations, and different units of measure at the same location, are
  /// always shown as separate lines, never combined into one total. `null`
  /// when there is nothing to show (see [_checkAvailabilityResultText]).
  String? _formatCheckAvailabilityResult(StockLookupSuccess result) {
    final description = result.description;
    final lines = <String>[
      if (description != null && description.isNotEmpty) description,
      for (final availability in result.availabilityByLocation)
        context.t(
          'home.availableAtLocation',
          params: {
            'quantity': _formatAvailabilityQuantity(
              availability.remainingQuantity,
            ),
            'unit': availability.unitOfMeasureCode,
            'location': availability.locationCode.isEmpty
                ? context.t('home.unknownLocation')
                : availability.locationCode,
          },
        ),
    ];
    return lines.isEmpty ? null : lines.join('\n');
  }

  /// Renders a whole-number quantity without a trailing ".0" while still
  /// showing decimals when the backend actually reports a fractional value —
  /// mirrors `ScanStockScreen`'s own `_formatQuantity`.
  static String _formatAvailabilityQuantity(num value) {
    final asDouble = value.toDouble();
    if (asDouble == asDouble.roundToDouble()) {
      return asDouble.toInt().toString();
    }
    return asDouble.toString();
  }

  // Opens the Profile (Edit Profile) screen from the header avatar/name tap.
  void _openProfile() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => EditProfileScreen()));
  }

  // Handles the header gear icon tap.
  void _openSettings() {
    // TODO: No Settings screen exists yet in this app — destination needs
    // confirmation. Showing a safe placeholder instead of navigating.
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.t('home.settingsComingSoon'))),
    );
  }

  // Opens the Account Balance drill-down from the balance hero card.
  void _openAccountBalance() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const AccountBalanceScreen()));
  }

  // Opens the Active Orders drill-down from the summary metric card.
  void _openActiveOrders() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const OrdersScreen(filter: OrderStatusFilter.active),
      ),
    );
  }

  // Opens the Overdue Invoices drill-down from the summary metric card.
  void _openOverdueInvoices() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            const InvoicesScreen(filter: InvoiceStatusFilter.overdue),
      ),
    );
  }

  // Scanning in home page using QR code function: opens the Scan Stock
  // screen from the "Scan Fabric Availability" CTA.
  void _openScanStockScreen() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => ScanStockScreen()));
  }

  // Pushes a bottom-tab destination screen, then restores the Home tab as
  // selected once the user navigates back (tabs here are push-based, not
  // persistent, so Home is the natural resting state on return).
  Future<void> _openTabScreen(int tabIndex, Widget screen) async {
    setState(() => _selectedNavIndex = tabIndex);
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
    if (mounted) {
      setState(() => _selectedNavIndex = _navIndexHome);
    }
  }

  // Handles bottom tab bar taps and routes to the matching screen.
  void _handleBottomNavTap(int tabIndex) {
    switch (tabIndex) {
      case _navIndexHome:
        setState(() => _selectedNavIndex = _navIndexHome);
        break;
      case _navIndexOrders:
        _openTabScreen(_navIndexOrders, const OrdersScreen());
        break;
      case _navIndexSupport:
        _openTabScreen(_navIndexSupport, const SupportScreen());
        break;
      case _navIndexProfile:
        _openTabScreen(_navIndexProfile, EditProfileScreen());
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            HomeHeader(
              userName: kCurrentUserName,
              onAvatarTap: _openProfile,
              onSettingsTap: _openSettings,
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: refreshHomeDashboardData,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(AppSpacing.pageHorizontal),
                  child: ResponsiveMaxWidth(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildDashboardSection(),
                        const SizedBox(height: AppSpacing.pageHorizontal),
                        ScanFabricButton(
                          label: context.t('home.scanFabricAvailability'),
                          onTap: _openScanStockScreen,
                        ),
                        const SizedBox(height: AppSpacing.pageHorizontal),
                        AvailabilitySearchCard(
                          title: context.t('home.checkAvailability'),
                          hintText: context.t('home.enterCatalogueCode'),
                          helperText: context.t('home.checkAvailabilityHelper'),
                          controller: _catalogueCodeController,
                          onSearch: searchFabricAvailabilityByCatalogueCode,
                          isLoading:
                              _catalogueSearchState ==
                              _CatalogueSearchUiState.loading,
                          errorText: _catalogueSearchErrorText(),
                          resultText: _catalogueSearchResultText(),
                        ),
                        _buildCatalogueSelectionSection(),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            SafeArea(
              top: false,
              child: CustomBottomNav(
                currentIndex: _selectedNavIndex,
                onTap: _handleBottomNavTap,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Builds whatever belongs below the catalogue search box: nothing while
  // idle/loading/invalidInput/noResults/error/temporarilyUnavailable (those
  // states are already fully expressed by AvailabilitySearchCard's own
  // errorText/resultText); the suggestions list when a search returned
  // multiple groups and none is selected yet; otherwise the selected
  // group's variations (an exact match, or a suggestion the user tapped),
  // including the final stock-availability status once a variation is
  // picked.
  Widget _buildCatalogueSelectionSection() {
    final selectedGroup = _selectedCatalogueGroup;
    if (selectedGroup == null) {
      if (_catalogueSearchState == _CatalogueSearchUiState.suggestions) {
        return _CatalogueSuggestionsCard(
          key: const ValueKey('catalogue-suggestions'),
          groups: _catalogueGroups,
          onSelectGroup: _selectCatalogueGroup,
        );
      }
      return const SizedBox.shrink();
    }

    return _CatalogueVariationsCard(
      key: const ValueKey('catalogue-variations'),
      group: selectedGroup,
      showBackToSuggestions:
          _catalogueSearchState == _CatalogueSearchUiState.suggestions,
      onBack: _clearSelectedCatalogueGroup,
      selectedVariation: _selectedVariation,
      onSelectVariation: _selectVariation,
      isAvailabilityLoading:
          _checkAvailabilityState == _CheckAvailabilityUiState.loading,
      availabilityErrorText: _checkAvailabilityErrorText(),
      availabilityResultText: _checkAvailabilityResultText(),
    );
  }

  // Builds the Current Balance card (live ledger-entries API), the
  // active-orders/overdue-invoices section (still mock-backed), and the
  // Last Payment row (live Payments API) — each loads and switches between
  // its own loading/error/loaded states independently of the others; see
  // _loadCurrentBalance/_loadLastPayment.
  Widget _buildDashboardSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildCurrentBalanceSection(),
        const SizedBox(height: 12),
        if (_isDashboardLoading && _dashboardData == null)
          _buildMetricsLoadingSkeleton()
        else if (_dashboardError != null && _dashboardData == null)
          _buildDashboardErrorState()
        else
          _buildMetricsSummaryCards(_dashboardData!),
        const SizedBox(height: 12),
        _buildLastPaymentSection(),
      ],
    );
  }

  // Switches the Current Balance card between its loading/error/loaded
  // states. The non-loaded states render through _CurrentBalanceShell,
  // which reuses BalanceCard's exact outer chrome (navy gradient, wallet
  // icon, label styling) so the card never visually jumps once a live
  // result arrives — BalanceCard itself is untouched, matching
  // _LastPaymentShell's convention.
  Widget _buildCurrentBalanceSection() {
    switch (_currentBalanceState) {
      case _CurrentBalanceUiState.loading:
        return const _CurrentBalanceShell(
          key: ValueKey('current-balance-loading'),
          trailing: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
            ),
          ),
        );
      case _CurrentBalanceUiState.error:
        return _CurrentBalanceShell(
          key: const ValueKey('current-balance-error'),
          message: _currentBalanceErrorMessage(),
          onRetry: _loadCurrentBalance,
        );
      case _CurrentBalanceUiState.loaded:
        final result = _currentBalanceAmount!;
        return BalanceCard(
          amount: _formatCurrentBalanceAmount(result),
          onTap: _openAccountBalance,
        );
    }
  }

  Widget _buildMetricsSummaryCards(HomeDashboardData data) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MetricCard(
          icon: Icons.receipt_long_rounded,
          iconBoxColor: AppColors.darkTeal,
          backgroundColor: AppColors.mint,
          valueText: data.activeOrdersCount,
          subtitle: context.t('home.activeOrders'),
          contentColor: AppColors.darkTeal,
          onTap: _openActiveOrders,
        ),
        const SizedBox(height: 12),
        MetricCard(
          icon: Icons.request_quote_rounded,
          iconBoxColor: AppColors.darkRedBrown,
          backgroundColor: AppColors.peach,
          borderColor: AppColors.border,
          valueText: data.overdueInvoicesAmount,
          subtitle: context.t('home.overdueInvoices'),
          contentColor: AppColors.darkRedBrown,
          onTap: _openOverdueInvoices,
        ),
      ],
    );
  }

  // Switches the Last Payment row between its loading/empty/error/loaded
  // states. The non-loaded states render through _LastPaymentShell, which
  // reuses LastPaymentCard's exact outer chrome (icon, label, container
  // styling) so the row never visually jumps once a live result arrives —
  // LastPaymentCard itself is untouched, matching
  // AccountBalanceScreen's _QuickHistorySectionShell convention.
  Widget _buildLastPaymentSection() {
    switch (_lastPaymentState) {
      case _LastPaymentUiState.loading:
        return const _LastPaymentShell(
          key: ValueKey('last-payment-loading'),
          trailing: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        );
      case _LastPaymentUiState.empty:
        return _LastPaymentShell(
          key: const ValueKey('last-payment-empty'),
          message: context.t('lastPayment.empty'),
        );
      case _LastPaymentUiState.error:
        return _LastPaymentShell(
          key: const ValueKey('last-payment-error'),
          message: _lastPaymentErrorMessage(),
          onRetry: _loadLastPayment,
        );
      case _LastPaymentUiState.loaded:
        final entry = _lastPaymentEntry!;
        return LastPaymentCard(
          amount: _formatLastPaymentAmount(entry),
          date: formatMonthDay(entry.postingDate),
        );
    }
  }

  // Simple placeholder box shared by every dashboard-card skeleton (Current
  // Balance and the mock-backed Active Orders/Overdue Invoices cards).
  static Widget _skeletonBox(double height) {
    return Container(
      height: height,
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.border.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(8),
      ),
    );
  }

  // Simple placeholder skeleton shown while the (still mock-backed) Active
  // Orders/Overdue Invoices cards are first loading. Current Balance and
  // the Last Payment row below each have their own independent loading
  // shell.
  Widget _buildMetricsLoadingSkeleton() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _skeletonBox(72),
        const SizedBox(height: 12),
        _skeletonBox(72),
      ],
    );
  }

  // Error state with a retry action, shown when dashboard data fails to
  // load and no previously loaded data is available to fall back on.
  Widget _buildDashboardErrorState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color: AppColors.dangerRed,
            size: 28,
          ),
          const SizedBox(height: 8),
          Text(
            _dashboardError ?? context.t('home.unableToLoadDashboard'),
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.grayText),
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: retryLoadHomeDashboardData,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryNavy,
              foregroundColor: Colors.white,
            ),
            child: Text(context.t('common.retry')),
          ),
        ],
      ),
    );
  }
}

/// Catalogue search "no exact commonItemNo match" result: every group the
/// search returned, shown as a tappable suggestion so the user can pick one
/// to see its variations. Reuses [AvailabilitySearchCard]'s outer chrome
/// (surface color, border, radius, shadow) so this reads as part of the
/// same Check Availability card group rather than a visually unrelated
/// block.
class _CatalogueSuggestionsCard extends StatelessWidget {
  const _CatalogueSuggestionsCard({
    super.key,
    required this.groups,
    required this.onSelectGroup,
  });

  final List<BusinessCentralItemSearchGroup> groups;
  final ValueChanged<BusinessCentralItemSearchGroup> onSelectGroup;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: AppSpacing.pageHorizontal),
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.smallAll,
        border: Border.all(color: AppColors.border),
        boxShadow: AppShadows.standardCard,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.t('home.catalogueMatchingTitle'),
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1A1A1A),
            ),
          ),
          const SizedBox(height: 8),
          for (final group in groups)
            Material(
              key: ValueKey('catalogue-group-${group.commonItemNo}'),
              color: Colors.transparent,
              child: InkWell(
                onTap: () => onSelectGroup(group),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              context.t(
                                'home.catalogueGroupLabel',
                                params: {'code': group.commonItemNo},
                              ),
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF1A1A1A),
                              ),
                            ),
                            Text(
                              context.t(
                                'home.catalogueVariationCount',
                                params: {'count': '${group.variations.length}'},
                              ),
                              style: const TextStyle(
                                fontSize: 12.5,
                                color: AppColors.grayText,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(
                        Icons.chevron_right_rounded,
                        color: AppColors.grayText,
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A resolved catalogue group's variations — reached either from an exact
/// `commonItemNo` match or after the user taps a suggestion. Lets the user
/// pick one exact variation, then shows the final stock-availability status
/// (loading/success/not-found/error) for that variation, sourced from the
/// existing, unchanged [StockLookupService] contract — never from this
/// group's own [BusinessCentralItemSearchGroup.totalInventory], which is
/// only ever shown labeled as a group-level total.
class _CatalogueVariationsCard extends StatefulWidget {
  const _CatalogueVariationsCard({
    super.key,
    required this.group,
    required this.showBackToSuggestions,
    required this.onBack,
    required this.selectedVariation,
    required this.onSelectVariation,
    required this.isAvailabilityLoading,
    required this.availabilityErrorText,
    required this.availabilityResultText,
  });

  final BusinessCentralItemSearchGroup group;
  final bool showBackToSuggestions;
  final VoidCallback onBack;
  final BusinessCentralItemVariation? selectedVariation;
  final ValueChanged<BusinessCentralItemVariation> onSelectVariation;
  final bool isAvailabilityLoading;
  final String? availabilityErrorText;
  final String? availabilityResultText;

  @override
  State<_CatalogueVariationsCard> createState() =>
      _CatalogueVariationsCardState();
}

class _CatalogueVariationsCardState extends State<_CatalogueVariationsCard> {
  /// Whether the variation list (and the selected variation's availability
  /// status) is shown below the "Catalogue {code} / N variations" header.
  /// Purely a local visual toggle — tapping the header never touches
  /// catalogue search, stock lookup, or [widget.selectedVariation]; see
  /// [_toggleExpanded].
  bool _expanded = true;

  void _toggleExpanded() => setState(() => _expanded = !_expanded);

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: AppSpacing.pageHorizontal),
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.smallAll,
        border: Border.all(color: AppColors.border),
        boxShadow: AppShadows.standardCard,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.showBackToSuggestions)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: InkWell(
                onTap: widget.onBack,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.chevron_left_rounded,
                      size: 18,
                      color: AppColors.primaryNavy,
                    ),
                    Text(
                      context.t('home.catalogueMatchingTitle'),
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primaryNavy,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          // The only tap target that toggles [_expanded] — deliberately does
          // not call onSelectVariation, onBack, or any catalogue-search/
          // stock-lookup seam. Purely a local UI affordance.
          Material(
            color: Colors.transparent,
            child: InkWell(
              key: const ValueKey('catalogue-variations-header'),
              onTap: _toggleExpanded,
              borderRadius: AppRadius.smallAll,
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          context.t(
                            'home.catalogueGroupLabel',
                            params: {'code': widget.group.commonItemNo},
                          ),
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1A1A1A),
                          ),
                        ),
                        Text(
                          context.t(
                            'home.catalogueVariationCount',
                            params: {
                              'count': '${widget.group.variations.length}',
                            },
                          ),
                          style: const TextStyle(
                            fontSize: 12.5,
                            color: AppColors.grayText,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    _expanded
                        ? Icons.expand_more_rounded
                        : Icons.chevron_right_rounded,
                    color: AppColors.grayText,
                  ),
                ],
              ),
            ),
          ),
          if (_expanded) ...[
            const SizedBox(height: 4),
            Text(
              context.t('home.catalogueSelectVariation', params: {}),
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1A1A1A),
              ),
            ),
            const SizedBox(height: 6),
            for (final variation in widget.group.variations)
              _VariationRow(
                key: ValueKey('variation-${variation.itemNo}'),
                variation: variation,
                selected: widget.selectedVariation?.itemNo == variation.itemNo,
                onTap: () => widget.onSelectVariation(variation),
              ),
            if (widget.selectedVariation != null) ...[
              const SizedBox(height: 8),
              if (widget.isAvailabilityLoading)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else if (widget.availabilityErrorText != null)
                Text(
                  widget.availabilityErrorText!,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: AppColors.dangerRed,
                  ),
                )
              else if (widget.availabilityResultText != null)
                Text(
                  widget.availabilityResultText!,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.darkTeal,
                  ),
                ),
            ],
          ],
        ],
      ),
    );
  }
}

/// One tappable variation row inside [_CatalogueVariationsCard] — shows the
/// exact `itemNo` the final stock lookup will be sent, plus whatever
/// optional descriptive fields the grouped response actually returned (see
/// [BusinessCentralItemVariation]'s doc comment for why those are
/// optional). Highlighted when [selected].
class _VariationRow extends StatelessWidget {
  const _VariationRow({
    super.key,
    required this.variation,
    required this.selected,
    required this.onTap,
  });

  final BusinessCentralItemVariation variation;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final description = variation.description;
    final unit = variation.baseUnitOfMeasure;
    final subtitleParts = [
      if (description != null && description.isNotEmpty) description,
      if (unit != null && unit.isNotEmpty) unit,
    ];

    return Material(
      color: selected
          ? AppColors.primaryNavy.withValues(alpha: 0.06)
          : Colors.transparent,
      borderRadius: AppRadius.smallAll,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.smallAll,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      variation.itemNo,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: selected
                            ? FontWeight.w700
                            : FontWeight.w500,
                        color: const Color(0xFF1A1A1A),
                      ),
                    ),
                    if (subtitleParts.isNotEmpty)
                      Text(
                        subtitleParts.join(' · '),
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.grayText,
                        ),
                      ),
                  ],
                ),
              ),
              if (selected)
                const Icon(
                  Icons.check_circle_rounded,
                  color: AppColors.primaryNavy,
                  size: 18,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Last Payment row placeholder for the loading/empty/error states, reusing
/// [LastPaymentCard]'s exact outer chrome (icon, label, container styling)
/// so the row never visually jumps once a live result arrives.
/// [LastPaymentCard] itself is untouched — this is a sibling widget shown in
/// its place, mirroring `_QuickHistorySectionShell`'s convention in
/// `account_balance_screen.dart`.
class _LastPaymentShell extends StatelessWidget {
  const _LastPaymentShell({
    super.key,
    this.trailing,
    this.message,
    this.onRetry,
  });

  /// Shown at the row's trailing edge (e.g. a small loading spinner) in
  /// place of the amount/date pair.
  final Widget? trailing;

  /// Empty/error copy shown under the "Last Payment" label in place of the
  /// amount.
  final String? message;

  /// When set (error state), shows a retry action next to [message].
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 72),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.smallAll,
        border: Border.all(color: AppColors.border),
        boxShadow: AppShadows.standardCard,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: const Color(0xFFEFEFF2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.account_balance_wallet_outlined,
              color: AppColors.grayText,
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  context.t('lastPayment.label'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: AppColors.grayText,
                  ),
                ),
                if (message != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    message!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.grayText,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 8), trailing!],
          if (onRetry != null) ...[
            const SizedBox(width: 4),
            TextButton(
              onPressed: onRetry,
              child: Text(context.t('common.retry')),
            ),
          ],
        ],
      ),
    );
  }
}

/// Current Balance card placeholder for the loading/error states, reusing
/// [BalanceCard]'s exact outer chrome (navy gradient, wallet icon, label
/// styling) so the card never visually jumps once a live result arrives.
/// [BalanceCard] itself is untouched — this is a sibling widget shown in its
/// place, mirroring [_LastPaymentShell]'s convention.
class _CurrentBalanceShell extends StatelessWidget {
  const _CurrentBalanceShell({
    super.key,
    this.trailing,
    this.message,
    this.onRetry,
  });

  /// Shown next to the label (e.g. a small loading spinner) while no
  /// message is shown.
  final Widget? trailing;

  /// Error copy shown under the "CURRENT BALANCE" label in place of the
  /// amount.
  final String? message;

  /// When set (error state), shows a retry action next to [message].
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(8);
    return Container(
      constraints: const BoxConstraints(minHeight: 135),
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.gradientNavyStart, AppColors.gradientNavyEnd],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.primaryNavy,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.account_balance_wallet_rounded,
              color: Colors.white,
              size: 18,
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.t('balanceCard.label'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.2,
                  color: Color(0xFFB7B8E3),
                ),
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ?trailing,
                  if (message != null)
                    Flexible(
                      child: Text(
                        message!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  if (onRetry != null)
                    TextButton(
                      onPressed: onRetry,
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white,
                      ),
                      child: Text(context.t('common.retry')),
                    ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}
