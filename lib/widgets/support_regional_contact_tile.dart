import 'package:flutter/material.dart';

import '../localization/translations.dart';
import '../models/support_region.dart';
import '../theme/app_colors.dart';

/// A single regional support representative row shown in the Contact Us
/// screen's "Regional Contacts" section (name, area, an optional tappable
/// phone number, and an optional availability window).
class SupportRegionalContactTile extends StatelessWidget {
  const SupportRegionalContactTile({
    super.key,
    required this.contact,
    required this.onCallTap,
  });

  final SupportRegionalContact contact;
  final ValueChanged<String> onCallTap;

  @override
  Widget build(BuildContext context) {
    final phone = contact.phone;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  contact.name,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textNavy,
                  ),
                ),
              ),
              if (phone != null)
                Semantics(
                  button: true,
                  label: context.t(
                    'contactUs.callNumber',
                    params: {'number': phone},
                  ),
                  child: InkWell(
                    key: ValueKey(
                      'regional-contact-call-'
                      '${contact.category.name}-${contact.name}-${contact.area}',
                    ),
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => onCallTap(phone),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 4,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.call_rounded,
                            size: 14,
                            color: AppColors.primaryNavy,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            phone,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppColors.primaryNavy,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            contact.area,
            style: const TextStyle(fontSize: 13, color: AppColors.grayText),
          ),
          if (contact.availability != null) ...[
            const SizedBox(height: 4),
            Text(
              contact.availability!,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.grayText,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
