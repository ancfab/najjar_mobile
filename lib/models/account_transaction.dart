/// Whether an [AccountTransaction] added to or subtracted from the account
/// balance.
///
/// [neutral] is for transactions whose source data does not define a
/// credit/debit meaning for its signed amount (e.g. Business Central ledger
/// entries — see `LedgerEntryPresentationAdapter`) — rendered without the
/// green/red color or "Credit"/"Debit" label the other two values get,
/// rather than guessing.
enum AccountTransactionType { credit, debit, neutral }

/// Which category an [AccountTransaction] belongs to, used to pick its
/// Quick History row icon.
enum AccountTransactionCategory {
  supplyPurchase,
  deposit,
  serviceFee,

  /// A Business Central ledger entry adapted for display — see
  /// `LedgerEntryPresentationAdapter`.
  ledgerEntry,
}

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
    this.currencyCode,
  });

  final String id;
  final String label;

  /// Signed amount: negative for a debit, positive for a credit.
  final double amount;
  final AccountTransactionType type;
  final DateTime occurredAt;
  final AccountTransactionCategory category;

  /// Optional external reference (e.g. a deposit or PO reference number).
  final String? reference;

  /// ISO 4217 currency code as supplied by the source data (e.g. a Business
  /// Central ledger entry's `Currency_Code`), or `null` when no currency
  /// code is available — in which case display falls back to the app's
  /// existing default ("$") rather than inventing one. Never converted or
  /// re-derived; passed through exactly as received.
  final String? currencyCode;
}
