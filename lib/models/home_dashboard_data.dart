/// Aggregated summary data shown across the Home screen dashboard cards
/// (current balance, active orders, overdue invoices, last payment).
class HomeDashboardData {
  const HomeDashboardData({
    required this.currentBalance,
    required this.activeOrdersCount,
    required this.overdueInvoicesAmount,
    required this.lastPaymentAmount,
    required this.lastPaymentDate,
  });

  final String currentBalance;
  final String activeOrdersCount;
  final String overdueInvoicesAmount;
  final String lastPaymentAmount;
  final String lastPaymentDate;
}
