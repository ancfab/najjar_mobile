import '../models/home_dashboard_data.dart';

// endpoint is confirmed.
//
// Current Balance and Last Payment are no longer part of this mock — Current
// Balance is loaded live via `CurrentBalanceDataSource`, and Last Payment via
// `LastPaymentDataSource`; see `HomeScreen`.
const HomeDashboardData kMockHomeDashboardData = HomeDashboardData(
  activeOrdersCount: '12',
  overdueInvoicesAmount: '\$12,450.00',
);
