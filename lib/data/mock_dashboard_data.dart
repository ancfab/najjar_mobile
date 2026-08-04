import '../models/home_dashboard_data.dart';

// TODO: Replace mock dashboard data with backend dashboard summary API once
// endpoint is confirmed.
// TODO: Confirm currency formatting rules with business team.
// TODO: Confirm overdue invoice rule: status-based or due-date-based.
//
// Current Balance and Last Payment are no longer part of this mock — Current
// Balance is loaded live via `CurrentBalanceDataSource`, and Last Payment via
// `LastPaymentDataSource`; see `HomeScreen`.
const HomeDashboardData kMockHomeDashboardData = HomeDashboardData(
  // TODO: Replace with active orders count API once endpoint is confirmed.
  activeOrdersCount: '12',
  // TODO: Replace with overdue invoices total API once endpoint is
  // confirmed; also see the overdue-rule TODO above.
  overdueInvoicesAmount: '\$12,450.00',
);
