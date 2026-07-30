import 'package:flutter/material.dart';

import '../localization/translations.dart';
import '../models/fabric_specs.dart';
import '../theme/app_colors.dart';
import '../utils/responsive.dart';

/// Mobile-friendly bottom sheet showing mock [FabricSpecs] fields for an
/// order item.
///
/// TODO: Confirm final Fabric Specs behavior with product/backend team: PDF
/// download, modal, or separate screen. This bottom sheet is a temporary
/// frontend-only stand-in until that's decided.
class FabricSpecsSheet extends StatelessWidget {
  const FabricSpecsSheet({super.key, required this.specs});

  final FabricSpecs specs;

  @override
  Widget build(BuildContext context) {
    final maxSheetHeight = MediaQuery.of(context).size.height * 0.85;
    return SafeArea(
      top: false,
      child: ResponsiveMaxWidth(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxSheetHeight),
          child: SingleChildScrollView(
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
                Text(
                  context.t('fabricSpecs.title'),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textNavy,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  specs.fabricName,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.grayText,
                  ),
                ),
                const SizedBox(height: 16),
                _buildSpecRow(context.t('fabricSpecs.sku'), specs.sku),
                _buildSpecRow(context.t('fabricSpecs.color'), specs.color),
                _buildSpecRow(context.t('fabricSpecs.weight'), specs.weight),
                _buildSpecRow(
                  context.t('fabricSpecs.quantity'),
                  specs.quantity,
                ),
                if (specs.composition != null)
                  _buildSpecRow(
                    context.t('fabricSpecs.composition'),
                    specs.composition!,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSpecRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.grayText,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: AppColors.textNavy,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Opens the Fabric Specs bottom sheet for [specs].
///
/// Frontend-only and temporary: shows mock fabric spec fields in a modal
/// bottom sheet.
///
/// TODO: Confirm final Fabric Specs behavior with product/backend team: PDF
/// download, modal, or separate screen.
Future<void> showFabricSpecsSheet(BuildContext context, FabricSpecs specs) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (context) => FabricSpecsSheet(specs: specs),
  );
}
