// Fake ItemCatalogueSearchService for Home Check Availability widget tests —
// mirrors FakeStockLookupService's convention (queued results, a default
// builder, a gate to control when a call resolves, and a call log) so tests
// never exercise real HTTP/secure storage.

import 'dart:async';

import 'package:anc_fabrics/services/item_catalogue_search_service.dart';

class FakeItemCatalogueSearchService implements ItemCatalogueSearchService {
  FakeItemCatalogueSearchService();

  /// Queue of results to return, one per call, in order. If exhausted,
  /// [defaultResultBuilder] is used instead.
  final List<ItemCatalogueSearchResult> queuedResults = [];

  /// Falls back to this when [queuedResults] is empty; defaults to
  /// [ItemCatalogueNoResults] echoing the raw query.
  ItemCatalogueSearchResult Function(String rawQuery) defaultResultBuilder =
      ItemCatalogueNoResults.new;

  /// Every query [search] has been called with, in call order.
  final List<String> calls = [];

  /// When set, [search] does not complete until this completer completes —
  /// lets a test observe the loading state and control exactly when the
  /// search resolves.
  Completer<void>? gate;

  int get callCount => calls.length;

  @override
  Future<ItemCatalogueSearchResult> search(String rawQuery) async {
    calls.add(rawQuery);
    if (gate != null) await gate!.future;
    if (queuedResults.isNotEmpty) return queuedResults.removeAt(0);
    return defaultResultBuilder(rawQuery);
  }
}
