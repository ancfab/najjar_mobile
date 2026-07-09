import '../data/mock_dashboard_data.dart';
import '../models/home_dashboard_data.dart';

/// Supplies dashboard summary data (balance, orders, invoices, last
/// payment) for the Home screen.
class HomeDashboardService {
  const HomeDashboardService();

  /// Fetches the Home dashboard summary.
  ///
  /// TODO: Replace mock dashboard data with backend dashboard summary API
  /// once endpoint is confirmed.
  Future<HomeDashboardData> fetchHomeDashboardData() async {
    await Future.delayed(const Duration(milliseconds: 600));
    return kMockHomeDashboardData;
  }
}
