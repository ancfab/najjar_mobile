// Fake CurrentBalanceDataSource for HomeScreen tests: returns a canned
// CurrentBalanceAmount (or throws, or stays pending) without exercising real
// HTTP or secure storage.

import 'package:anc_fabrics/services/current_balance_data_source.dart';
import 'package:anc_fabrics/services/current_balance_service.dart';

class FakeCurrentBalanceDataSource implements CurrentBalanceDataSource {
  FakeCurrentBalanceDataSource({this.amount, this.error, this.pendingFuture});

  /// Returned from [fetchCurrentBalance] when set.
  final CurrentBalanceAmount? amount;

  /// When set, thrown from [fetchCurrentBalance] instead of returning
  /// [amount].
  final Object? error;

  /// When set, awaited instead of resolving immediately — lets a test
  /// observe the loading state before controlling exactly when/how the
  /// call completes.
  final Future<CurrentBalanceAmount>? pendingFuture;

  int callCount = 0;

  @override
  Future<CurrentBalanceAmount> fetchCurrentBalance() async {
    callCount++;
    if (pendingFuture != null) return pendingFuture!;
    if (error != null) throw error!;
    return amount ?? const CurrentBalanceAmount(amount: 0, currencyCode: null);
  }
}
