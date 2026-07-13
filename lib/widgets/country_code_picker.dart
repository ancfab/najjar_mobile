import 'package:flutter/material.dart';

import '../data/country_codes.dart';
import '../models/country_code.dart';
import '../theme/app_colors.dart';
import '../utils/responsive.dart';

/// Reusable, searchable country dial-code picker.
///
/// Displays the selected country's flag, dial code, and a dropdown arrow.
/// Tapping it opens a searchable bottom sheet (works well on both Android
/// and iOS) listing [kCountryCodes]; search matches country name, dial code,
/// or ISO code.
class CountryCodePicker extends StatelessWidget {
  const CountryCodePicker({
    super.key,
    required this.selectedCountry,
    required this.onChanged,
    this.enabled = true,
    this.errorText,
  });

  final CountryCode selectedCountry;
  final ValueChanged<CountryCode> onChanged;
  final bool enabled;
  final String? errorText;

  Future<void> _openPicker(BuildContext context) async {
    final picked = await showModalBottomSheet<CountryCode>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) => const _CountryCodeSearchSheet(),
    );

    if (picked != null) {
      onChanged(picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasError = errorText != null && errorText!.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Opacity(
          opacity: enabled ? 1 : 0.5,
          child: Material(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: enabled ? () => _openPicker(context) : null,
              child: Container(
                constraints: const BoxConstraints(minHeight: 52),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: hasError ? AppColors.dangerRed : AppColors.border,
                  ),
                ),
                child: Row(
                  children: [
                    Text(
                      selectedCountry.flag,
                      style: const TextStyle(fontSize: 20),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      selectedCountry.dialCode,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primaryNavy,
                      ),
                    ),
                    const Spacer(),
                    const Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: AppColors.textNavy,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (hasError) ...[
          const SizedBox(height: 6),
          Text(
            errorText!,
            style: const TextStyle(fontSize: 12, color: AppColors.dangerRed),
          ),
        ],
      ],
    );
  }
}

class _CountryCodeSearchSheet extends StatefulWidget {
  const _CountryCodeSearchSheet();

  @override
  State<_CountryCodeSearchSheet> createState() =>
      _CountryCodeSearchSheetState();
}

class _CountryCodeSearchSheetState extends State<_CountryCodeSearchSheet> {
  final _searchController = TextEditingController();
  List<CountryCode> _results = kCountryCodes;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    final normalized = query.trim().toLowerCase();
    setState(() {
      if (normalized.isEmpty) {
        _results = kCountryCodes;
        return;
      }
      final normalizedDial = normalized.replaceFirst('+', '');
      _results = kCountryCodes.where((country) {
        final nameMatch = country.name.toLowerCase().contains(normalized);
        final isoMatch = country.isoCode.toLowerCase().contains(normalized);
        final dialMatch = country.dialCode
            .replaceFirst('+', '')
            .contains(normalizedDial);
        return nameMatch || isoMatch || dialMatch;
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        child: ResponsiveMaxWidth(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: AppColors.border,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Text(
                  'Select country code',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textNavy,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _searchController,
                  autofocus: false,
                  textInputAction: TextInputAction.search,
                  onChanged: _onSearchChanged,
                  style: const TextStyle(
                    fontSize: 15,
                    color: AppColors.textNavy,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Search by country, code, or ISO',
                    hintStyle: const TextStyle(
                      color: AppColors.grayText,
                      fontSize: 14,
                    ),
                    prefixIcon: const Icon(
                      Icons.search_rounded,
                      color: AppColors.grayText,
                    ),
                    filled: true,
                    fillColor: AppColors.background,
                    contentPadding: const EdgeInsets.symmetric(vertical: 0),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: AppColors.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: AppColors.border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(
                        color: AppColors.primaryNavy,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Flexible(
                  child: _results.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.symmetric(vertical: 32),
                          child: Center(
                            child: Text(
                              'No countries found',
                              style: TextStyle(
                                color: AppColors.grayText,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        )
                      : ListView.separated(
                          shrinkWrap: true,
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          itemCount: _results.length,
                          separatorBuilder: (_, _) =>
                              const Divider(height: 1, color: AppColors.border),
                          itemBuilder: (context, index) {
                            final country = _results[index];
                            return ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: Text(
                                country.flag,
                                style: const TextStyle(fontSize: 22),
                              ),
                              title: Text(
                                country.name,
                                style: const TextStyle(
                                  fontSize: 15,
                                  color: AppColors.textNavy,
                                ),
                              ),
                              trailing: Text(
                                country.dialCode,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.primaryNavy,
                                ),
                              ),
                              onTap: () => Navigator.of(context).pop(country),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
