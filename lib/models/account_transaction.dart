/// Whether an [AccountTransaction] added to or subtracted from the account
/// balance.
enum AccountTransactionType { credit, debit }

/// Which category an [AccountTransaction] belongs to, used to pick its
/// Quick History row icon.
enum AccountTransactionCategory { supplyPurchase, deposit, serviceFee }

/// A single entry in the Account Balance screen's Quick History list.
class AccountTransaction {
  const AccountTransaction({
    required this.id,
    required this.label,
    required this.amount,
    required this.type,
    required this.occurredAt,
    required this.category,
    this.reference,
  });

  final String id;
  final String label;

  /// Signed dollar amount: negative for a debit, positive for a credit.
  final double amount;
  final AccountTransactionType type;
  final DateTime occurredAt;
  final AccountTransactionCategory category;

  /// Optional external reference (e.g. a deposit or PO reference number).
  final String? reference;
}
