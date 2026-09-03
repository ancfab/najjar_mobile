// Fake HomeDashboardService for HomeScreen tests: returns a canned
// HomeDashboardData (or throws) without exercising real HTTP or secure
// storage.

import 'package:anc_fabrics/models/home_dashboard_data.dart';
import 'package:anc_fabrics/services/home_dashboard_service.dart';

class FakeHomeDashboardService implements HomeDashboardService {
  FakeHomeDashboardService({
    this.data = const HomeDashboardData(
      activeOrdersCount: '0',
      overdueInvoicesAmount: '0.00',
    ),
    this.error,
  });

  /// Returned from [fetchHomeDashboardData] unless [error] is set.
  final HomeDashboardData data;

  /// When set, thrown from [fetchHomeDashboardData] instead of returning
  /// [data].
  final Object? error;

  int callCount = 0;

  @override
  Future<HomeDashboardData> fetchHomeDashboardData() async {
    callCount++;
    if (error != null) throw error!;
    return data;
  }
}
