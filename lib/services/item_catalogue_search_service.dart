/// Purpose: The frontend contract Home's Check Availability catalogue search
/// step calls to resolve a typed/search code to one or more catalogue
/// groups, before the user picks an exact variation for the existing
/// `StockLookupService.lookup` seam. Distinct from `StockLookupService`:
/// this service never talks to the inventory endpoint and never itself
/// resolves final stock availability — see the library doc comment on
/// `stock_lookup_service.dart` for that contract.
///
/// CONFIRMED(item-search contract): `GET /items?search=...` returns Business
/// Central's own broad match against both `commonItemNo` and `itemNo` (see
/// this feature's production verification), so a search may legitimately
/// return catalogue groups whose `commonItemNo` only *contains* the entered
/// text as a substring of one of its `itemNo`s. This service does not filter
/// those out — see [resolveExactCommonItemGroup] for how an exact
/// `commonItemNo` match is distinguished from that broader set.
library;

import '../config/api_config.dart';
import '../models/business_central/business_central_item_search_group.dart';
import 'anc_api_client.dart';
import 'anc_api_exceptions.dart';
import 'auth_session_store.dart';
import 'business_central_error_mapper.dart';
import 'secure_auth_session_store.dart';
import 'session_expiry_coordinator.dart';

/// Sealed outcome of one [ItemCatalogueSearchService.search] call.
sealed class ItemCatalogueSearchResult {
  const ItemCatalogueSearchResult(this.rawQuery);

  /// The raw search text as entered, before trimming — always present, even
  /// on failure, so the UI can show the user what was searched for.
  final String rawQuery;
}

/// Exactly one returned group's `commonItemNo` matched [rawQuery]
/// (trimmed, case-insensitive) — see [resolveExactCommonItemGroup]. The UI
/// shows only [group]'s variations, never the other groups the search also
/// returned.
class ItemCatalogueExactMatch extends ItemCatalogueSearchResult {
  const ItemCatalogueExactMatch(super.rawQuery, this.group);

  final BusinessCentralItemSearchGroup group;
}

/// No single group's `commonItemNo` exactly matched [rawQuery] — every group
/// the backend returned is preserved as a suggestion for the user to pick
/// from, per the confirmed broad `commonItemNo`/`itemNo` search behavior.
class ItemCatalogueSuggestions extends ItemCatalogueSearchResult {
  const ItemCatalogueSuggestions(super.rawQuery, this.groups);

  final List<BusinessCentralItemSearchGroup> groups;
}

/// The search completed but returned no groups at all.
class ItemCatalogueNoResults extends ItemCatalogueSearchResult {
  const ItemCatalogueNoResults(super.rawQuery);
}

/// [rawQuery] itself failed local validation (empty after trimming) —
/// before any API call.
class ItemCatalogueInvalidQuery extends ItemCatalogueSearchResult {
  const ItemCatalogueInvalidQuery(super.rawQuery);
}

/// A transient failure (network/protocol/unexpected HTTP status, or
/// pagination metadata that could not be trusted) that is reasonable to
/// retry.
class ItemCatalogueRetryableFailure extends ItemCatalogueSearchResult {
  const ItemCatalogueRetryableFailure(super.rawQuery);
}

/// The backing service is reachable but reports itself temporarily
/// unavailable (the confirmed HTTP 503 case, mapped the same way as every
/// other Business Central endpoint — see `mapBusinessCentralError`).
class ItemCatalogueTemporarilyUnavailable extends ItemCatalogueSearchResult {
  const ItemCatalogueTemporarilyUnavailable(super.rawQuery);
}

/// The authenticated session is no longer valid. Mirrors
/// `StockLookupSessionExpired`: [ItemCatalogueSearchService] hands off to
/// the session coordinator itself (navigating to Login) before returning
/// this, so the UI treats it as "nothing to show here", never a local error
/// card.
class ItemCatalogueSessionExpired extends ItemCatalogueSearchResult {
  const ItemCatalogueSessionExpired(super.rawQuery);
}

/// Picks the single catalogue group whose `commonItemNo` exactly matches
/// [enteredSearch] (both trimmed and compared case-insensitively), or
/// `null` when no group matches or more than one does.
///
/// Pure and side-effect free, so it is independently testable from the
/// service/UI. A `null` return covers three distinct situations the caller
/// treats identically (falling back to showing every returned [groups] as
/// suggestions rather than guessing):
/// - no group's `commonItemNo` matches at all;
/// - the backend returns duplicate groups with the same exact
///   `commonItemNo` — a malformed/unexpected payload this function never
///   silently resolves by picking one or merging their variations, since
///   there is no evidence either duplicate is the "right" one.
BusinessCentralItemSearchGroup? resolveExactCommonItemGroup(
  String enteredSearch,
  List<BusinessCentralItemSearchGroup> groups,
) {
  final normalizedQuery = enteredSearch.trim().toLowerCase();
  final matches = groups
      .where(
        (group) => group.commonItemNo.trim().toLowerCase() == normalizedQuery,
      )
      .toList(growable: false);
  return matches.length == 1 ? matches.single : null;
}

/// Purpose: Resolves a Home Check Availability search into a catalogue
/// group (exact match) or a set of suggested groups, by calling
/// `GET /items?search=...` through [AncApiClient.searchItems] and paging
/// through every returned page of groups.
///
/// Responsibilities:
/// - Reject an empty (post-trim) query locally before any API call.
/// - Read the bearer token through the existing [AuthSessionStore] seam.
/// - Fetch every page of grouped results for the search term, following
///   only the backend's numeric `current_page`/`last_page` fields — never a
///   `next_page_url` (unsafe/incomplete on every other confirmed Business
///   Central list endpoint; see `ItemsService`'s doc comment) — aborting as
///   incomplete if that metadata cannot be trusted or [_maxPages] is
///   reached, so a truncated page set is never presented as complete.
/// - Apply [resolveExactCommonItemGroup] to the aggregated groups.
/// - Map every transport/HTTP failure onto [ItemCatalogueSearchResult] via
///   [mapBusinessCentralError], with `supportsAccountLinking: false` — this
///   catalog is company-scoped, matching `ItemsService`'s own 422 handling,
///   never `ItemsService` itself.
/// - Hand off to [SessionExpiryCoordinator] on a missing session or
///   confirmed HTTP 401, returning [ItemCatalogueSessionExpired] rather than
///   throwing.
///
/// Must not:
/// - Resolve final stock availability — that remains
///   `StockLookupService.lookup(variation.itemNo)`, called separately once
///   the user picks a variation.
/// - Download/filter the unfiltered catalog client-side — every request is
///   `search`-scoped.
///
/// Injectable seam `HomeScreen`'s Check Availability catalogue-search step
/// depends on — mirrors `StockLookupService`'s interface/implementation
/// split so a test can inject a fake instead of exercising real HTTP/secure
/// storage, exactly like `HomeScreen.checkAvailabilityService`.
abstract class ItemCatalogueSearchService {
  Future<ItemCatalogueSearchResult> search(String rawQuery);
}

/// The production [ItemCatalogueSearchService] implementation — see the
/// interface's doc comment for responsibilities.
class ApiItemCatalogueSearchService implements ItemCatalogueSearchService {
  ApiItemCatalogueSearchService({
    AncApiClient? apiClient,
    AuthSessionStore? sessionStore,
    SessionExpiryCoordinator? coordinator,
  }) : _apiClient = apiClient ?? AncApiClient(),
       _ownsApiClient = apiClient == null,
       _sessionStore = sessionStore ?? SecureAuthSessionStore(),
       _coordinator = coordinator ?? sessionExpiryCoordinator;

  final AncApiClient _apiClient;
  final bool _ownsApiClient;
  final AuthSessionStore _sessionStore;
  final SessionExpiryCoordinator _coordinator;

  /// Fixed `per_page` for every search request this service sends, matching
  /// the app's general Business Central pagination policy.
  static const int _perPage = ApiConfig.businessCentralDefaultPerPage;

  /// Hard cap on pages fetched for one search — defensive only, matching
  /// `ApiStockLookupService._maxPages`'s role: guarantees termination even
  /// if the backend's pagination metadata is malformed.
  static const int _maxPages = 50;

  @override
  Future<ItemCatalogueSearchResult> search(String rawQuery) async {
    final trimmed = rawQuery.trim();
    
    if (trimmed.isEmpty) return ItemCatalogueInvalidQuery(rawQuery);

    final session = await _sessionStore.read();
    if (session == null) {
  
      // Defensive: an authenticated caller should never reach this screen
      // without a stored session, but if it happens there is nothing to
      // gain by pretending otherwise — route through the same centralized
      // path a confirmed 401 would.
      await _coordinator.handleUnauthorized();
      return ItemCatalogueSessionExpired(rawQuery);
    }
  
    final _GroupPageFetch fetch;
    try {
      fetch = await _fetchAllGroupPages(token: session.token, search: trimmed);
    } on AncApiException catch (error) {
   
      return _mapFailure(rawQuery, error);
    }

    if (!fetch.complete) {
      // Malformed pagination metadata or the defensive page cap was hit —
      // never present a partial/truncated group set as a complete result.
     
      return ItemCatalogueRetryableFailure(rawQuery);
    }

    final groups = fetch.groups;
    if (groups.isEmpty) {
     
      return ItemCatalogueNoResults(rawQuery);
    }

    final exactMatch = resolveExactCommonItemGroup(trimmed, groups);
    if (exactMatch != null) {
    
      return ItemCatalogueExactMatch(rawQuery, exactMatch);
    }

    return ItemCatalogueSuggestions(rawQuery, groups);
  }

  /// Fetches every page of grouped search results for [search], starting at
  /// page 1 and following the backend's `current_page`/`last_page` fields
  /// (never `next_page_url`) — see the class-level doc comment.
  Future<_GroupPageFetch> _fetchAllGroupPages({
    required String token,
    required String search,
  }) async {
    final groups = <BusinessCentralItemSearchGroup>[];
    var requestedPage = 1;
    var previousCurrentPage = 0;

    for (var iteration = 0; iteration < _maxPages; iteration++) {
      final response = await _apiClient.searchItems(
        token: token,
        search: search,
        page: requestedPage,
        perPage: _perPage,
      );

      final currentPage = response.currentPage;
      final lastPage = response.lastPage;
      final malformed =
          currentPage < 1 ||
          lastPage < 1 ||
          currentPage > lastPage ||
          currentPage != requestedPage ||
          currentPage <= previousCurrentPage;
      if (malformed) return const _GroupPageFetch.incomplete();

      groups.addAll(response.data);
      if (response.isLastPage) return _GroupPageFetch.complete(groups);

      previousCurrentPage = currentPage;
      requestedPage = currentPage + 1;
    }

    // Exceeded the defensive page cap without ever reaching the last page.
    return const _GroupPageFetch.incomplete();
  }

  Future<ItemCatalogueSearchResult> _mapFailure(
    String rawQuery,
    AncApiException error,
  ) async {
    final outcome = mapBusinessCentralError(
      error,
      supportsAccountLinking: false,
    );
    return switch (outcome) {
      BusinessCentralUnauthorized() => await _sessionExpired(rawQuery),
      BusinessCentralTemporarilyUnavailable() =>
        ItemCatalogueTemporarilyUnavailable(rawQuery),
      BusinessCentralUpstreamFailure() => ItemCatalogueRetryableFailure(
        rawQuery,
      ),
      BusinessCentralNetworkFailure() => ItemCatalogueRetryableFailure(
        rawQuery,
      ),
      BusinessCentralRequestDefect() => ItemCatalogueRetryableFailure(rawQuery),
      BusinessCentralAccountNotLinked() => ItemCatalogueRetryableFailure(
        rawQuery,
      ),
      BusinessCentralProtocolFailure() => ItemCatalogueRetryableFailure(
        rawQuery,
      ),
    };
  }

  Future<ItemCatalogueSearchResult> _sessionExpired(String rawQuery) async {
    await _coordinator.handleUnauthorized();
    return ItemCatalogueSessionExpired(rawQuery);
  }

  /// Closes the underlying [AncApiClient], but only when this instance
  /// created it; a caller-supplied client is left open for the caller to
  /// manage.
  void close() {
    if (_ownsApiClient) _apiClient.close();
  }
}

/// Result of [ItemCatalogueSearchService._fetchAllGroupPages]: either every
/// page was fetched and validated ([complete] `true`, [groups] populated),
/// or the fetch was abandoned because the backend's pagination metadata
/// could not be trusted or the defensive page cap was hit ([complete]
/// `false`, [groups] always empty).
class _GroupPageFetch {
  const _GroupPageFetch.complete(this.groups) : complete = true;

  const _GroupPageFetch.incomplete() : complete = false, groups = const [];

  final bool complete;
  final List<BusinessCentralItemSearchGroup> groups;
}
