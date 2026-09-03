import 'dart:async';

import 'package:flutter/material.dart';

import '../config/demo_config.dart';
import '../localization/translations.dart';
import '../models/business_central/business_central_item_search_group.dart';
import '../models/home_dashboard_data.dart';
import '../services/api_stock_lookup_service.dart';
import '../services/auth_service.dart';
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
/// the dashboard (balance/orders/invoices) so a customer-details failure
/// never blanks out those sections, and vice versa — mirrors
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
    this.dashboardService,
    this.lastPaymentSource,
    this.currentBalanceSource,
    this.checkAvailabilityService,
    this.catalogueSearchService,
    this.authService,
  });

  /// Active Orders / Overdue Invoices metrics seam. Defaults (lazily, in
  /// State) to [ApiHomeDashboardService] — the live Business Central
  /// customer-details endpoint; overridable so tests can inject a fake
  /// instead of a real network call. The owned production default is
  /// closed on [State.dispose], mirroring [checkAvailabilityService]'s
  /// exact ownership-disposal pattern.
  final HomeDashboardService? dashboardService;

  /// Last Payment data seam. Defaults (lazily, in State) to
  /// [CustomerDetailsLastPaymentDataSource] — the customer's own
  /// `customer_details` snapshot's `lastPaymentAmount`/`lastPaymentDate`
  /// fields (product decision, 2026-09-03); overridable so tests can inject
  /// a fake.
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

  /// Authenticated-username display seam — used only to read the current
  /// session for [HomeHeader]'s display, never to decide authentication
  /// (see [AuthService.currentSession]'s doc comment). Left `null` here and
  /// resolved lazily in [_HomeScreenState.initState], mirroring
  /// [checkAvailabilityService]'s exact ownership-disposal pattern.
  final AuthService? authService;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  /// Dashboard metrics seam actually used by [loadHomeDashboardData] —
  /// resolved in [initState]; see [HomeScreen.dashboardService].
  late final HomeDashboardService _dashboardService;

  /// Set only when this State created its own [ApiHomeDashboardService]
  /// (no [HomeScreen.dashboardService] was injected) — the only instance
  /// this screen ever closes.
  ApiHomeDashboardService? _ownedDashboardService;

  final TextEditingController _catalogueCodeController =
      TextEditingController();

  /// Last Payment data seam actually used by [_loadLastPayment] — resolved
  /// in [initState], mirroring [HomeScreen.dashboardService]'s exact
  /// ownership-disposal pattern.
  late final LastPaymentDataSource _lastPaymentSource;

  /// Set only when this State created its own
  /// [CustomerDetailsLastPaymentDataSource] (no [HomeScreen.lastPaymentSource]
  /// was injected) — the only instance this screen ever closes.
  CustomerDetailsLastPaymentDataSource? _ownedLastPaymentSource;

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

  /// Authenticated-username display seam actually used by [_loadUsername] —
  /// resolved in [initState], mirroring [_checkAvailabilityService]'s exact
  /// pattern; see [HomeScreen.authService]'s doc comment for why.
  late final AuthService _authService;

  /// Set only when this State created its own [AuthService] (no
  /// [HomeScreen.authService] was injected) — the only instance this screen
  /// ever closes.
  AuthService? _ownedAuthService;

  /// The authenticated user's username, loaded from the persisted session
  /// for display only (see [AuthService.currentSession]'s doc comment) —
  /// `null` before that load completes or when no session/username could be
  /// read, in which case [HomeHeader] falls back to a safe generic label
  /// rather than a fabricated name.
  String? _username;

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

  // Last Payment row state — loaded live from customer_details.
  _LastPaymentUiState _lastPaymentState = _LastPaymentUiState.loading;
  LastPaymentSummary? _lastPaymentEntry;

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

  /// Per-variation inline availability lookup state, keyed by the variation's
  /// exact `itemNo`. An entry exists only after the user taps that row's
  /// "Check" button; every entry is looked up and displayed independently on
  /// its own row (no shared bottom-of-card result). Cleared wholesale
  /// whenever a new catalogue search runs or a different group is selected.
  final Map<String, _VariationAvailability> _variationAvailability = {};

  /// `itemNo`s with an inline lookup currently in flight — a per-row
  /// re-entrancy guard (a rapid double-tap of the same row's "Check"
  /// button). Independent per variation, so checking one row never cancels
  /// or blocks another.
  final Set<String> _variationLookupsInFlight = {};

  /// Bumped whenever a new catalogue search runs or a different group is
  /// selected — the "epoch" every in-flight [_checkVariation] captures, so a
  /// slow inventory response that lands after the user has moved on is
  /// discarded instead of corrupting fresher state. Not bumped per row:
  /// concurrent per-variation lookups within the same group share an epoch.
  int _checkAvailabilityGeneration = 0;

  /// Debounce timer for the as-you-type catalogue suggestions under the
  /// search field.
  Timer? _suggestDebounce;

  /// Current as-you-type suggestions shown under the search field. Best
  /// effort: a failed or superseded suggestion fetch leaves this unchanged
  /// (or empty) and never shows an error — the explicit Search button still
  /// surfaces real catalogue-search errors.
  List<AvailabilitySuggestion> _catalogueSuggestions = const [];

  /// Bumped on every debounced suggestion fetch so a slow one can't
  /// overwrite fresher suggestions.
  int _suggestGeneration = 0;

  @override
  void initState() {
    super.initState();
    final injectedDashboardService = widget.dashboardService;
    if (injectedDashboardService != null) {
      _dashboardService = injectedDashboardService;
    } else {
      final owned = ApiHomeDashboardService();
      _ownedDashboardService = owned;
      _dashboardService = owned;
    }
    final injectedLastPaymentSource = widget.lastPaymentSource;
    if (injectedLastPaymentSource != null) {
      _lastPaymentSource = injectedLastPaymentSource;
    } else {
      final owned = CustomerDetailsLastPaymentDataSource();
      _ownedLastPaymentSource = owned;
      _lastPaymentSource = owned;
    }
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
    final injectedAuthService = widget.authService;
    if (injectedAuthService != null) {
      _authService = injectedAuthService;
    } else {
      final owned = AuthService.production();
      _ownedAuthService = owned;
      _authService = owned;
    }
    _catalogueCodeController.addListener(_onCatalogueCodeChanged);
    _loadUsername();
  }

  @override
  void dispose() {
    _suggestDebounce?.cancel();
    _catalogueCodeController.removeListener(_onCatalogueCodeChanged);
    _catalogueCodeController.dispose();
    // Bumping every generation here means an in-flight catalogue search,
    // suggestion fetch, or inline stock lookup's continuation recognizes
    // itself as stale (see [searchFabricAvailabilityByCatalogueCode]/
    // [_fetchCatalogueSuggestions]/[_checkVariation]) and never calls
    // setState after dispose.
    _catalogueSearchGeneration++;
    _checkAvailabilityGeneration++;
    _suggestGeneration++;
    _ownedCheckAvailabilityService?.close();
    _ownedCatalogueSearchService?.close();
    _ownedAuthService?.close();
    _ownedDashboardService?.close();
    _ownedLastPaymentSource?.close();
    super.dispose();
  }

  /// Loads the Home header's display username from the currently persisted
  /// session (display only — never used to decide authentication; see
  /// [AuthService.currentSession]'s doc comment), mirroring
  /// `EditProfileScreen._loadIdentity`'s exact pattern. A missing/unreadable
  /// session leaves [_username] `null`, which [HomeHeader] renders as a safe
  /// generic label rather than a fabricated name.
  Future<void> _loadUsername() async {
    final session = await _authService.currentSession();
    if (!mounted) return;
    setState(() => _username = session?.username);
  }

  /// Loads the Active Orders / Overdue Invoices metrics live from the
  /// customer-details API (see [ApiHomeDashboardService]). Any failure maps
  /// to the dashboard error state with a retry — never fabricated numbers.
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
  /// Fans out to the live Active Orders/Overdue Invoices summary and the
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
    } catch (error) {
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

  /// Loads the most recent payment from `customer_details`'
  /// `lastPaymentAmount`/`lastPaymentDate` fields for the Last Payment row
  /// (see [CustomerDetailsLastPaymentDataSource]). Independent of
  /// [loadHomeDashboardData]/[refreshHomeDashboardData], so a
  /// customer-details failure never blanks out Balance/Orders/Invoices, and
  /// vice versa. Also serves as the retry action after an error.
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
  /// confirmed display rule. `customer_details` carries no currency field
  /// at all (unlike the Payments-list endpoint this row used to source
  /// from), so this always renders the plain figure via
  /// [formatCurrencyOrUnknown] — no prefix, never a guessed `$`/code.
  String _formatLastPaymentAmount(LastPaymentSummary entry) {
    return formatCurrencyOrUnknown(entry.amount.abs(), currencyCode: null);
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
  /// else shows every returned group as a suggestion. Only when the user
  /// taps a variation row's inline "Check" button does [_checkVariation]
  /// call the existing, unchanged [StockLookupService] exact-`itemNo`
  /// lookup — see that method.
  ///
  /// Starting a new search always clears every per-variation result left
  /// over from a previous one, and bumps both [_catalogueSearchGeneration]
  /// and [_checkAvailabilityGeneration] so a slow in-flight request from the
  /// previous query can never land after this one starts.
  Future<void> searchFabricAvailabilityByCatalogueCode() async {
    final rawInput = _catalogueCodeController.text;
    final trimmedCode = rawInput.trim();

    if (trimmedCode.isEmpty) {
      _catalogueSearchGeneration++;
      _checkAvailabilityGeneration++;
      _suggestDebounce?.cancel();
      setState(() {
        _catalogueSearchState = _CatalogueSearchUiState.invalidInput;
        _catalogueGroups = const [];
        _selectedCatalogueGroup = null;
        _variationAvailability.clear();
        _catalogueSuggestions = const [];
      });
      return;
    }

    // Duplicate-submission guard: ignored while a search is already in
    // flight, whether triggered again by the button or the keyboard.
    if (_isCatalogueSearching) return;
    _isCatalogueSearching = true;
    // Supersede any in-flight per-variation lookup from a previous query
    // too — its continuation (see [_checkVariation]) recognizes the bumped
    // epoch and never overwrites this fresh search's state.
    _checkAvailabilityGeneration++;
    _suggestDebounce?.cancel();
    final requestId = ++_catalogueSearchGeneration;

    setState(() {
      _catalogueSearchState = _CatalogueSearchUiState.loading;
      _catalogueGroups = const [];
      _selectedCatalogueGroup = null;
      _variationAvailability.clear();
      _catalogueSuggestions = const [];
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
      _variationAvailability.clear();
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
      _variationAvailability.clear();
    });
  }

  /// Controller listener: (re)schedules a debounced catalogue-suggestion
  /// fetch as the user types. Skips fetching while there's nothing useful to
  /// suggest — fewer than 2 characters, or the text already equals the
  /// resolved group's `commonItemNo` (the dropdown would just repeat what's
  /// already shown below).
  void _onCatalogueCodeChanged() {
    final query = _catalogueCodeController.text.trim();
    _suggestDebounce?.cancel();
    final resolved = _selectedCatalogueGroup?.commonItemNo.trim().toLowerCase();
    if (query.length < 2 || query.toLowerCase() == resolved) {
      if (_catalogueSuggestions.isNotEmpty) {
        setState(() => _catalogueSuggestions = const []);
      }
      return;
    }
    _suggestDebounce = Timer(
      const Duration(milliseconds: 300),
      () => unawaited(_fetchCatalogueSuggestions(query)),
    );
  }

  /// Best-effort as-you-type suggestions: runs the same catalogue search the
  /// Search button uses, but only ever populates the dropdown from an exact
  /// match or a suggestions result — every failure/no-result/session
  /// outcome just clears the dropdown silently (the button path still
  /// reports real errors). Superseded by [_suggestGeneration] so a slow
  /// response can't overwrite fresher suggestions.
  Future<void> _fetchCatalogueSuggestions(String query) async {
    final generation = ++_suggestGeneration;
    ItemCatalogueSearchResult result;
    try {
      result = await _catalogueSearchService.search(query);
    } catch (_) {
      return;
    }
    if (!mounted || generation != _suggestGeneration) return;
    // The user kept typing (or cleared the field) after this fetch started.
    if (_catalogueCodeController.text.trim() != query) return;

    final groups = switch (result) {
      ItemCatalogueExactMatch(:final group) => [group],
      ItemCatalogueSuggestions(:final groups) => groups,
      _ => const <BusinessCentralItemSearchGroup>[],
    };
    setState(() {
      _catalogueSuggestions = [
        for (final group in groups)
          AvailabilitySuggestion(
            code: group.commonItemNo,
            subtitle: context.t(
              'home.catalogueVariationCount',
              params: {'count': '${group.variations.length}'},
            ),
          ),
      ];
    });
  }

  /// Fills the field with a tapped suggestion's code and runs the full
  /// catalogue search for it. Cancels/stales any pending suggestion fetch so
  /// the dropdown doesn't reappear over the resolved variations.
  void _onSuggestionSelected(AvailabilitySuggestion suggestion) {
    _suggestDebounce?.cancel();
    _suggestGeneration++;
    _catalogueCodeController.text = suggestion.code;
    _catalogueCodeController.selection = TextSelection.collapsed(
      offset: suggestion.code.length,
    );
    setState(() => _catalogueSuggestions = const []);
    unawaited(searchFabricAvailabilityByCatalogueCode());
  }

  /// Runs the unchanged exact-`itemNo` stock lookup for one variation the
  /// user tapped "Check" on — the same [StockLookupService] contract
  /// `ScanStockScreen` uses, never a second, duplicated inventory-fetch/
  /// filter/aggregate path. The result is stored per `itemNo` in
  /// [_variationAvailability] and rendered inline on that row; other rows
  /// are unaffected. Re-tapping a row after its result shows starts a fresh
  /// lookup (retry).
  Future<void> _checkVariation(BusinessCentralItemVariation variation) async {
    final itemNo = variation.itemNo;
    // Per-row re-entrancy guard: a rapid double-tap on the same row's
    // button. Other rows are independent.
    if (_variationLookupsInFlight.contains(itemNo)) return;
    _variationLookupsInFlight.add(itemNo);
    // Captured, not bumped: a concurrent check of another row in the same
    // group must not invalidate this one. A new catalogue search / group
    // selection bumps the epoch and clears the map.
    final epoch = _checkAvailabilityGeneration;

    setState(() {
      _variationAvailability[itemNo] = const _VariationAvailability.loading();
    });

    StockLookupResult result;
    try {
      result = await _checkAvailabilityService.lookup(itemNo);
    } catch (error) {
      // A truly unexpected exception (an implementation bug) must not crash
      // the screen; treat it like any other unexpected failure.
      debugPrint('Check Availability lookup threw unexpectedly: $error');
      result = StockLookupUnexpectedFailure(itemNo);
    }

    _variationLookupsInFlight.remove(itemNo);
    // Discards a response that arrived after a new catalogue search / group
    // selection superseded this group (or after dispose bumped the epoch).
    if (!mounted || epoch != _checkAvailabilityGeneration) return;

    if (result is StockLookupSessionExpired) {
      // A real adapter hands off to the session coordinator (which
      // navigates to Login) before ever returning this — matching
      // SessionExpiredException elsewhere in the app, there is nothing
      // controlled to show here.
      setState(() => _variationAvailability.remove(itemNo));
      return;
    }

    setState(() {
      _variationAvailability[itemNo] = _VariationAvailability.resolved(
        _stageForCheckAvailability(result),
        result,
      );
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

  // Opens the Profile (Edit Profile) screen from the header avatar/name tap.
  void _openProfile() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => EditProfileScreen()));
  }

  // Handles the header gear icon tap.
  void _openSettings() {
    // confirmation. Showing a safe placeholder instead of navigating.
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.t('home.settingsComingSoon'))),
    );
  }

  // Opens the Account Balance drill-down from the balance hero card,
  // passing along the already-loaded Current Balance's ledger-derived
  // currency so Account Balance never has to re-fetch ledger entries or
  // fall back to a region-inferred currency of its own — see
  // AccountBalanceScreen's class-level doc comment. `null` when Current
  // Balance hasn't resolved a currency yet (still loading, errored, or a
  // blank Currency_Code), in which case Account Balance shows its own
  // existing "?" unknown-currency fallback.
  void _openAccountBalance() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AccountBalanceScreen(
          currencyCode: _currentBalanceAmount?.currencyCode,
        ),
      ),
    );
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
              userName: _username ?? context.t('home.defaultUserLabel'),
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
                          suggestions: _catalogueSuggestions,
                          onSuggestionSelected: _onSuggestionSelected,
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
      variationAvailability: _variationAvailability,
      onCheckVariation: _checkVariation,
    );
  }

  // Builds the Current Balance card (live ledger-entries API), the
  // active-orders/overdue-invoices section (live customer-details API), and
  // the Last Payment row (live customer-details API) — each loads and
  // switches between its own loading/error/loaded states independently of
  // the others; see _loadCurrentBalance/_loadLastPayment.
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
        final date = entry.date;
        return LastPaymentCard(
          amount: _formatLastPaymentAmount(entry),
          // customer_details can report an amount with no accompanying
          // date — shown as an empty date string rather than a fabricated
          // one; the amount alone is still real, confirmed data.
          date: date == null ? '' : formatMonthDay(date),
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
/// `commonItemNo` match or after the user taps a suggestion. Every variation
/// row carries its own inline "Check" button that runs the unchanged
/// exact-`itemNo` [StockLookupService] lookup and shows a single combined
/// availability status right on that row — independently of the other rows,
/// and never from this group's own
/// [BusinessCentralItemSearchGroup.totalInventory].
class _CatalogueVariationsCard extends StatefulWidget {
  const _CatalogueVariationsCard({
    super.key,
    required this.group,
    required this.showBackToSuggestions,
    required this.onBack,
    required this.variationAvailability,
    required this.onCheckVariation,
  });

  final BusinessCentralItemSearchGroup group;
  final bool showBackToSuggestions;
  final VoidCallback onBack;

  /// Per-`itemNo` inline lookup state, owned by `_HomeScreenState`. A missing
  /// entry means that row hasn't been checked yet.
  final Map<String, _VariationAvailability> variationAvailability;

  /// Runs (or retries) the inline availability lookup for one variation.
  final ValueChanged<BusinessCentralItemVariation> onCheckVariation;

  @override
  State<_CatalogueVariationsCard> createState() =>
      _CatalogueVariationsCardState();
}

class _CatalogueVariationsCardState extends State<_CatalogueVariationsCard> {
  /// Whether the variation list is shown below the "Catalogue {code} / N
  /// variations" header. Purely a local visual toggle — tapping the header
  /// never touches catalogue search or any inline stock lookup; see
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
          // not call onCheckVariation, onBack, or any catalogue-search/
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
                availability:
                    widget.variationAvailability[variation.itemNo],
                onCheck: () => widget.onCheckVariation(variation),
              ),
          ],
        ],
      ),
    );
  }
}

/// One variation's inline availability lookup state, owned by
/// `_HomeScreenState` and passed down per row.
class _VariationAvailability {
  const _VariationAvailability.loading()
    : state = _CheckAvailabilityUiState.loading,
      result = null;

  const _VariationAvailability.resolved(this.state, this.result);

  final _CheckAvailabilityUiState state;
  final StockLookupResult? result;
}

/// One variation row inside [_CatalogueVariationsCard]: the exact `itemNo`
/// (plus any optional descriptive fields the grouped response returned) on
/// the left, and an inline "Check" button that resolves to a single combined
/// availability status — green (in stock), traffic-light yellow (low →
/// "contact support"), or red (out of stock) — shown full-width just below
/// the row. Never renders the underlying remaining quantity; other rows are
/// unaffected while this one loads.
class _VariationRow extends StatelessWidget {
  const _VariationRow({
    super.key,
    required this.variation,
    required this.availability,
    required this.onCheck,
  });

  final BusinessCentralItemVariation variation;
  final _VariationAvailability? availability;
  final VoidCallback onCheck;

  Widget _checkButton(BuildContext context, {bool retry = false}) {
    return OutlinedButton(
      key: ValueKey('variation-check-${variation.itemNo}'),
      onPressed: onCheck,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 34),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        foregroundColor: AppColors.primaryNavy,
        side: const BorderSide(color: AppColors.primaryNavy),
        textStyle: const TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
        ),
      ),
      child: Text(
        context.t(retry ? 'common.retry' : 'home.checkVariationAction'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final description = variation.description;
    final unit = variation.baseUnitOfMeasure;
    final subtitleParts = [
      if (description != null && description.isNotEmpty) description,
      if (unit != null && unit.isNotEmpty) unit,
    ];

    final entry = availability;
    final state = entry?.state;
    final result = entry?.result;

    Widget? inlineAction;
    Widget? belowLine;

    if (entry == null || state == _CheckAvailabilityUiState.idle) {
      inlineAction = _checkButton(context);
    } else if (state == _CheckAvailabilityUiState.loading) {
      inlineAction = SizedBox(
        key: ValueKey('variation-checking-${variation.itemNo}'),
        width: 18,
        height: 18,
        child: const CircularProgressIndicator(strokeWidth: 2),
      );
    } else if (state == _CheckAvailabilityUiState.success &&
        result is StockLookupSuccess) {
      belowLine = _StockStatusPill(
        level: result.combinedAvailabilityLevel,
        expectedRestockDate: result.expectedRestockDate,
      );
    } else if (state == _CheckAvailabilityUiState.notFound) {
      // No open inventory rows for this exact itemNo — effectively out of
      // stock (still no figure shown), but incoming stock already on a
      // purchase order still surfaces its expected receipt date.
      belowLine = _StockStatusPill(
        level: StockAvailabilityLevel.outOfStock,
        expectedRestockDate: result is StockLookupNotFound
            ? result.expectedRestockDate
            : null,
      );
    } else {
      // retryableFailure / temporarilyUnavailable / invalidInput
      inlineAction = _checkButton(context, retry: true);
      belowLine = Text(
        state == _CheckAvailabilityUiState.temporarilyUnavailable
            ? context.t('home.checkAvailabilityUnavailable')
            : context.t('home.catalogueLookupError'),
        key: ValueKey('variation-error-${variation.itemNo}'),
        style: const TextStyle(fontSize: 12, color: AppColors.dangerRed),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      variation.itemNo,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1A1A1A),
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
              if (inlineAction != null) ...[
                const SizedBox(width: 8),
                inlineAction,
              ],
            ],
          ),
          if (belowLine != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: belowLine,
            ),
        ],
      ),
    );
  }
}

/// The single combined availability status shown under a checked variation
/// row — one full-width coloured pill, never a per-location breakdown and
/// never the underlying quantity. Colours come from the dedicated
/// `AppColors.stock*` tokens (forest green / traffic-light yellow / red).
class _StockStatusPill extends StatelessWidget {
  const _StockStatusPill({required this.level, this.expectedRestockDate});

  final StockAvailabilityLevel level;

  /// The earliest purchase-order expected-receipt date after the lookup
  /// date, fed by `StockLookupSuccess.expectedRestockDate` /
  /// `StockLookupNotFound.expectedRestockDate` — shown beside an
  /// out-of-stock status as "stock expected by this date"; `null` when no
  /// incoming stock is on order.
  final DateTime? expectedRestockDate;

  @override
  Widget build(BuildContext context) {
    final (Color bg, Color fg, String keySuffix, String label) = switch (level) {
      StockAvailabilityLevel.available => (
        AppColors.stockAvailableBg,
        AppColors.stockAvailableText,
        'available',
        context.t('common.available'),
      ),
      StockAvailabilityLevel.low => (
        AppColors.stockLowBg,
        AppColors.stockLowText,
        'low',
        context.t('common.contactSupportForInquiries'),
      ),
      StockAvailabilityLevel.outOfStock => (
        AppColors.stockOutBg,
        AppColors.stockOutText,
        'out',
        context.t('home.stockOutOfStock'),
      ),
    };
    final restockDate = expectedRestockDate;

    return Container(
      key: ValueKey('variation-status-$keySuffix'),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: AppRadius.smallAll,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: fg,
            ),
          ),
          if (restockDate != null)
            Text(
              context.t(
                'home.stockExpectedBy',
                params: {
                  'date': MaterialLocalizations.of(
                    context,
                  ).formatMediumDate(restockDate),
                },
              ),
              key: const ValueKey('variation-restock-date'),
              style: TextStyle(fontSize: 12, color: fg),
            ),
        ],
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
