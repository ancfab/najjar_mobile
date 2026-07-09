import 'fabric_order.dart';
import 'fabric_specs.dart';
import 'order_price_breakdown.dart';

/// Combined Order Detail data for a single order: the order summary plus
/// the price breakdown and fabric specs shown on the Order Detail screen.
///
/// TODO: Replace with a backend-shaped order detail model (likely with a
/// `fromJson` factory) once the Order Detail API response format is
/// confirmed.
class FabricOrderDetail {
  const FabricOrderDetail({
    required this.order,
    required this.priceBreakdown,
    required this.fabricSpecs,
  });

  final FabricOrder order;
  final OrderPriceBreakdown priceBreakdown;
  final FabricSpecs fabricSpecs;
}
