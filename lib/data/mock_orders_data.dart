import '../models/fabric_order.dart';
import '../models/fabric_specs.dart';
import '../models/order_price_breakdown.dart';

// TODO: Replace mock orders data with backend Orders list API once the
// endpoint is confirmed.
// TODO: Confirm date formatting rules with business team.

const List<String> _mockMonthAbbreviations = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// Formats a [DateTime] to match the display style already used by the
/// fixed mock dates below (e.g. "Oct 12, 2023").
String _formatMockDate(DateTime date) {
  final month = _mockMonthAbbreviations[date.month - 1];
  return '$month ${date.day}, ${date.year}';
}

final DateTime _mockNow = DateTime.now();

/// Original fixed mock Fabric Orders, unchanged since earlier tasks.
///
/// Most orders use fixed 2023 dates. `#ORD-9101` and `#ORD-9102` use dates
/// computed relative to [DateTime.now()] instead, so the "Last 7 days" /
/// "Last 30 days" date-range filters always have at least one real match to
/// filter against, regardless of when the app or its tests are run.
final List<FabricOrder> _fixedMockFabricOrders = [
  FabricOrder(
    orderId: '#ORD-8829',
    date: 'Oct 12, 2023',
    orderDate: DateTime(2023, 10, 12),
    status: OrderStatus.delivered,
    fabricTag: 'Premium Cotton Twill',
    fabricType: 'Cotton',
    meters: '280 meters',
    price: '\$4,800.00',
  ),
  FabricOrder(
    orderId: '#ORD-8830',
    date: 'Oct 18, 2023',
    orderDate: DateTime(2023, 10, 18),
    status: OrderStatus.shipped,
    fabricTag: 'Italian Wool Blend',
    fabricType: 'Wool',
    meters: '150 meters',
    price: '\$6,200.00',
  ),
  FabricOrder(
    orderId: '#ORD-8831',
    date: 'Oct 22, 2023',
    orderDate: DateTime(2023, 10, 22),
    status: OrderStatus.processing,
    fabricTag: 'Egyptian Linen',
    fabricType: 'Linen',
    meters: '320 meters',
    price: '\$3,950.00',
  ),
  FabricOrder(
    orderId: '#ORD-9101',
    date: _formatMockDate(_mockNow.subtract(const Duration(days: 2))),
    orderDate: _mockNow.subtract(const Duration(days: 2)),
    status: OrderStatus.processing,
    fabricTag: 'Recycled Polyester Mesh',
    fabricType: 'Polyester',
    meters: '95 meters',
    price: '\$1,275.00',
  ),
  FabricOrder(
    orderId: '#ORD-9102',
    date: _formatMockDate(_mockNow.subtract(const Duration(days: 20))),
    orderDate: _mockNow.subtract(const Duration(days: 20)),
    status: OrderStatus.delivered,
    fabricTag: 'Bamboo Silk Charmeuse',
    fabricType: 'Silk',
    meters: '60 meters',
    price: '\$2,640.00',
  ),
];

/// (fabricType, status) pairs used to build [_generatedMockFabricOrders]
/// below. Each fabric type always maps to the same status — deterministic
/// on purpose, so which status/fabric-type combinations do or don't exist
/// in the generated set is predictable (e.g. no generated order is ever
/// "Wool" + "Delivered", matching the fixed `#ORD-8830` Wool/Shipped order
/// above) instead of depending on modulo-cycle coincidences.
///
/// Silk is intentionally left out of this pool — it stays exclusive to the
/// fixed `#ORD-9102` (Silk/Delivered) order above.
///
/// TODO: Confirm the official fabric type/category values with the
/// backend/API team before connecting live data.
const List<(String fabricType, OrderStatus status)> _generatedTypeStatusPairs =
    [
      ('Cotton', OrderStatus.delivered),
      ('Wool', OrderStatus.shipped),
      ('Linen', OrderStatus.processing),
      ('Polyester', OrderStatus.processing),
      ('Denim', OrderStatus.shipped),
      ('Velvet', OrderStatus.delivered),
    ];

/// Number of synthetic orders generated below, on top of the 5 fixed
/// orders above. Chosen so the combined mock dataset totals 248 orders —
/// enough to exercise multi-page pagination (e.g. "Showing 10 of 248
/// orders" at the default page size of 10) without a real backend.
const int _kGeneratedOrderCount = 243;

/// Synthetic Fabric Orders generated purely to give the Orders list
/// pagination UI a large, realistic result set to page/filter/search
/// through. Order IDs continue on from the fixed orders' `#ORD-92xx`
/// range, dates are spaced a few days apart starting after the fixed
/// orders' dates, and fabric type/status cycle through
/// [_generatedTypeStatusPairs] so every fabric type has many matching
/// orders spread across multiple pages.
final List<FabricOrder> _generatedMockFabricOrders = List.generate(
  _kGeneratedOrderCount,
  (index) {
    final pair = _generatedTypeStatusPairs[index % _generatedTypeStatusPairs.length];
    final orderNumber = 9200 + index;
    final orderDate = DateTime(2023, 1, 1).add(Duration(days: index * 3));
    final meters = 60 + (index % 40) * 5;
    final price = 900 + (index * 37) % 5000;
    return FabricOrder(
      orderId: '#ORD-$orderNumber',
      date: _formatMockDate(orderDate),
      orderDate: orderDate,
      status: pair.$2,
      fabricTag: '${pair.$1} Batch ${index + 1}',
      fabricType: pair.$1,
      meters: '$meters meters',
      price: '\$$price.00',
    );
  },
);

/// Full mock Fabric Orders dataset used by [MockOrdersService]: the 5 fixed
/// orders followed by the generated pagination filler set. See
/// [_fixedMockFabricOrders] and [_generatedMockFabricOrders] above for how
/// each half is built.
///
/// TODO: Replace with the backend Orders list API response once the
/// endpoint is confirmed; this generated filler set only exists to make
/// pagination testable without a real API.
final List<FabricOrder> kMockFabricOrders = List.unmodifiable([
  ..._fixedMockFabricOrders,
  ..._generatedMockFabricOrders,
]);

/// Distinct fabric type/category values available across the mock orders
/// dataset, used to populate the Fabric Type filter section.
///
/// TODO: Confirm the official fabric type/category values with the
/// backend/API team before connecting live data.
List<String> get kMockFabricTypes =>
    kMockFabricOrders.map((order) => order.fabricType).toSet().toList()
      ..sort();

// ---------------------------------------------------------------------------
// Order Detail mock data (Price Breakdown card + Fabric Specs bottom sheet).
// ---------------------------------------------------------------------------
//
// TODO: Replace mock price breakdown values with the real order detail API
// once subtotal, shipping, VAT, total amount, currency, and invoice
// availability fields are confirmed.
// TODO: Replace mock fabric specs with real fabric specification fields
// once the backend/API response shape is confirmed.

/// Mock color per fabric type, used to fill in [FabricSpecs.color] since no
/// per-order color field exists yet.
///
/// TODO: Confirm fabric color values with the backend/API team; this is a
/// coarse fabric-type-based guess purely for mock display purposes.
const Map<String, String> _mockColorByFabricType = {
  'Cotton': 'Ivory White',
  'Wool': 'Charcoal Grey',
  'Linen': 'Natural Beige',
  'Polyester': 'Slate Blue',
  'Denim': 'Indigo Blue',
  'Velvet': 'Deep Burgundy',
  'Silk': 'Champagne Gold',
};

/// Mock composition per fabric type, used to fill in
/// [FabricSpecs.composition] since no per-order composition field exists
/// yet.
///
/// TODO: Confirm fabric composition values with the backend/API team; this
/// is a coarse fabric-type-based guess purely for mock display purposes.
const Map<String, String> _mockCompositionByFabricType = {
  'Cotton': '100% Cotton',
  'Wool': '90% Wool, 10% Nylon',
  'Linen': '100% Linen',
  'Polyester': '100% Recycled Polyester',
  'Denim': '98% Cotton, 2% Elastane',
  'Velvet': '80% Cotton, 20% Silk',
  'Silk': '100% Silk',
};

/// Parses a pre-formatted mock price string (e.g. "\$4,800.00") back into a
/// [double] so a shipping/VAT estimate can be derived from it. Only ever
/// used against this file's own mock currency strings, never external/API
/// input, so a permissive parse (falling back to 0) is safe here.
double _parseMockCurrency(String value) {
  final cleaned = value.replaceAll('\$', '').replaceAll(',', '');
  return double.tryParse(cleaned) ?? 0;
}

/// Formats a [double] as a mock "\$X,XXX.XX" currency string. Hand-rolled
/// (rather than using the `intl` package, which this project doesn't
/// currently depend on) since it only ever needs to format the small,
/// always-positive mock amounts derived in this file.
String _formatMockCurrency(double amount) {
  final rounded = (amount * 100).round() / 100;
  final wholePart = rounded.truncate().toString();
  final centsPart = ((rounded - rounded.truncate()) * 100)
      .round()
      .toString()
      .padLeft(2, '0');
  final buffer = StringBuffer();
  for (var i = 0; i < wholePart.length; i++) {
    if (i > 0 && (wholePart.length - i) % 3 == 0) buffer.write(',');
    buffer.write(wholePart[i]);
  }
  return '\$$buffer.$centsPart';
}

/// Builds a mock [OrderPriceBreakdown] for [order].
///
/// `#ORD-8829` returns the fixed example breakdown used while designing the
/// Price Breakdown card; every other order derives a shipping (5%) and VAT
/// (2.4%) estimate from [FabricOrder.price] so every mock order has a
/// plausible, non-hardcoded breakdown to display.
///
/// TODO: Replace mock price breakdown values with the real order detail API
/// once subtotal, shipping, VAT, total amount, currency, and invoice
/// availability fields are confirmed.
OrderPriceBreakdown buildMockPriceBreakdown(FabricOrder order) {
  if (order.orderId == '#ORD-8829') {
    return const OrderPriceBreakdown(
      subtotal: '\$4,800.00',
      shipping: '\$240.00',
      vat: '\$115.00',
      totalAmount: '\$5,155.00',
    );
  }
  final subtotalValue = _parseMockCurrency(order.price);
  final shippingValue = subtotalValue * 0.05;
  final vatValue = subtotalValue * 0.024;
  final totalValue = subtotalValue + shippingValue + vatValue;
  return OrderPriceBreakdown(
    subtotal: _formatMockCurrency(subtotalValue),
    shipping: _formatMockCurrency(shippingValue),
    vat: _formatMockCurrency(vatValue),
    totalAmount: _formatMockCurrency(totalValue),
  );
}

/// Builds mock [FabricSpecs] for [order] from its existing fabric tag/type/
/// meters fields, filled out with a coarse fabric-type-based color and
/// composition guess.
///
/// TODO: Replace mock fabric specs with real fabric specification fields
/// once the backend/API response shape is confirmed.
FabricSpecs buildMockFabricSpecs(FabricOrder order) {
  final orderNumber = order.orderId.replaceAll(RegExp(r'[^0-9]'), '');
  return FabricSpecs(
    fabricName: order.fabricTag,
    sku: 'SKU-$orderNumber',
    color: _mockColorByFabricType[order.fabricType] ?? 'Not specified',
    weight: '320 GSM',
    quantity: order.meters,
    composition: _mockCompositionByFabricType[order.fabricType],
  );
}
