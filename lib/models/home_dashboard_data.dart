/// Aggregated summary data shown across the Home screen dashboard cards
/// (active orders, overdue invoices).
///
/// Current Balance and Last Payment are deliberately not part of this
/// mock-backed summary — Current Balance is loaded live from the
/// ledger-entries API via `CurrentBalanceDataSource`, and Last Payment is
/// loaded live from the Payments API via `LastPaymentDataSource`; see
/// `HomeScreen`.
class HomeDashboardData {
  const HomeDashboardData({
    required this.activeOrdersCount,
    required this.overdueInvoicesAmount,
  });

  final String activeOrdersCount;
  final String overdueInvoicesAmount;
}
