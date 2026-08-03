import 'package:flutter/material.dart';

import '../localization/app_locale.dart';
import '../localization/translations.dart';
import '../services/locale_controller.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';

/// Globe-icon trigger that opens the language switcher as a compact popup
/// menu anchored to itself (via [PopupMenuButton]), instead of a bottom
/// sheet or a dedicated screen. [LocaleController] stays the single source
/// of truth for the active locale and its persistence — this widget only
/// renders the trigger + menu and calls [LocaleController.setLocale].
class LanguagePopupMenuButton extends StatelessWidget {
  LanguagePopupMenuButton({super.key, LocaleController? controller})
    : controller = controller ?? localeController;

  final LocaleController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        return PopupMenuButton<AppLocale>(
          tooltip: context.t('language.iconTooltip'),
          color: AppColors.surface,
          elevation: 6,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          constraints: const BoxConstraints(minWidth: 220, maxWidth: 260),
          onSelected: (appLocale) => controller.setLocale(appLocale),
          itemBuilder: (context) => _buildMenuItems(context),
          child: const Padding(
            padding: EdgeInsets.all(4),
            child: Icon(Icons.language, color: AppColors.textNavy, size: 26),
          ),
        );
      },
    );
  }

  List<PopupMenuEntry<AppLocale>> _buildMenuItems(BuildContext context) {
    return [
      PopupMenuItem<AppLocale>(
        enabled: false,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Text(
          context.t('language.selectorTitle'),
          style: AppTypography.cardTitle.copyWith(color: AppColors.primaryNavy),
        ),
      ),
      const PopupMenuDivider(height: 1),
      for (var i = 0; i < AppLocale.values.length; i++) ...[
        PopupMenuItem<AppLocale>(
          key: ValueKey(
            'language-option-${AppLocale.values[i].locale.languageCode}',
          ),
          value: AppLocale.values[i],
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: _LanguageOptionRow(
            appLocale: AppLocale.values[i],
            selected: controller.appLocale == AppLocale.values[i],
          ),
        ),
        if (i != AppLocale.values.length - 1) const PopupMenuDivider(height: 1),
      ],
    ];
  }
}

class _LanguageOptionRow extends StatelessWidget {
  const _LanguageOptionRow({required this.appLocale, required this.selected});

  final AppLocale appLocale;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 28,
          child: Text(
            appLocale.locale.languageCode.toUpperCase(),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: selected ? AppColors.primaryNavy : AppColors.grayText,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            appLocale.nativeName,
            style: TextStyle(
              fontSize: 15,
              fontWeight: selected ? FontWeight.bold : FontWeight.normal,
              color: selected ? AppColors.primaryNavy : AppColors.textNavy,
            ),
          ),
        ),
        if (selected)
          const Padding(
            padding: EdgeInsetsDirectional.only(start: 8),
            child: Icon(
              Icons.check_rounded,
              color: AppColors.primaryNavy,
              size: 18,
            ),
          ),
      ],
    );
  }
}
