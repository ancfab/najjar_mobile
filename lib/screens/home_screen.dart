import 'package:flutter/material.dart';

import '../data/mock_user.dart';
import '../models/catalogue_lookup_result.dart';
import '../models/home_dashboard_data.dart';
import '../services/catalogue_lookup_service.dart';
import '../services/home_dashboard_service.dart';
import '../theme/app_colors.dart';
import '../utils/responsive.dart';
import '../widgets/availability_search_card.dart';
import '../widgets/balance_card.dart';
import '../widgets/custom_bottom_nav.dart';
import '../widgets/home_header.dart';
import '../widgets/last_payment_card.dart';
import '../widgets/metric_card.dart';
import '../widgets/scan_fabric_button.dart';
import 'account_balance_screen.dart';
import 'invoices_screen.dart';
import 'orders_screen.dart';
import 'profile_screen.dart';
import 'scan_stock_screen.dart';
import 'support_screen.dart';

// Bottom tab bar indexes, kept in one place so they stay in sync with the
// tab order rendered by CustomBottomNav.
const int _navIndexHome = 0;
const int _navIndexOrders = 1;
const int _navIndexSupport = 2;
const int _navIndexProfile = 3;

/// UI state for the Check Availability catalogue lookup card.
enum _CatalogueLookupUiState { idle, loading, error, empty, success }

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final HomeDashboardService _dashboardService = const HomeDashboardService();
  final CatalogueLookupService _catalogueLookupService =
      const CatalogueLookupService();
  final TextEditingController _catalogueCodeController =
      TextEditingController();

  int _selectedNavIndex = _navIndexHome;

  // Home dashboard summary state (balance, orders, invoices, last payment).
  HomeDashboardData? _dashboardData;
  bool _isDashboardLoading = true;
  String? _dashboardError;

  // Check Availability catalogue lookup state.
  _CatalogueLookupUiState _catalogueUiState = _CatalogueLookupUiState.idle;
  String? _catalogueMessage;

  @override
  void initState() {
    super.initState();
    loadHomeDashboardData();
  }

  @override
  void dispose() {
    _catalogueCodeController.dispose();
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
        _dashboardError = 'Unable to load dashboard data.';
        _isDashboardLoading = false;
      });
    }
  }

  /// Refreshes Home dashboard data when user pulls down on the Home screen.
  Future<void> refreshHomeDashboardData() async {
    try {
      final data = await _dashboardService.fetchHomeDashboardData();
      if (!mounted) return;
      setState(() {
        _dashboardData = data;
        _dashboardError = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _dashboardError = 'Unable to refresh dashboard data.');
    }
  }

  /// Retries loading Home dashboard data after an error.
  Future<void> retryLoadHomeDashboardData() async {
    await loadHomeDashboardData();
  }

  /// Validates that the catalogue code input is not empty.
  bool validateCatalogueCodeInput(String input) {
    return input.trim().isNotEmpty;
  }

  /// Looks up fabric availability from the Home screen using catalogue code.
  Future<void> searchFabricAvailabilityByCatalogueCode() async {
    final catalogueCode = _catalogueCodeController.text;
    if (!validateCatalogueCodeInput(catalogueCode)) {
      setState(() {
        _catalogueUiState = _CatalogueLookupUiState.error;
        _catalogueMessage = 'Please enter a catalogue code.';
      });
      return;
    }

    setState(() {
      _catalogueUiState = _CatalogueLookupUiState.loading;
      _catalogueMessage = null;
    });

    try {
      final result = await _catalogueLookupService
          .searchFabricAvailabilityByCatalogueCode(catalogueCode);
      handleCatalogueLookupResult(result);
    } catch (_) {
      showCatalogueLookupError();
    }
  }

  /// Updates the catalogue lookup UI state from a successful service call.
  void handleCatalogueLookupResult(CatalogueLookupResult result) {
    if (!mounted) return;
    setState(() {
      if (result.status == CatalogueLookupStatus.success) {
        _catalogueUiState = _CatalogueLookupUiState.success;
        _catalogueMessage =
            '${result.availableQuantity} yd available at '
            '${result.warehouseName}.';
      } else {
        _catalogueUiState = _CatalogueLookupUiState.empty;
        _catalogueMessage =
            'No availability found for "${result.catalogueCode}".';
      }
    });
  }

  /// Shows an error state when the catalogue lookup call fails.
  void showCatalogueLookupError() {
    if (!mounted) return;
    setState(() {
      _catalogueUiState = _CatalogueLookupUiState.error;
      _catalogueMessage = 'Something went wrong. Please try again.';
    });
  }

  // Opens the Profile screen from the header avatar/name tap.
  void _openProfile() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const ProfileScreen(userName: kCurrentUserName),
      ),
    );
  }

  // Handles the header gear icon tap.
  void _openSettings() {
    // TODO: No Settings screen exists yet in this app — destination needs
    // confirmation. Showing a safe placeholder instead of navigating.
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Settings screen coming soon')),
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
    ).push(MaterialPageRoute(builder: (_) => const ScanStockScreen()));
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
        _openTabScreen(
          _navIndexProfile,
          const ProfileScreen(userName: kCurrentUserName),
        );
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
                  padding: const EdgeInsets.all(16),
                  child: ResponsiveMaxWidth(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildDashboardSection(),
                        const SizedBox(height: 16),
                        ScanFabricButton(
                          label: 'Scan Fabric Availability',
                          onTap: _openScanStockScreen,
                        ),
                        const SizedBox(height: 16),
                        AvailabilitySearchCard(
                          title: 'Check Availability',
                          hintText: 'Enter Catalogue Code',
                          helperText:
                              'Quickly check availability across all warehouses.',
                          controller: _catalogueCodeController,
                          onSearch: searchFabricAvailabilityByCatalogueCode,
                          isLoading:
                              _catalogueUiState ==
                              _CatalogueLookupUiState.loading,
                          errorText:
                              _catalogueUiState == _CatalogueLookupUiState.error
                              ? _catalogueMessage
                              : null,
                          resultText:
                              (_catalogueUiState ==
                                      _CatalogueLookupUiState.success ||
                                  _catalogueUiState ==
                                      _CatalogueLookupUiState.empty)
                              ? _catalogueMessage
                              : null,
                        ),
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

  // Builds the balance/active-orders/overdue-invoices/last-payment section,
  // switching between loading skeleton, error+retry, and loaded states.
  Widget _buildDashboardSection() {
    if (_isDashboardLoading && _dashboardData == null) {
      return _buildDashboardLoadingSkeleton();
    }
    if (_dashboardError != null && _dashboardData == null) {
      return _buildDashboardErrorState();
    }

    final data = _dashboardData!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BalanceCard(amount: data.currentBalance, onTap: _openAccountBalance),
        const SizedBox(height: 12),
        MetricCard(
          icon: Icons.receipt_long_rounded,
          iconBoxColor: AppColors.darkTeal,
          backgroundColor: AppColors.mint,
          valueText: data.activeOrdersCount,
          subtitle: 'Active Orders',
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
          subtitle: 'Overdue Invoices',
          contentColor: AppColors.darkRedBrown,
          onTap: _openOverdueInvoices,
        ),
        const SizedBox(height: 12),
        LastPaymentCard(
          amount: data.lastPaymentAmount,
          date: data.lastPaymentDate,
        ),
      ],
    );
  }

  // Simple placeholder skeleton shown while dashboard data is first loading.
  Widget _buildDashboardLoadingSkeleton() {
    Widget skeletonBox(double height) {
      return Container(
        height: height,
        width: double.infinity,
        decoration: BoxDecoration(
          color: AppColors.border.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(8),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        skeletonBox(135),
        const SizedBox(height: 12),
        skeletonBox(72),
        const SizedBox(height: 12),
        skeletonBox(72),
        const SizedBox(height: 12),
        skeletonBox(72),
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
            _dashboardError ?? 'Unable to load dashboard data.',
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
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}
