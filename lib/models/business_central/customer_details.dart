/// Purpose: The Business Central customer-details endpoint's single scalar
/// snapshot response — the authenticated customer's balance/credit figures,
/// optionally scoped to a requested `date_from`/`date_to` range.
///
/// Responsibilities:
/// - Parse [customerBalance] from the confirmed **live** field name
///   `customerbalance` (all lowercase — confirmed by runtime diagnostics
///   against the real backend response on 2026-08-30). The originally
///   assumed/documented camelCase `customerBalance` is accepted as a
///   fallback for defensive compatibility, but `customerbalance` is the
///   canonical key checked first.
/// - Parse `availableCredit`/`usedCredit` plus the additionally-observed/
///   documented fields (`overdueInvoicesAmount`, `lastPaymentAmount`,
///   `lastPaymentDate`, `activeOrders`, `DateFilter`) — never invent a field
///   name not named in the confirmed contract.
/// - Throw a [FormatException] — never an uncontrolled cast error, and never
///   a silently-applied fallback value — when a *required* monetary field
///   ([customerBalance], [availableCredit], [usedCredit]) is missing or the
///   wrong type under both the canonical and fallback key.
/// - Treat every other field as optional: absent is `null`; a *present* but
///   wrong-type value still throws (never silently replaced with fake data)
///   — except [dateFilter], whose exact shape this contract does not
///   confirm (see its doc comment).
///
/// Must not:
/// - Send or require a `customer_no`/currency field — this endpoint's
///   confirmed contract carries neither; the ANC API scopes the result to
///   the authenticated token server-side.
class CustomerDetails {
  const CustomerDetails({
    required this.customerBalance,
    required this.availableCredit,
    required this.usedCredit,
    this.overdueInvoicesAmount,
    this.lastPaymentAmount,
    this.lastPaymentDate,
    this.activeOrders,
    this.dateFilter,
  });

  /// The customer's overall balance for the requested (or default) period.
  /// Anchors the Account Balance screen's hero figure — see
  /// `AccountBalanceHeroCard`.
  final double customerBalance;

  final double availableCredit;
  final double usedCredit;

  /// Total amount currently overdue, when the backend includes it. Not
  /// consumed by the Account Balance screen in this phase (out of scope —
  /// see `HomeDashboardData`'s still-mocked equivalent).
  final double? overdueInvoicesAmount;

  final double? lastPaymentAmount;
  final DateTime? lastPaymentDate;

  /// Count of active orders, when the backend includes it. Kept as [num]
  /// since the confirmed contract does not state whether this is sent as a
  /// JSON integer or a decimal.
  final num? activeOrders;

  /// Backend-provided description of the date range this snapshot covers
  /// (e.g. a label or an echoed range), shown verbatim as "Period: ..." on
  /// the Balance by Period section. Kept as a raw, undisplayed-as-parsed
  /// string — this contract's exact shape (plain string vs. a structured
  /// object) is not confirmed, so a present-but-non-String value is treated
  /// as absent (`null`) rather than thrown, since this field is display-only
  /// and never used in a balance calculation.
  final String? dateFilter;

  /// The live backend's actual field name for [customerBalance] — confirmed
  /// by runtime diagnostics; see the class-level doc comment.
  static const String _canonicalBalanceKey = 'customerbalance';

  /// The originally assumed/documented camelCase name, accepted only as a
  /// fallback if [_canonicalBalanceKey] is absent — kept in case a future
  /// backend revision corrects the casing, but never preferred over the
  /// confirmed live key.
  static const String _fallbackBalanceKey = 'customerBalance';

  static final RegExp _dateOnlyPattern = RegExp(r'^\d{4}-\d{2}-\d{2}$');

  /// Parses [json]. If the top-level decoded body wraps its fields in a
  /// `data` object (matching the `data`-wrapped shape this app's auth
  /// endpoints use), that nested map is parsed instead of the top-level one
  /// — this endpoint's confirmed live example was observed as a flat
  /// top-level shape, but this tolerates either without guessing a field
  /// name that isn't in the confirmed contract.
  factory CustomerDetails.fromJson(Map<String, dynamic> json) {
    final root = json['data'];
    final fields = root is Map<String, dynamic> ? root : json;

    return CustomerDetails(
      customerBalance: _requireBalance(fields),
      availableCredit: _requireNum(fields, 'availableCredit'),
      usedCredit: _requireNum(fields, 'usedCredit'),
      overdueInvoicesAmount: _optionalNum(fields, 'overdueInvoicesAmount'),
      lastPaymentAmount: _optionalNum(fields, 'lastPaymentAmount'),
      lastPaymentDate: _optionalDateOnly(fields, 'lastPaymentDate'),
      activeOrders: _optionalRawNum(fields, 'activeOrders'),
      dateFilter: _optionalLenientString(fields, 'DateFilter'),
    );
  }

  /// Reads [customerBalance] from [_canonicalBalanceKey] (`customerbalance`)
  /// when present, falling back to [_fallbackBalanceKey] (`customerBalance`)
  /// only when the canonical key is entirely absent. Either way, the
  /// resolved value must still be a number — missing under both keys, or
  /// present under whichever key was checked but the wrong type, still
  /// throws [FormatException] rather than defaulting to zero or any other
  /// fabricated value.
  static double _requireBalance(Map<String, dynamic> json) {
    final key = json.containsKey(_canonicalBalanceKey)
        ? _canonicalBalanceKey
        : _fallbackBalanceKey;
    final value = json[key];
    if (value is int) return value.toDouble();
    if (value is double) return value;
    throw FormatException(
      'CustomerDetails.$_canonicalBalanceKey (or legacy '
      '$_fallbackBalanceKey) missing or not a number',
    );
  }

  static double _requireNum(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is int) return value.toDouble();
    if (value is double) return value;
    throw FormatException('CustomerDetails.$key missing or not a number');
  }

  static double? _optionalNum(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value == null) return null;
    if (value is int) return value.toDouble();
    if (value is double) return value;
    throw FormatException('CustomerDetails.$key was not a number');
  }

  static num? _optionalRawNum(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value == null) return null;
    if (value is num) return value;
    throw FormatException('CustomerDetails.$key was not a number');
  }

  static DateTime? _optionalDateOnly(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value == null) return null;
    if (value is! String || !_dateOnlyPattern.hasMatch(value)) {
      throw FormatException(
        'CustomerDetails.$key was not a yyyy-MM-dd date string',
      );
    }
    try {
      return DateTime.parse(value);
    } on FormatException {
      throw FormatException(
        'CustomerDetails.$key was not a valid calendar date',
      );
    }
  }

  /// Returns [key] when present and a [String], or `null` for anything else
  /// (absent, JSON `null`, or a present non-String value) — see
  /// [dateFilter]'s doc comment for why this one field is lenient rather
  /// than throwing on a type mismatch.
  static String? _optionalLenientString(Map<String, dynamic> json, String key) {
    final value = json[key];
    return value is String ? value : null;
  }

  /// Deliberately omits every monetary field — financial data is never
  /// logged implicitly, matching [LedgerEntry]/[PaymentEntry]'s convention.
  @override
  String toString() => 'CustomerDetails(dateFilter: $dateFilter)';
}
