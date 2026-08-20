import 'package:flutter/material.dart';

import '../localization/translations.dart';
import '../theme/app_colors.dart';

class _NavItemData {
  const _NavItemData(this.icon, this.labelKey);

  final IconData icon;
  final String labelKey;
}

class CustomBottomNav extends StatelessWidget {
  const CustomBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  final int currentIndex;
  final ValueChanged<int> onTap;

  static const List<_NavItemData> _items = [
    _NavItemData(Icons.home_rounded, 'nav.home'),
    _NavItemData(Icons.receipt_long_rounded, 'nav.orders'),
    _NavItemData(Icons.help_outline_rounded, 'nav.support'),
    _NavItemData(Icons.person_outline_rounded, 'nav.profile'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 64),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Image.asset(
              'assets/logo/ANC Logo.png',
              height: 20,
              fit: BoxFit.contain,
            ),
          ),
          ...List.generate(_items.length, (index) {
            final item = _items[index];
            return Expanded(
              child: CustomBottomNavItem(
                icon: item.icon,
                label: context.t(item.labelKey),
                selected: index == currentIndex,
                onTap: () => onTap(index),
              ),
            );
          }),
        ],
      ),
    );
  }
}

class CustomBottomNavItem extends StatelessWidget {
  const CustomBottomNavItem({
    super.key,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Container(
            constraints: const BoxConstraints(minWidth: 0),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: selected ? AppColors.primaryNavy : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 20,
                  color: selected
                      ? const Color(0xFFD8D6F5)
                      : AppColors.grayText,
                ),
                const SizedBox(height: 3),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    color: selected ? Colors.white : AppColors.grayText,
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
