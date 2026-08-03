import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_radius.dart';
import '../theme/app_shadows.dart';

class AvailabilitySearchCard extends StatelessWidget {
  const AvailabilitySearchCard({
    super.key,
    required this.title,
    required this.hintText,
    required this.helperText,
    this.controller,
    this.onSearch,
    this.isLoading = false,
    this.errorText,
    this.resultText,
  });

  final String title;
  final String hintText;
  final String helperText;
  final TextEditingController? controller;
  final VoidCallback? onSearch;

  /// Shows a spinner in the search button and disables input while a
  /// lookup is in flight.
  final bool isLoading;

  /// Validation/error message shown below the helper text, if any.
  final String? errorText;

  /// Success/no-results message shown below the helper text, if any.
  final String? resultText;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.smallAll,
        border: Border.all(color: AppColors.border),
        boxShadow: AppShadows.standardCard,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // TODO: Swap for the exact archive icon asset from Figma if provided.
              const Icon(
                Icons.inventory_2_rounded,
                color: AppColors.primaryNavy,
                size: 20,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1A1A1A),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 44),
                  child: TextField(
                    controller: controller,
                    enabled: !isLoading,
                    style: const TextStyle(fontSize: 14),
                    onSubmitted: (_) => onSearch?.call(),
                    decoration: InputDecoration(
                      hintText: hintText,
                      hintStyle: const TextStyle(
                        color: AppColors.grayText,
                        fontSize: 14,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: AppRadius.smallAll,
                        borderSide: const BorderSide(color: AppColors.border),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: AppRadius.smallAll,
                        borderSide: const BorderSide(color: AppColors.border),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: AppRadius.smallAll,
                        borderSide: const BorderSide(
                          color: AppColors.primaryNavy,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Material(
                color: AppColors.primaryNavy,
                borderRadius: AppRadius.smallAll,
                child: InkWell(
                  borderRadius: AppRadius.smallAll,
                  onTap: isLoading ? null : onSearch,
                  child: SizedBox(
                    width: 44,
                    height: 44,
                    child: isLoading
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Icon(
                            Icons.search_rounded,
                            color: Colors.white,
                            size: 20,
                          ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            helperText,
            style: const TextStyle(fontSize: 12.5, color: AppColors.grayText),
          ),
          if (errorText != null) ...[
            const SizedBox(height: 8),
            Text(
              errorText!,
              style: const TextStyle(
                fontSize: 12.5,
                color: AppColors.dangerRed,
              ),
            ),
          ] else if (resultText != null) ...[
            const SizedBox(height: 8),
            Text(
              resultText!,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: AppColors.darkTeal,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
