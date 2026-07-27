/// Purpose: Generic parser for the Laravel-style paginated envelope every
/// Business Central endpoint (ledger entries, and later payments, invoices,
/// credit memos, etc.) returns.
///
/// Responsibilities:
/// - Parse the envelope's pagination metadata and its `data` array of rows,
///   using a caller-supplied row parser so this type stays independent of
///   any one endpoint's row shape.
/// - Validate required metadata and reject a malformed `data` value (missing
///   or not a JSON array) via [FormatException] — never an uncontrolled cast
///   error.
///
/// Must not:
/// - Follow `next_page_url` itself, or decide which host is trusted — that
///   is [AncApiClient]'s job, since only it attaches the bearer token.
class PaginatedResponse<T> {
  const PaginatedResponse({
    required this.currentPage,
    required this.data,
    required this.firstPageUrl,
    required this.from,
    required this.lastPage,
    required this.lastPageUrl,
    required this.nextPageUrl,
    required this.path,
    required this.perPage,
    required this.prevPageUrl,
    required this.to,
    required this.total,
  });

  final int currentPage;
  final List<T> data;
  final String firstPageUrl;

  /// 1-based index of the first row on this page, or `null` when [data] is
  /// empty.
  final int? from;

  final int lastPage;
  final String lastPageUrl;

  /// URL of the next page, or `null` when this is the last page. Kept as a
  /// raw string — parsing and host-trust validation happen only at the
  /// point a caller actually follows it (see `AncApiClient.
  /// fetchLedgerEntriesPage`), never here.
  final String? nextPageUrl;

  final String path;
  final int perPage;

  /// URL of the previous page, or `null` on the first page. Never followed
  /// by this app (pagination only ever moves forward), but parsed since the
  /// backend always sends it.
  final String? prevPageUrl;

  /// 1-based index of the last row on this page, or `null` when [data] is
  /// empty.
  final int? to;

  final int total;

  /// Whether a subsequent page exists. Prefer this over comparing
  /// [currentPage] to [lastPage] when deciding whether to request another
  /// page — the backend-provided URL is the source of truth.
  bool get hasNextPage => nextPageUrl != null;

  /// Whether [currentPage] is the last page for this query.
  bool get isLastPage => currentPage >= lastPage;

  /// Parses [json] using [fromRowJson] to parse each element of `data`.
  ///
  /// Throws a [FormatException] — never an uncontrolled cast error — when
  /// [json] is not a JSON object, `data` is missing or not a JSON array, any
  /// row is not a JSON object, [fromRowJson] itself rejects a row, or a
  /// required pagination field is missing/malformed.
  factory PaginatedResponse.fromJson(
    Object? json,
    T Function(Map<String, dynamic>) fromRowJson,
  ) {
    if (json is! Map<String, dynamic>) {
      throw const FormatException('PaginatedResponse: expected a JSON object.');
    }

    final rawData = json['data'];
    if (rawData is! List) {
      throw const FormatException(
        'PaginatedResponse.data missing or not a JSON array.',
      );
    }

    final rows = <T>[
      for (final row in rawData)
        if (row is Map<String, dynamic>)
          fromRowJson(row)
        else
          throw const FormatException(
            'PaginatedResponse.data contains a non-object row.',
          ),
    ];

    return PaginatedResponse<T>(
      currentPage: _requireInt(json, 'current_page'),
      data: rows,
      firstPageUrl: _requireString(json, 'first_page_url'),
      from: _optionalInt(json, 'from'),
      lastPage: _requireInt(json, 'last_page'),
      lastPageUrl: _requireString(json, 'last_page_url'),
      nextPageUrl: _optionalString(json, 'next_page_url'),
      path: _requireString(json, 'path'),
      perPage: _requireInt(json, 'per_page'),
      prevPageUrl: _optionalString(json, 'prev_page_url'),
      to: _optionalInt(json, 'to'),
      total: _requireInt(json, 'total'),
    );
  }

  static int _requireInt(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is! int) {
      throw FormatException('PaginatedResponse.$key missing or not an int');
    }
    return value;
  }

  static int? _optionalInt(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value == null) return null;
    if (value is! int) {
      throw FormatException('PaginatedResponse.$key was not an int');
    }
    return value;
  }

  static String _requireString(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is! String || value.isEmpty) {
      throw FormatException(
        'PaginatedResponse.$key missing or not a non-empty string',
      );
    }
    return value;
  }

  static String? _optionalString(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value == null) return null;
    if (value is! String) {
      throw FormatException('PaginatedResponse.$key was not a string');
    }
    return value;
  }
}
