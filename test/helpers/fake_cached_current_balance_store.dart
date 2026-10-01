// Fake in-memory CachedCurrentBalanceStore for HomeScreen tests — no real
// secure storage platform channel is exercised.

import 'package:anc_fabrics/models/cached_current_balance.dart';
import 'package:anc_fabrics/services/cached_current_balance_store.dart';
import 'package:anc_fabrics/services/current_balance_service.dart';

class FakeCachedCurrentBalanceStore implements CachedCurrentBalanceStore {
  FakeCachedCurrentBalanceStore({this.cached});

  /// Returned from [load]; null means "nothing cached for this account".
  CachedCurrentBalance? cached;

  /// When set, [load] awaits this future before returning, so a test can
  /// hold the cached figure back and assert what the card shows meanwhile.
  Future<void>? loadDelay;

  /// Every amount passed to [save], in call order.
  final List<CurrentBalanceAmount> savedAmounts = [];

  int loadCallCount = 0;

  @override
  Future<CachedCurrentBalance?> load() async {
    loadCallCount++;
    final delay = loadDelay;
    if (delay != null) await delay;
    return cached;
  }

  @override
  Future<void> save(CurrentBalanceAmount amount) async {
    savedAmounts.add(amount);
    cached = CachedCurrentBalance(amount: amount, cachedAt: DateTime.now());
  }
}
