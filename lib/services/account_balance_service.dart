import '../models/business_central/customer_details.dart';
import 'customer_details_service.dart';

/// Data seam for the Account Balance screen: the hero balance/Credit
/// Information snapshot, backed by the Business Central customer-details
/// endpoint (see `CustomerDetailsService`).
abstract class AccountBalanceService {
  /// Fetches the authenticated customer's current snapshot with no date
  /// filter, for the Global Account Balance hero card and Credit
  /// Information card.
  Future<CustomerDetails> fetchAccountSummary();
}

/// Default [AccountBalanceService]: backed by the live
/// [CustomerDetailsService].
class LiveAccountBalanceService implements AccountBalanceService {
  LiveAccountBalanceService({CustomerDetailsService? customerDetailsService})
    : _customerDetailsService =
          customerDetailsService ?? CustomerDetailsService();

  final CustomerDetailsService _customerDetailsService;

  @override
  Future<CustomerDetails> fetchAccountSummary() =>
      _customerDetailsService.fetchCustomerDetails();

  /// Closes the underlying [CustomerDetailsService]'s HTTP client, but only
  /// when this instance created its own (a caller-supplied
  /// [CustomerDetailsService] is left for the caller to manage).
  void close() => _customerDetailsService.close();
}
