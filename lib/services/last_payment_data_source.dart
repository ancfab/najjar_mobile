import '../models/business_central/payment_entry.dart';
import 'customer_details_service.dart';
import 'last_payment_service.dart';

/// A minimal snapshot of the customer's most recent payment — amount, date
/// and, when known, currency. Deliberately not the full [PaymentEntry]
/// shape: the `customer_details` endpoint's `lastPaymentAmount`/
/// `lastPaymentDate` fields carry no document number, customer number, or
/// currency the way a real Payments-endpoint row does, and this type must
/// never fabricate those to force-fit one.
class LastPaymentSummary {
  const LastPaymentSummary({
    required this.amount,
    required this.date,
    this.currencyCode,
  });

  final double amount;

  /// `null` when the backend published an amount but no date for it —
  /// never a fabricated fallback date.
  final DateTime? date;

  /// The payment's own currency, as returned by the Payments endpoint —
  /// `null` when the source has none (`customer_details`).
  final String? currencyCode;
}

/// Purpose: The seam `HomeScreen`'s Last Payment row depends on for its live
/// data — abstract so widget tests can inject a fake instead of exercising
/// real HTTP/secure storage, matching the existing
/// `QuickHistoryDataSource`/`AccountBalanceService` injectable-service
/// convention.
abstract class LastPaymentDataSource {
  /// Returns the most recent payment, or `null` when the authenticated
  /// customer has no payment on record. Throws `SessionExpiredException` or
  /// `BusinessCentralFailureException` (see `business_central_error_mapper.
  /// dart`) on failure — never a raw `AncApiException` or platform
  /// exception.
  Future<LastPaymentSummary?> fetchLatestPayment();
}

/// Customer-details-backed [LastPaymentDataSource]: reads the customer's
/// own `customer_details` snapshot's `lastPaymentAmount`/`lastPaymentDate`
/// fields directly. Home's default until 2026-09-30, when it switched to
/// the real Payments rows (see [LiveLastPaymentDataSource]); kept as a
/// working alternate implementation of this seam.
///
/// Returns `null` (the "no payment" empty state) only when
/// `lastPaymentAmount` itself is absent — a *present* value of `0` is
/// still shown as a real reported figure (with whatever date accompanies
/// it, if any), never silently reinterpreted as "no payment" — BC's
/// contract does not document `0` as a "no payment" sentinel, so this
/// class does not invent that rule.
class CustomerDetailsLastPaymentDataSource implements LastPaymentDataSource {
  CustomerDetailsLastPaymentDataSource({
    CustomerDetailsService? customerDetailsService,
  }) : _customerDetails = customerDetailsService ?? CustomerDetailsService(),
       _ownsService = customerDetailsService == null;

  final CustomerDetailsService _customerDetails;
  final bool _ownsService;

  @override
  Future<LastPaymentSummary?> fetchLatestPayment() async {
    final details = await _customerDetails.fetchCustomerDetails();
    final amount = details.lastPaymentAmount;
    if (amount == null) return null;
    return LastPaymentSummary(amount: amount, date: details.lastPaymentDate);
  }

  /// Closes the underlying [CustomerDetailsService], but only when this
  /// instance created it; a caller-supplied service is left open for the
  /// caller to manage.
  void close() {
    if (_ownsService) _customerDetails.close();
  }
}

/// Default [LastPaymentDataSource] (product decision, 2026-09-30): loads
/// the single most recent payment via [LastPaymentService], which requests
/// `page=1&per_page=1` against the Payments endpoint — the backend returns
/// it newest-first by `postingDate` (ties: higher `entryNo`) — so Home shows
/// the real latest payment row and its posting date rather than
/// `customer_details`' summary fields.
class LiveLastPaymentDataSource implements LastPaymentDataSource {
  LiveLastPaymentDataSource({LastPaymentService? lastPaymentService})
    : _lastPaymentService = lastPaymentService ?? LastPaymentService(),
      _ownsService = lastPaymentService == null;

  final LastPaymentService _lastPaymentService;
  final bool _ownsService;

  @override
  Future<LastPaymentSummary?> fetchLatestPayment() async {
    final entry = await _lastPaymentService.fetchLatestPayment();
    if (entry == null) return null;
    return LastPaymentSummary(
      amount: entry.amount,
      date: entry.postingDate,
      currencyCode: entry.currencyCode,
    );
  }

  /// Closes the underlying [LastPaymentService], but only when this
  /// instance created it; a caller-supplied service is left open for the
  /// caller to manage.
  void close() {
    if (_ownsService) _lastPaymentService.close();
  }
}
