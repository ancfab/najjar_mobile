/// Purpose: The single frontend contract Scan Stock's camera/barcode scan
/// path and manual-entry fallback both call to resolve a raw scanned/typed
/// code into stock information — see [StockLookupService.lookup].
///
/// CONFIRMED(stock-lookup contract): the identity carried by a decoded/typed
/// code is an exact Business Central `itemNo` — never `commonItemNo`,
/// `gtin`, a batch/lot reference, or a sales/purchase-order `No`. The
/// production implementation, `ApiStockLookupService`, resolves it via
/// `GET /api/business-central/inventory?item_no=...`. This file stays the
/// shared frontend contract so [ScanStockScreen] never depends on
/// `ApiStockLookupService`/`InventoryService` directly.
/// [UnconfiguredStockLookupService] remains for tests/backward compatibility
/// only — it is no longer the production default.
library;

/// Sealed outcome of one [StockLookupService.lookup] call. The UI switches
/// on the concrete subtype rather than inspecting a status code/string, so
/// every call site is forced to handle every outcome explicitly.
sealed class StockLookupResult {
  const StockLookupResult(this.rawCode);

  /// The trimmed raw code the lookup was performed for (as scanned or
  /// typed) — always present, even on failure, so the UI can show the user
  /// what was searched for.
  final String rawCode;
}

/// One location/unit-of-measure's aggregated open remaining quantity for a
/// single [StockLookupSuccess] — see [StockLookupSuccess.availabilityByLocation].
///
/// Represents the sum of every open inventory row sharing the same
/// [locationCode]/[unitOfMeasureCode] pair for the looked-up item. Different
/// locations, and different units of measure at the same location, are
/// always kept as separate entries — never combined into one total.
final class StockLocationAvailability {
  const StockLocationAvailability({
    required this.locationCode,
    required this.remainingQuantity,
    required this.unitOfMeasureCode,
  });

  final String locationCode;
  final num remainingQuantity;
  final String unitOfMeasureCode;

  /// The only Business Central [unitOfMeasureCode] value confirmed (across
  /// every fixture/tested payload) to represent meters — see this class's
  /// doc comment. No other observed code (e.g. `YD`, `PCS`) is meters, so
  /// [isLowStockInMeters] must never fire for them.
  static const String _metersUnitOfMeasureCode = 'MT';

  /// The low-stock threshold, in meters: at or below this quantity, the
  /// exact figure must not be shown to the user (see [isLowStockInMeters]).
  /// CONFIRMED business rule: `quantity > 100` is "Available" with the real
  /// quantity shown; `quantity <= 100` hides the quantity entirely.
  static const num lowStockThresholdMeters = 100;

  /// True when [unitOfMeasureCode] is meters — the single source of truth
  /// every screen displaying per-location availability must check to tell
  /// apart "MT, available" from "not MT" before choosing a visual
  /// available/warning treatment (green/yellow background, etc.): unlike
  /// [isLowStockInMeters], this is `true` for an above-threshold MT entry
  /// too, so `!isLowStockInMeters` must never be read as "should render as
  /// the MT-available state" — a non-MT entry also makes that `true` while
  /// meaning something else entirely (no MT threshold rule applies at all).
  bool get isMeasuredInMeters => unitOfMeasureCode == _metersUnitOfMeasureCode;

  /// True when this entry is measured in meters and [remainingQuantity] is
  /// at or below [lowStockThresholdMeters] — the single source of truth
  /// every screen displaying per-location availability (`ScanStockScreen`,
  /// the Home screen's Check Availability card) must branch on instead of
  /// duplicating the `> 100` comparison. Always `false` for a non-meters
  /// [unitOfMeasureCode] — this rule is meters-specific and must not affect
  /// other units of measure (e.g. yards, pieces).
  bool get isLowStockInMeters =>
      isMeasuredInMeters && remainingQuantity <= lowStockThresholdMeters;

  @override
  bool operator ==(Object other) =>
      other is StockLocationAvailability &&
      other.locationCode == locationCode &&
      other.remainingQuantity == remainingQuantity &&
      other.unitOfMeasureCode == unitOfMeasureCode;

  @override
  int get hashCode =>
      Object.hash(locationCode, remainingQuantity, unitOfMeasureCode);

  @override
  String toString() =>
      'StockLocationAvailability(locationCode: $locationCode, '
      'remainingQuantity: $remainingQuantity, '
      'unitOfMeasureCode: $unitOfMeasureCode)';
}

/// A stock record was found for [rawCode].
///
/// Every field besides [rawCode]/[scannedAt]/[availabilityByLocation] is
/// nullable and must only be populated with a value actually returned by the
/// lookup implementation — never a placeholder/fake value invented to make
/// the result card look more complete. [batchReference] in particular has no
/// documented source field on the confirmed inventory contract (see
/// `ApiStockLookupService`) and must stay `null` in production.
class StockLookupSuccess extends StockLookupResult {
  const StockLookupSuccess(
    super.rawCode, {
    required this.scannedAt,
    this.itemNo,
    this.description,
    this.batchReference,
    this.availabilityByLocation = const [],
    this.expectedRestockDate,
  });

  /// When this lookup completed, for display and for [scannedAt] on the
  /// persisted last-scan record.
  final DateTime scannedAt;

  final String? itemNo;
  final String? description;
  final String? batchReference;

  /// Open remaining quantity, aggregated by (location, unit of measure) —
  /// see [StockLocationAvailability]. Empty when the lookup implementation
  /// has no per-location breakdown to report (e.g. a fake used by a test
  /// that doesn't exercise availability display).
  final List<StockLocationAvailability> availabilityByLocation;

  /// TODO(expected-restock-date): the earliest expected incoming-stock date
  /// for this item, shown beside an out-of-stock status on the Home Check
  /// Availability card. No ANC API endpoint exposes purchase-order /
  /// replenishment receipt dates yet, so `ApiStockLookupService` always
  /// leaves this `null`; populate it here (and render it in
  /// `home_screen.dart`'s status pill) once such an endpoint exists.
  final DateTime? expectedRestockDate;

  /// A single, location-agnostic availability classification for this item,
  /// summing every location's open remaining quantity — the Home Check
  /// Availability card shows one status per variation, never a per-location
  /// breakdown.
  ///
  /// The MT threshold rule is unchanged (see
  /// [StockLocationAvailability.lowStockThresholdMeters]); it is applied to
  /// the *summed* meters quantity here:
  /// - Any meters (`MT`) entries → classify on their summed remaining
  ///   quantity: `> 100` [StockAvailabilityLevel.available], `0 < q <= 100`
  ///   [StockAvailabilityLevel.low], `<= 0` [StockAvailabilityLevel.outOfStock].
  /// - No meters entries, but other units summing above zero →
  ///   [StockAvailabilityLevel.available].
  /// - Nothing left anywhere (no entries, or every summed quantity `<= 0`) →
  ///   [StockAvailabilityLevel.outOfStock].
  ///
  /// Never exposes the underlying quantity — callers render a status label
  /// and colour only.
  StockAvailabilityLevel get combinedAvailabilityLevel {
    final meters = availabilityByLocation
        .where((entry) => entry.isMeasuredInMeters)
        .toList(growable: false);
    if (meters.isNotEmpty) {
      final metersTotal = meters.fold<num>(
        0,
        (sum, entry) => sum + entry.remainingQuantity,
      );
      if (metersTotal <= 0) return StockAvailabilityLevel.outOfStock;
      if (metersTotal <= StockLocationAvailability.lowStockThresholdMeters) {
        return StockAvailabilityLevel.low;
      }
      return StockAvailabilityLevel.available;
    }

    final otherTotal = availabilityByLocation.fold<num>(
      0,
      (sum, entry) => sum + entry.remainingQuantity,
    );
    if (availabilityByLocation.isEmpty || otherTotal <= 0) {
      return StockAvailabilityLevel.outOfStock;
    }
    return StockAvailabilityLevel.available;
  }
}

/// The single, location-agnostic availability status shown per variation on
/// the Home Check Availability card — see
/// [StockLookupSuccess.combinedAvailabilityLevel]. Deliberately does not
/// carry the underlying quantity: the UI renders only a label and colour.
enum StockAvailabilityLevel {
  /// Summed remaining quantity is above the low-stock threshold (or the item
  /// is stocked in a non-meters unit with a positive total).
  available,

  /// Summed meters quantity is at/below the low-stock threshold but above
  /// zero — the UI shows "contact support" copy, never the figure.
  low,

  /// Nothing remaining across any location.
  outOfStock,
}

/// The lookup completed but found no stock record for [rawCode].
class StockLookupNotFound extends StockLookupResult {
  const StockLookupNotFound(super.rawCode);
}

/// [rawCode] itself failed validation before any lookup was attempted (e.g.
/// empty after trimming) — distinct from a failed/absent API result.
class StockLookupInvalidCode extends StockLookupResult {
  const StockLookupInvalidCode(super.rawCode);
}

/// A transient failure (network/protocol/unexpected HTTP status) that is
/// reasonable to retry.
class StockLookupRetryableFailure extends StockLookupResult {
  const StockLookupRetryableFailure(super.rawCode);
}

/// The backing service is reachable but reports itself temporarily
/// unavailable (e.g. the confirmed HTTP 503 case already mapped by
/// `mapBusinessCentralError`).
class StockLookupTemporarilyUnavailable extends StockLookupResult {
  const StockLookupTemporarilyUnavailable(super.rawCode);
}

/// The authenticated session is no longer valid. Mirrors
/// `SessionExpiredException`: a real adapter is expected to hand off to the
/// session coordinator itself (navigating to Login) before returning this,
/// so the UI treats it as "nothing to show here" rather than an error panel.
class StockLookupSessionExpired extends StockLookupResult {
  const StockLookupSessionExpired(super.rawCode);
}

/// The scan/manual code identity cannot be resolved to a lookup yet because
/// no production matching adapter is configured — returned by
/// [UnconfiguredStockLookupService]. Distinct from
/// [StockLookupRetryableFailure]: retrying will not help until a real
/// adapter is wired in.
class StockLookupMappingNotConfigured extends StockLookupResult {
  const StockLookupMappingNotConfigured(super.rawCode);
}

/// A failure that does not fit any other category above.
class StockLookupUnexpectedFailure extends StockLookupResult {
  const StockLookupUnexpectedFailure(super.rawCode);
}

/// Injectable seam [ScanStockScreen] depends on for every stock lookup —
/// camera/barcode detection and manual entry alike — instead of talking to
/// `ItemsService`/`InventoryService` directly. See the library doc comment
/// for why no implementation here can yet perform a real match.
abstract class StockLookupService {
  /// Resolves [rawCode] (already trimmed and confirmed non-empty by the
  /// caller) to a [StockLookupResult]. Never throws for an expected failure
  /// mode — every expected outcome is a [StockLookupResult] subtype;
  /// implementations should only let a truly unexpected exception escape,
  /// which callers treat the same as [StockLookupUnexpectedFailure].
  Future<StockLookupResult> lookup(String rawCode);
}

/// The only [StockLookupService] implementation until the scan/manual code
/// identity and a server-side lookup contract are confirmed (see the
/// library doc comment). Returns a controlled, localized "mapping not
/// configured" result instead of crashing, guessing a matching rule, or
/// paging through every `/items`/`/inventory` row to fake a client-side
/// search.
///
/// A future real adapter can reuse `ItemsService`/`InventoryService` behind
/// this same [StockLookupService] interface without any change to
/// [ScanStockScreen] or its tests (which depend only on the interface via
/// an injected fake).
class UnconfiguredStockLookupService implements StockLookupService {
  const UnconfiguredStockLookupService();

  @override
  Future<StockLookupResult> lookup(String rawCode) async {
    return StockLookupMappingNotConfigured(rawCode);
  }
}
