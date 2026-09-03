import '../models/home_dashboard_data.dart';
import '../utils/currency.dart';
import 'customer_details_service.dart';

/// Supplies the Home screen's dashboard summary metrics (Active Orders,
/// Overdue Invoices) — see [ApiHomeDashboardService] for the production
/// implementation. Kept as an injectable seam (mirroring
/// `LastPaymentDataSource`/`CurrentBalanceDataSource`'s convention) so
/// widget tests can supply a fake instead of a real network call.
abstract class HomeDashboardService {
  /// Fetches the Home dashboard summary. Implementations may throw — the
  /// Home screen maps any failure onto its dashboard error state (with a
  /// retry), never onto fabricated numbers.
  Future<HomeDashboardData> fetchHomeDashboardData();
}

/// Production [HomeDashboardService]: loads the authenticated customer's
/// own Business Central Customer Details snapshot (via the same
/// [CustomerDetailsService] the Account Balance screen uses) and formats
/// its `activeOrders` / `overdueInvoicesAmount` fields for the two Home
/// metric cards. No mock/dummy values anywhere: a field the backend does
/// not include renders as an em dash placeholder, never an invented figure.
class ApiHomeDashboardService implements HomeDashboardService {
  ApiHomeDashboardService({CustomerDetailsService? customerDetailsService})
    : _customerDetails = customerDetailsService ?? CustomerDetailsService(),
      _ownsService = customerDetailsService == null;

  final CustomerDetailsService _customerDetails;
  final bool _ownsService;

  /// Shown when the backend omits an optional metric — a visible "unknown"
  /// indicator, deliberately not `0`, which would fabricate a real-looking
  /// figure.
  static const String _unknown = '—';

  @override
  Future<HomeDashboardData> fetchHomeDashboardData() async {
    final details = await _customerDetails.fetchCustomerDetails();

    final activeOrders = details.activeOrders;
    final overdue = details.overdueInvoicesAmount;

    return HomeDashboardData(
      activeOrdersCount: activeOrders == null
          ? _unknown
          : _formatCount(activeOrders),
      // Plain, unprefixed figure — unlike Current Balance, this field never
      // carries a currency at all on any tenant, so there's no "unknown
      // currency" case to flag with "?"; just the number.
      overdueInvoicesAmount: overdue == null
          ? _unknown
          : formatPlainAmount(overdue),
    );
  }

  /// Renders a whole-number count without a trailing ".0" (the contract
  /// doesn't guarantee whether BC sends `0` or `0.0`), keeping any genuine
  /// fractional value visible rather than silently rounding it.
  static String _formatCount(num value) {
    if (value == value.truncate()) return value.truncate().toString();
    return value.toString();
  }

  /// Closes the underlying [CustomerDetailsService], but only when this
  /// instance created it; a caller-supplied service is left open for the
  /// caller to manage.
  void close() {
    if (_ownsService) _customerDetails.close();
  }
}
