import 'current_balance_service.dart';

/// Purpose: The seam `HomeScreen`'s Current Balance card depends on for its
/// live data — abstract so widget tests can inject a fake instead of
/// exercising real HTTP/secure storage, matching the existing
/// `LastPaymentDataSource`/`LiveLastPaymentDataSource` convention.
abstract class CurrentBalanceDataSource {
  /// Returns the authenticated customer's Current Balance. Throws
  /// `SessionExpiredException`, `BusinessCentralFailureException`, or
  /// `CurrentBalanceInconsistentCurrencyException` (see
  /// `current_balance_service.dart`) on failure — never a raw
  /// `AncApiException` or platform exception, and never mock data.
  Future<CurrentBalanceAmount> fetchCurrentBalance();
}

/// Default [CurrentBalanceDataSource]: loads every page of the
/// authenticated customer's Business Central ledger entries via
/// [CurrentBalanceService] and reduces them to a Current Balance.
class LiveCurrentBalanceDataSource implements CurrentBalanceDataSource {
  LiveCurrentBalanceDataSource({CurrentBalanceService? currentBalanceService})
    : _currentBalanceService = currentBalanceService ?? CurrentBalanceService();

  final CurrentBalanceService _currentBalanceService;

  @override
  Future<CurrentBalanceAmount> fetchCurrentBalance() =>
      _currentBalanceService.fetchCurrentBalance();
}
