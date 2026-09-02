import 'package:flutter/material.dart';

import '../localization/translations.dart';
import '../models/support_region.dart';
import '../theme/app_colors.dart';

/// A single verified office/location row, shown in the Contact Us screen's
/// "Locations" section (city, address, an optional business/location name,
/// and an optional tappable phone number) and, in [compact] form, in the
/// Support screen's "Corporate Office" card.
class SupportOfficeLocationTile extends StatelessWidget {
  const SupportOfficeLocationTile({
    super.key,
    required this.location,
    required this.onCallTap,
    this.compact = false,
    this.callNumberLabelKey = 'contactUs.callNumber',
  });

  final SupportOfficeLocation location;
  final ValueChanged<String> onCallTap;

  /// When true, renders just the city/name/address/phone content without
  /// the outer bordered card background — used on the Support screen,
  /// whose "Corporate Office" card already supplies its own bordered
  /// container via `SupportInfoCard`. Contact Us keeps the default (false)
  /// so its own "Locations" section, with one bordered tile per location,
  /// is unaffected.
  final bool compact;

  /// Translation key for the tappable phone number's semantics label.
  /// Screen-specific (rather than shared) because the Contact Us and
  /// Support copy for this label differs slightly per-locale.
  final String callNumberLabelKey;

  /// Localized city display text: the joined translation of every id in
  /// [SupportOfficeLocation.cityIds] (e.g. Oman's "Muscat / Seeb" from two
  /// ids), or the raw [SupportOfficeLocation.city] string when no city id
  /// has been added yet.
  String _cityText(BuildContext context) {
    final ids = location.cityIds;
    if (ids.isEmpty) return location.city;
    return ids.map((id) => context.t(id.translationKey)).join(' / ');
  }

  /// Localized address display text, or the raw
  /// [SupportOfficeLocation.address] string when this address's wording
  /// hasn't been confirmed for translation yet.
  String _addressText(BuildContext context) {
    final key = location.addressKey;
    return key == null ? location.address : context.t(key);
  }

  @override
  Widget build(BuildContext context) {
    final phone = location.phone;
    final name = location.name;
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          _cityText(context),
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: AppColors.textNavy,
          ),
        ),
        if (name != null) ...[
          const SizedBox(height: 2),
          Text(
            name,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.grayText,
            ),
          ),
        ],
        const SizedBox(height: 4),
        Text(
          _addressText(context),
          style: const TextStyle(fontSize: 13, color: AppColors.grayText),
        ),
        if (phone != null) ...[
          const SizedBox(height: 6),
          Semantics(
            button: true,
            label: context.t(callNumberLabelKey, params: {'number': phone}),
            child: InkWell(
              key: ValueKey('office-location-call-${location.city}'),
              borderRadius: BorderRadius.circular(8),
              onTap: () => onCallTap(phone),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.call_rounded,
                      size: 14,
                      color: AppColors.primaryNavy,
                    ),
                    const SizedBox(width: 4),
                    Directionality(
                      textDirection: TextDirection.ltr,
                      child: Text(
                        phone,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primaryNavy,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    );

    if (compact) return content;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: content,
    );
  }
}
