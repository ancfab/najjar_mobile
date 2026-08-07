import 'current_balance_data_source.dart';
import 'current_balance_service.dart';

/// TEMPORARY CLIENT DEMO MODE [CurrentBalanceDataSource]: returns a fixed,
/// realistic [CurrentBalanceAmount] with no I/O — never calls the live
/// ledger-entries endpoint. Selected in place of
/// [LiveCurrentBalanceDataSource] only when [DemoConfig.useDemoCurrentBalance]
/// (`demo_config.dart`) is `true`; see `HomeScreen`'s
/// `resolveDefaultCurrentBalanceDataSource`.
///
/// Only the raw amount/currency pair is supplied here — `HomeScreen` still
/// formats it through the same `formatCurrencyOrUnknown` helper the live
/// result goes through, so this never hardcodes a pre-formatted display
/// string.
class DemoCurrentBalanceDataSource implements CurrentBalanceDataSource {
  const DemoCurrentBalanceDataSource();

  /// Mock balance shown during client demos.
  static const CurrentBalanceAmount mockBalance = CurrentBalanceAmount(
    amount: 18450.75,
    currencyCode: 'AED',
  );

  @override
  Future<CurrentBalanceAmount> fetchCurrentBalance() async => mockBalance;
}
