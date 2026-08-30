// Fake AccountBalanceService for AccountBalanceScreen tests: resolves
// immediately (no simulated network delay) with deterministic fixture data,
// so tests don't need to pump for an artificial delay.

import 'package:anc_fabrics/models/business_central/customer_details.dart';
import 'package:anc_fabrics/services/account_balance_service.dart';

/// Default live-shaped fixture for tests that don't care about the exact
/// figures — distinct from the retired `$42,850.00`/`+12.4%` mock values.
const CustomerDetails kFakeAccountSummary = CustomerDetails(
  customerBalance: 36711.73,
  availableCredit: 57150.00,
  usedCredit: 42850.00,
);

class FakeAccountBalanceService implements AccountBalanceService {
  FakeAccountBalanceService({CustomerDetails? summary, this.summaryError})
    : summary = summary ?? kFakeAccountSummary;

  final CustomerDetails summary;

  /// When set, thrown from [fetchAccountSummary] instead of returning
  /// [summary].
  final Object? summaryError;

  @override
  Future<CustomerDetails> fetchAccountSummary() async {
    if (summaryError != null) throw summaryError!;
    return summary;
  }
}
