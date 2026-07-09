import 'package:flutter/material.dart';

import '../models/fabric_order.dart';
import '../theme/app_colors.dart';
import 'status_badge.dart';

/// Card summarizing a single [FabricOrder] on the Fabric Orders list.
class OrderCard extends StatelessWidget {
  const OrderCard({super.key, required this.order, this.onTap});

  final FabricOrder order;

  /// Called when the card is tapped. Typically navigates to the Order
  /// Detail screen for [order]; left null wherever the card is shown
  /// read-only.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: _buildCardContent(),
      ),
    );
  }

  Widget _buildCardContent() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildThumbnail(),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        // Displayed without the stored "#" prefix (e.g.
                        // "#ORD-8829" -> "ORD-8829"); see [displayOrderId].
                        displayOrderId(order.orderId),
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textNavy,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    StatusBadge(status: order.status),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  order.date,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.grayText,
                  ),
                ),
                const SizedBox(height: 12),
                const Divider(height: 1, color: AppColors.border),
                const SizedBox(height: 12),
                _buildFabricChip(),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Text(
                        order.meters,
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
                          color: AppColors.grayText,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerRight,
                        child: Text(
                          order.price,
                          maxLines: 1,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: AppColors.primaryNavy,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Small light "pill" chip showing the order's fabric type/tag (e.g.
  /// "Premium Cotton Twill"), sized to its content rather than the full
  /// card width.
  Widget _buildFabricChip() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.border),
      ),
      child: Text(
        order.fabricTag,
        style: const TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          color: AppColors.textNavy,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  /// Builds the order thumbnail.
  ///
  /// Falls back to a neutral placeholder icon whenever
  /// [FabricOrder.thumbnailUrl] is missing/empty (the current mock-only
  /// state — no image asset pipeline or CDN exists yet) or fails to load
  /// (e.g. once a real image URL is wired up and the network request
  /// errors), so a broken or absent thumbnail can never break the card
  /// layout.
  Widget _buildThumbnail() {
    final url = order.thumbnailUrl;
    return Container(
      width: 56,
      height: 56,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: (url == null || url.isEmpty)
          ? _buildThumbnailFallback()
          : Image.network(
              url,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) =>
                  _buildThumbnailFallback(),
              loadingBuilder: (context, child, progress) {
                if (progress == null) return child;
                return const Center(
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                );
              },
            ),
    );
  }

  /// Neutral placeholder shown in place of a fabric thumbnail image; see
  /// [_buildThumbnail] for when this is used.
  Widget _buildThumbnailFallback() {
    return const Icon(Icons.texture_rounded, color: AppColors.grayText);
  }
}
