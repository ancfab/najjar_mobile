import 'package:flutter/material.dart';

import '../localization/translations.dart';
import '../theme/app_colors.dart';
import '../utils/responsive.dart';

// TODO(mock-data): Placeholder for the most recent scan record. Replace
// with the real last-scan entry from the scan history/stock service once
// that API exists.
const String _kRecentScanItemLabel = 'Indigo Denim - Batch #4421';

/// Scan Stock screen.
///
/// Frontend-only for now: no camera/QR scanning dependency currently
/// exists in this project (see pubspec.yaml), so this screen renders the
/// scanning UI (dark background, framing overlay, instructions) without a
/// live camera preview.
///
/// TODO: Once a scanner dependency (e.g. mobile_scanner) is approved and
/// added, replace the placeholder background in [_ScanPreviewArea] with a
/// live camera preview, including Android/iOS camera permission handling.
class ScanStockScreen extends StatelessWidget {
  const ScanStockScreen({super.key});

  // Handles a completed scan by checking fabric stock availability.
  // TODO: Wire this to the real scan-result handling and stock
  // availability API once camera scanning is integrated.
  void _checkStockAvailability(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.t('scanStock.stockCheckComingSoon'))),
    );
  }

  // Opens the full scan history list.
  // TODO: Navigate to a real Scan History screen once it exists.
  void _openScanHistory(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.t('scanStock.scanHistoryComingSoon'))),
    );
  }

  // Toggles the camera torch/flash while scanning.
  // TODO: Wire this to the real camera flash control once a scanner
  // dependency is integrated.
  void _toggleFlash(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.t('scanStock.flashToggleComingSoon'))),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primaryNavy,
      appBar: AppBar(
        backgroundColor: AppColors.primaryNavy,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(context.t('scanStock.title')),
        actions: [
          IconButton(
            icon: const Icon(Icons.flash_on_rounded),
            tooltip: context.t('scanStock.toggleFlashTooltip'),
            onPressed: () => _toggleFlash(context),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _ScanPreviewArea(
              onCheckAvailability: _checkStockAvailability,
            ),
          ),
          _RecentScanCard(onViewHistory: _openScanHistory),
        ],
      ),
    );
  }
}

// Dark scanning viewport with the centered QR frame overlay and
// instructions. Isolated so the placeholder background is easy to find
// and swap for a real camera preview later.
class _ScanPreviewArea extends StatelessWidget {
  const _ScanPreviewArea({required this.onCheckAvailability});

  final void Function(BuildContext context) onCheckAvailability;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      // TODO: Replace this solid color with a live camera preview once a
      // scanner dependency is integrated.
      color: AppColors.gradientNavyStart,
      child: ResponsiveMaxWidth(
        maxWidth: 480,
        alignment: Alignment.center,
        child: CenteredScrollable(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const _QrFrame(),
              const SizedBox(height: 24),
              Text(
                context.t('scanStock.centerQrInstruction'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 14),
              ),
              const SizedBox(height: 20),
              TextButton(
                onPressed: () => onCheckAvailability(context),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 10,
                  ),
                ),
                child: Text(
                  context.t('scanStock.checkStockButton'),
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Square framing overlay shown over the (placeholder) scan area to guide
// the user to center a QR code.
class _QrFrame extends StatelessWidget {
  const _QrFrame();

  static const double _size = 220;
  static const double _cornerLength = 28;
  static const double _cornerThickness = 4;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _size,
      height: _size,
      child: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white24, width: 1),
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          for (final alignment in const [
            Alignment.topLeft,
            Alignment.topRight,
            Alignment.bottomLeft,
            Alignment.bottomRight,
          ])
            Align(
              alignment: alignment,
              child: _FrameCorner(alignment: alignment),
            ),
        ],
      ),
    );
  }
}

class _FrameCorner extends StatelessWidget {
  const _FrameCorner({required this.alignment});

  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    final isTop = alignment.y < 0;
    final isLeft = alignment.x < 0;
    return SizedBox(
      width: _QrFrame._cornerLength,
      height: _QrFrame._cornerLength,
      child: Stack(
        children: [
          Positioned(
            top: isTop ? 0 : null,
            bottom: isTop ? null : 0,
            left: 0,
            right: 0,
            child: Container(
              height: _QrFrame._cornerThickness,
              color: Colors.white,
            ),
          ),
          Positioned(
            left: isLeft ? 0 : null,
            right: isLeft ? null : 0,
            top: 0,
            bottom: 0,
            child: Container(
              width: _QrFrame._cornerThickness,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

// Bottom card showing the most recent scan and a link to full history.
class _RecentScanCard extends StatelessWidget {
  const _RecentScanCard({required this.onViewHistory});

  final void Function(BuildContext context) onViewHistory;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    context.t('scanStock.recentScanLabel'),
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.1,
                      color: AppColors.grayText,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    _kRecentScanItemLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textNavy,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: () => onViewHistory(context),
              child: Text(
                context.t('scanStock.viewHistoryButton'),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
