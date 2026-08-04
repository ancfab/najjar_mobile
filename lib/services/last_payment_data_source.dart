import '../models/business_central/payment_entry.dart';
import 'last_payment_service.dart';

/// Purpose: The seam `HomeScreen`'s Last Payment row depends on for its live
/// data — abstract so widget tests can inject a fake instead of exercising
/// real HTTP/secure storage, matching the existing
/// `QuickHistoryDataSource`/`AccountBalanceService` injectable-service
/// convention.
abstract class LastPaymentDataSource {
  /// Returns the most recent payment, or `null` when the authenticated
  /// customer has no payments at all. Throws `SessionExpiredException` or
  /// `BusinessCentralFailureException` (see `business_central_error_mapper.
  /// dart`) on failure — never a raw `AncApiException` or platform
  /// exception.
  Future<PaymentEntry?> fetchLatestPayment();
}

/// Default [LastPaymentDataSource]: loads the single most recent payment via
/// [LastPaymentService], which requests `page=1&per_page=1` against the
/// confirmed newest-first Payments endpoint.
class LiveLastPaymentDataSource implements LastPaymentDataSource {
  LiveLastPaymentDataSource({LastPaymentService? lastPaymentService})
    : _lastPaymentService = lastPaymentService ?? LastPaymentService();

  final LastPaymentService _lastPaymentService;

  @override
  Future<PaymentEntry?> fetchLatestPayment() =>
      _lastPaymentService.fetchLatestPayment();
}
