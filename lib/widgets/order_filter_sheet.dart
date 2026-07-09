import 'package:flutter/material.dart';

import '../models/fabric_order.dart';
import '../models/fabric_order_filter.dart';
import '../theme/app_colors.dart';

const List<OrderStatus?> _statusOptions = [
  null,
  OrderStatus.delivered,
  OrderStatus.shipped,
  OrderStatus.processing,
];

const List<DateRangeFilter> _dateRangeOptions = [
  DateRangeFilter.all,
  DateRangeFilter.last7Days,
  DateRangeFilter.last30Days,
  DateRangeFilter.custom,
];

/// Mobile-friendly bottom sheet for building a [FabricOrderFilter]: status,
/// date range (including a custom start/end range), and fabric type.
///
/// This only edits filter *sections* — free-text search has its own header
/// entry point on the Orders screen and is merged back in by the caller.
/// Returns the applied [FabricOrderFilter] via `Navigator.pop`, or `null`
/// if dismissed without applying.
class OrderFilterSheet extends StatefulWidget {
  const OrderFilterSheet({
    super.key,
    required this.initialFilter,
    required this.fabricTypeOptions,
  });

  final FabricOrderFilter initialFilter;
  final List<String> fabricTypeOptions;

  @override
  State<OrderFilterSheet> createState() => _OrderFilterSheetState();
}

class _OrderFilterSheetState extends State<OrderFilterSheet> {
  late OrderStatus? _status;
  late DateRangeFilter _dateRange;
  DateTime? _customStart;
  DateTime? _customEnd;
  String? _fabricType;

  @override
  void initState() {
    super.initState();
    _status = widget.initialFilter.status;
    _dateRange = widget.initialFilter.dateRange;
    _customStart = widget.initialFilter.customStartDate;
    _customEnd = widget.initialFilter.customEndDate;
    _fabricType = widget.initialFilter.fabricType;
  }

  // Clears every filter section and closes the sheet, restoring the Orders
  // list to the unfiltered mock data (search text is untouched by the
  // caller).
  void _reset() {
    Navigator.of(context).pop(const FabricOrderFilter());
  }

  // Commits the currently selected sections and closes the sheet.
  void _apply() {
    Navigator.of(context).pop(
      FabricOrderFilter(
        status: _status,
        dateRange: _dateRange,
        customStartDate: _dateRange == DateRangeFilter.custom
            ? _customStart
            : null,
        customEndDate: _dateRange == DateRangeFilter.custom
            ? _customEnd
            : null,
        fabricType: _fabricType,
      ),
    );
  }

  Future<void> _pickCustomStart() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _customStart ?? now,
      firstDate: DateTime(now.year - 5),
      lastDate: _customEnd ?? now,
    );
    if (picked != null) setState(() => _customStart = picked);
  }

  Future<void> _pickCustomEnd() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _customEnd ?? now,
      firstDate: _customStart ?? DateTime(now.year - 5),
      lastDate: now,
    );
    if (picked != null) setState(() => _customEnd = picked);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Filter Orders',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.textNavy,
              ),
            ),
            const SizedBox(height: 20),
            _sectionLabel('Status'),
            const SizedBox(height: 8),
            _buildStatusOptions(),
            const SizedBox(height: 20),
            _sectionLabel('Date Range'),
            const SizedBox(height: 8),
            _buildDateRangeOptions(),
            if (_dateRange == DateRangeFilter.custom) ...[
              const SizedBox(height: 12),
              _buildCustomDateRow(),
            ],
            const SizedBox(height: 20),
            // Fabric type is a frontend/mock-only filter for now.
            // TODO: Confirm the official fabric type/category values with
            // the backend/API team before connecting live data.
            _sectionLabel('Fabric Type'),
            const SizedBox(height: 8),
            _buildFabricTypeOptions(),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    key: const ValueKey('filter-sheet-reset'),
                    onPressed: _reset,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.textNavy,
                      side: const BorderSide(color: AppColors.border),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const Text('Reset'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    key: const ValueKey('filter-sheet-apply'),
                    onPressed: _apply,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryNavy,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const Text('Apply'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(String label) {
    return Text(
      label,
      style: const TextStyle(
        fontSize: 12.5,
        fontWeight: FontWeight.w600,
        color: AppColors.grayText,
      ),
    );
  }

  Widget _buildStatusOptions() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final status in _statusOptions)
          _choiceChip(
            key: ValueKey(
              'filter-sheet-status-${status == null ? 'All' : orderStatusLabel(status)}',
            ),
            label: status == null ? 'All' : orderStatusLabel(status),
            selected: _status == status,
            onTap: () => setState(() => _status = status),
          ),
      ],
    );
  }

  Widget _buildDateRangeOptions() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final option in _dateRangeOptions)
          _choiceChip(
            key: ValueKey('filter-sheet-date-${option.name}'),
            label: dateRangeFilterLabel(option),
            selected: _dateRange == option,
            onTap: () => setState(() => _dateRange = option),
          ),
      ],
    );
  }

  Widget _buildFabricTypeOptions() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _choiceChip(
          key: const ValueKey('filter-sheet-fabric-type-All'),
          label: 'All',
          selected: _fabricType == null,
          onTap: () => setState(() => _fabricType = null),
        ),
        for (final type in widget.fabricTypeOptions)
          _choiceChip(
            key: ValueKey('filter-sheet-fabric-type-$type'),
            label: type,
            selected: _fabricType == type,
            onTap: () => setState(() => _fabricType = type),
          ),
      ],
    );
  }

  Widget _buildCustomDateRow() {
    String formatDate(DateTime? date) {
      if (date == null) return 'Select date';
      return '${date.month}/${date.day}/${date.year}';
    }

    return Row(
      children: [
        Expanded(
          child: _dateField(
            key: const ValueKey('filter-sheet-custom-start'),
            label: 'Start date',
            value: formatDate(_customStart),
            onTap: _pickCustomStart,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _dateField(
            key: const ValueKey('filter-sheet-custom-end'),
            label: 'End date',
            value: formatDate(_customEnd),
            onTap: _pickCustomEnd,
          ),
        ),
      ],
    );
  }

  Widget _dateField({
    required Key key,
    required String label,
    required String value,
    required VoidCallback onTap,
  }) {
    return InkWell(
      key: key,
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(fontSize: 11, color: AppColors.grayText),
            ),
            const SizedBox(height: 2),
            Row(
              children: [
                Expanded(
                  child: Text(
                    value,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textNavy,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const Icon(
                  Icons.calendar_today_rounded,
                  size: 14,
                  color: AppColors.grayText,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _choiceChip({
    required Key key,
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Material(
      key: key,
      color: selected ? AppColors.primaryNavy : Colors.white,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? AppColors.primaryNavy : AppColors.border,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: selected ? Colors.white : AppColors.textNavy,
            ),
          ),
        ),
      ),
    );
  }
}
