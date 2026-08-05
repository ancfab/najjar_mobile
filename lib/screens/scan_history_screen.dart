import 'package:flutter/material.dart';

import '../localization/translations.dart';
import '../services/last_scan_store.dart';
import '../services/scan_history_store.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import '../utils/date_time_format.dart';
import '../utils/responsive.dart';

/// Scan History screen: a dedicated full-screen list of every successful
/// Scan Stock lookup (camera or manual entry) recorded by [ScanHistoryStore],
/// newest first.
///
/// Local-device-only for this release — no scan-history API endpoint exists
/// or is assumed; see [ScanHistoryStore]'s doc comment. This screen never
/// makes a network request, so no session-expiry handling applies here.
///
/// One-time migration: if [historyStore] is empty on open and
/// [lastScanStore] holds a valid Recent Scan record, that single record is
/// added as the initial history entry so existing users don't start with an
/// empty history despite already having a Recent Scan. This only ever runs
/// while history is empty, so it can never duplicate the migrated record on
/// a later open (history is non-empty by then).
class ScanHistoryScreen extends StatefulWidget {
  const ScanHistoryScreen({
    super.key,
    ScanHistoryStore? historyStore,
    LastScanStore? lastScanStore,
  }) : historyStore = historyStore ?? const SharedPreferencesScanHistoryStore(),
       lastScanStore = lastScanStore ?? const SharedPreferencesLastScanStore();

  /// Scan-history persistence seam. Overridable so tests can inject a fake
  /// instead of touching the real shared_preferences platform channel.
  final ScanHistoryStore historyStore;

  /// Recent Scan persistence seam, read only for the one-time migration
  /// described in the class doc comment.
  final LastScanStore lastScanStore;

  @override
  State<ScanHistoryScreen> createState() => _ScanHistoryScreenState();
}

class _ScanHistoryScreenState extends State<ScanHistoryScreen> {
  /// `null` while the initial load is in flight; otherwise the loaded (or
  /// safely-empty-on-failure) history, newest first.
  List<PersistedScanRecord>? _records;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    List<PersistedScanRecord> records;
    try {
      records = await widget.historyStore.read();
      if (records.isEmpty) {
        final recent = await widget.lastScanStore.read();
        if (recent != null) {
          await widget.historyStore.append(recent);
          records = await widget.historyStore.read();
        }
      }
    } catch (error) {
      // A corrupt/unreadable local store must not crash this screen; it's
      // no worse than there being no history at all.
      debugPrint('Failed to load scan history: $error');
      records = const [];
    }
    if (!mounted) return;
    setState(() => _records = records);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: AppColors.textNavy,
        elevation: 0,
        title: Text(context.t('scanHistory.title')),
      ),
      body: SafeArea(top: false, child: _buildBody()),
    );
  }

  Widget _buildBody() {
    final records = _records;
    if (records == null) {
      return const Center(
        key: ValueKey('scan-history-loading'),
        child: CircularProgressIndicator(),
      );
    }
    if (records.isEmpty) {
      return _buildEmptyState(context);
    }
    return ResponsiveMaxWidth(
      child: ListView.separated(
        key: const ValueKey('scan-history-list'),
        padding: const EdgeInsets.all(AppSpacing.lg),
        itemCount: records.length,
        separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
        itemBuilder: (context, index) => _ScanHistoryRow(
          key: ValueKey('scan-history-row-$index'),
          record: records[index],
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.history_rounded,
              color: AppColors.grayText,
              size: 28,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              context.t('scanHistory.emptyMessage'),
              key: const ValueKey('scan-history-empty-state'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.grayText),
            ),
          ],
        ),
      ),
    );
  }
}

/// One history record: raw code (LTR, prominent) plus the timestamp and
/// every optional field actually present — item number, description,
/// batch/reference. Never renders quantity, location, unit, or an
/// availability/status label; the list itself already contains only
/// successful scans.
class _ScanHistoryRow extends StatelessWidget {
  const _ScanHistoryRow({super.key, required this.record});

  final PersistedScanRecord record;

  @override
  Widget build(BuildContext context) {
    final rows = _detailRows(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Directionality(
            textDirection: TextDirection.ltr,
            child: Text(
              record.rawCode,
              key: const ValueKey('scan-history-row-raw-code'),
              style: AppTypography.cardTitle.copyWith(
                color: AppColors.textNavy,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Directionality(
            textDirection: TextDirection.ltr,
            child: Text(
              '${context.t('scanHistory.scannedAtLabel')}: '
              '${formatCompactLocalTimestamp(record.scannedAt)}',
              key: const ValueKey('scan-history-row-timestamp'),
              style: AppTypography.caption,
            ),
          ),
          for (final row in rows) ...[
            const SizedBox(height: AppSpacing.xs),
            _HistoryDetailRow(data: row),
          ],
        ],
      ),
    );
  }

  List<_HistoryRowData> _detailRows(BuildContext context) {
    final itemNo = record.itemNo;
    final description = record.description;
    final batchReference = record.batchReference;

    return [
      if (itemNo != null && itemNo.isNotEmpty)
        _HistoryRowData(
          context.t('scanStock.itemNumberLabel'),
          itemNo,
          key: 'item-number',
        ),
      if (description != null && description.isNotEmpty)
        _HistoryRowData(
          context.t('scanStock.itemFabricLabel'),
          description,
          key: 'description',
        ),
      if (batchReference != null && batchReference.isNotEmpty)
        _HistoryRowData(
          context.t('scanStock.batchReferenceLabel'),
          batchReference,
          key: 'batch-reference',
        ),
    ];
  }
}

class _HistoryRowData {
  const _HistoryRowData(this.label, this.value, {required this.key});

  final String label;
  final String value;
  final String key;
}

class _HistoryDetailRow extends StatelessWidget {
  const _HistoryDetailRow({required this.data});

  final _HistoryRowData data;

  @override
  Widget build(BuildContext context) {
    return Row(
      key: ValueKey('scan-history-row-${data.key}'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 100,
          child: Text(
            data.label,
            style: AppTypography.bodySecondary.copyWith(
              color: AppColors.grayText,
            ),
          ),
        ),
        Expanded(
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Text(
              data.value,
              style: AppTypography.body.copyWith(color: AppColors.textNavy),
            ),
          ),
        ),
      ],
    );
  }
}
