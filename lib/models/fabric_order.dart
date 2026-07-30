import 'package:flutter/widgets.dart';

import '../localization/translations.dart';

/// Order status as understood by the Fabric Orders UI.
///
/// TODO: Confirm the complete list of possible order statuses with the
/// backend/API team before connecting live data. Only Delivered, Shipped,
/// and Processing are confirmed for the current mock design; [unknown] is
/// the safe fallback for any raw status value not yet recognized.
enum OrderStatus { delivered, shipped, processing, unknown }

/// Maps a raw/mock order status string (as it might arrive from a backend
/// API) to the typed [OrderStatus] used by the UI.
///
/// This mapping is temporary and mock-only until the backend/API team
/// confirms the full set of order status values. Anything not explicitly
/// recognized here safely falls back to [OrderStatus.unknown] instead of
/// throwing, so an unexpected backend value can never crash the UI.
OrderStatus mapOrderStatus(String rawStatus) {
  switch (rawStatus.trim().toLowerCase()) {
    case 'delivered':
      return OrderStatus.delivered;
    case 'shipped':
      return OrderStatus.shipped;
    case 'processing':
      return OrderStatus.processing;
    default:
      return OrderStatus.unknown;
  }
}

/// Human-readable (English) label for an [OrderStatus]. Used only for
/// mock/local search-matching (see `MockOrdersService`) where no
/// [BuildContext] is available — UI display always goes through
/// [localizedOrderStatusLabel] instead so the shown text is translated.
String orderStatusLabel(OrderStatus status) {
  switch (status) {
    case OrderStatus.delivered:
      return 'Delivered';
    case OrderStatus.shipped:
      return 'Shipped';
    case OrderStatus.processing:
      return 'Processing';
    case OrderStatus.unknown:
      return 'Unknown';
  }
}

/// Localized display label for an [OrderStatus]. Shared by [StatusBadge],
/// the Orders filter UI, and the active-filter chip so the display text
/// only lives in one place.
String localizedOrderStatusLabel(BuildContext context, OrderStatus status) {
  switch (status) {
    case OrderStatus.delivered:
      return context.t('orderStatus.delivered');
    case OrderStatus.shipped:
      return context.t('orderStatus.shipped');
    case OrderStatus.processing:
      return context.t('orderStatus.processing');
    case OrderStatus.unknown:
      return context.t('orderStatus.unknown');
  }
}

/// Formats a stored [FabricOrder.orderId] for display only (e.g.
/// "#ORD-8829" -> "ORD-8829"). Search/filter matching in
/// [MockOrdersService] still operates on the raw stored value, so this is
/// purely cosmetic and never affects search/filter behavior.
String displayOrderId(String orderId) {
  return orderId.startsWith('#') ? orderId.substring(1) : orderId;
}

/// A single fabric order shown on the Fabric Orders list screen.
///
/// TODO: Replace with a backend-shaped model (likely with a `fromJson`
/// factory) once the Orders API response format is confirmed.
class FabricOrder {
  const FabricOrder({
    required this.orderId,
    required this.date,
    required this.orderDate,
    required this.status,
    required this.fabricTag,
    required this.fabricType,
    required this.meters,
    required this.price,
    this.thumbnailUrl,
  });

  final String orderId;

  /// Pre-formatted display date (e.g. "Oct 12, 2023"), shown on the order
  /// card and matched against by free-text search.
  final String date;

  /// Machine-readable date used for the date-range filter. Kept separate
  /// from [date] so date-range math never has to parse the display string.
  final DateTime orderDate;

  final OrderStatus status;
  final String fabricTag;

  /// Coarse fabric type/category used for the frontend Fabric Type filter.
  ///
  /// TODO: Confirm the official fabric type/category values with the
  /// backend/API team before connecting live data.
  final String fabricType;

  final String meters;
  final String price;

  /// Optional fabric thumbnail image URL.
  ///
  /// TODO: No image asset pipeline or CDN exists yet, so this stays null
  /// for every current mock order. Once the backend/API team confirms how
  /// thumbnails are served, this can be populated with the real URL —
  /// [OrderCard] already falls back to a neutral placeholder icon whenever
  /// this is null/empty or the image fails to load, so no UI changes
  /// should be needed to turn real thumbnails on.
  final String? thumbnailUrl;
}
