import '../models/home_dashboard_data.dart';

// TODO: Replace mock dashboard data with backend dashboard summary API once
// endpoint is confirmed.
// TODO: Confirm currency formatting rules with business team.
// TODO: Confirm overdue invoice rule: status-based or due-date-based.
const HomeDashboardData kMockHomeDashboardData = HomeDashboardData(
  // TODO: Replace this placeholder with live account balance from API after
  // backend endpoint is confirmed.
  currentBalance: '\$42,850.00',
  // TODO: Replace with active orders count API once endpoint is confirmed.
  activeOrdersCount: '12',
  // TODO: Replace with overdue invoices total API once endpoint is
  // confirmed; also see the overdue-rule TODO above.
  overdueInvoicesAmount: '\$12,450.00',
  // TODO: Replace this placeholder with most recent payment transaction
  // from API after backend endpoint is confirmed.
  lastPaymentAmount: '\$1,250.00',
  lastPaymentDate: 'Oct 24',
);
