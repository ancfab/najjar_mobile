/// A single point on the Account Balance screen's Balance History chart.
class BalanceHistoryPoint {
  const BalanceHistoryPoint({required this.date, required this.balance});

  final DateTime date;
  final double balance;
}
