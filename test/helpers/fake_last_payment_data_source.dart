// Fake LastPaymentDataSource for HomeScreen tests: returns a canned
// PaymentEntry (or none, or throws) without exercising real HTTP or secure
// storage.

import 'package:anc_fabrics/models/business_central/payment_entry.dart';
import 'package:anc_fabrics/services/last_payment_data_source.dart';

class FakeLastPaymentDataSource implements LastPaymentDataSource {
  FakeLastPaymentDataSource({this.entry, this.error, this.pendingFuture});

  /// Returned from [fetchLatestPayment] when set; `null` means "no
  /// payments" unless [error] or [pendingFuture] is set.
  final PaymentEntry? entry;

  /// When set, thrown from [fetchLatestPayment] instead of returning
  /// [entry].
  final Object? error;

  /// When set, awaited instead of resolving immediately — lets a test
  /// observe the loading state before controlling exactly when/how the
  /// call completes.
  final Future<PaymentEntry?>? pendingFuture;

  int callCount = 0;

  @override
  Future<PaymentEntry?> fetchLatestPayment() async {
    callCount++;
    if (pendingFuture != null) return pendingFuture!;
    if (error != null) throw error!;
    return entry;
  }
}
