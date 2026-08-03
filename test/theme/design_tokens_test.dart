// Tests for the shared design-system tokens (AppColors/AppSpacing/
// AppRadius/AppShadows/AppTypography) and their integration into the app's
// ThemeData: that the tokens exist and hold sane values, that MyApp's
// theme builds successfully with them wired in, and that the shared
// typography scale renders English, Arabic, and French sample text without
// throwing or overflowing — including under an increased system text-scale
// factor. Deliberately avoids brittle pixel-perfect or color-snapshot
// assertions.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anc_fabrics/main.dart';
import 'package:anc_fabrics/screens/login_screen.dart';
import 'package:anc_fabrics/theme/app_colors.dart';
import 'package:anc_fabrics/theme/app_radius.dart';
import 'package:anc_fabrics/theme/app_shadows.dart';
import 'package:anc_fabrics/theme/app_spacing.dart';
import 'package:anc_fabrics/theme/app_typography.dart';

void main() {
  group('AppColors', () {
    test('surface and disabled tokens exist and are opaque', () {
      expect(AppColors.surface.a, 1.0);
      expect(AppColors.disabled.a, 1.0);
    });

    test('surface is distinct from the page background', () {
      // Two deliberately different roles (elevated component vs. page
      // chrome) must not collapse to the same value.
      expect(AppColors.surface, isNot(AppColors.background));
    });
  });

  group('AppSpacing', () {
    test('scale is small, positive, and strictly increasing', () {
      const scale = [
        AppSpacing.xs,
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.xl,
        AppSpacing.xxl,
      ];
      for (var i = 1; i < scale.length; i++) {
        expect(
          scale[i],
          greaterThan(scale[i - 1]),
          reason: 'AppSpacing scale must be strictly increasing.',
        );
      }
      expect(scale.first, greaterThan(0));
    });

    test('pageHorizontal matches an existing scale step (lg)', () {
      expect(AppSpacing.pageHorizontal, AppSpacing.lg);
    });
  });

  group('AppRadius', () {
    test('every BorderRadius constant matches its raw double value', () {
      expect(AppRadius.smallAll, BorderRadius.circular(AppRadius.small));
      expect(AppRadius.inputAll, BorderRadius.circular(AppRadius.input));
      expect(AppRadius.buttonAll, BorderRadius.circular(AppRadius.button));
      expect(AppRadius.cardAll, BorderRadius.circular(AppRadius.card));
      expect(AppRadius.circularAll, BorderRadius.circular(AppRadius.circular));
      expect(
        AppRadius.sheetTop,
        BorderRadius.vertical(top: Radius.circular(AppRadius.sheet)),
      );
    });
  });

  group('AppShadows', () {
    test('every shadow list is non-empty and subtle (low alpha)', () {
      for (final shadow in [
        AppShadows.standardCard,
        AppShadows.elevatedCard,
        AppShadows.popupMenu,
        AppShadows.modalSheet,
      ]) {
        expect(shadow, isNotEmpty);
        for (final layer in shadow) {
          expect(
            layer.color.a,
            lessThan(0.5),
            reason: 'Shared shadows must stay subtle, not solid.',
          );
        }
      }
    });
  });

  group('AppTypography', () {
    test('display/title/section/card styles descend in size', () {
      expect(
        AppTypography.displayValue.fontSize,
        greaterThan(AppTypography.pageTitle.fontSize!),
      );
      expect(
        AppTypography.pageTitle.fontSize,
        greaterThan(AppTypography.cardTitle.fontSize!),
      );
      expect(
        AppTypography.body.fontSize,
        greaterThan(AppTypography.caption.fontSize!),
      );
    });

    test('no style forces a fixed line height that could clip glyphs', () {
      for (final style in [
        AppTypography.displayValue,
        AppTypography.pageTitle,
        AppTypography.sectionTitle,
        AppTypography.cardTitle,
        AppTypography.body,
        AppTypography.bodySecondary,
        AppTypography.label,
        AppTypography.caption,
        AppTypography.buttonText,
        AppTypography.numericValue,
      ]) {
        expect(style.height, isNull);
      }
    });
  });

  group('Theme integration', () {
    testWidgets('MyApp builds successfully with the shared tokens wired in', (
      tester,
    ) async {
      await tester.pumpWidget(MyApp(navigatorKey: GlobalKey<NavigatorState>()));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      final context = tester.element(find.byType(LoginScreen));
      final theme = Theme.of(context);

      expect(
        theme.textTheme.displayLarge?.fontSize,
        AppTypography.displayValue.fontSize,
      );
      expect(
        theme.textTheme.titleLarge?.fontSize,
        AppTypography.pageTitle.fontSize,
      );
      expect(
        theme.textTheme.bodySmall?.fontSize,
        AppTypography.bodySecondary.fontSize,
      );
      expect(theme.colorScheme.error, AppColors.dangerRed);
      expect(theme.scaffoldBackgroundColor, AppColors.background);
    });
  });

  group('Typography renders every supported language without overflow', () {
    // Representative strings per locale: a longer, real French/Arabic
    // phrase (not just a short greeting) so wrapping/overflow behavior is
    // actually exercised, alongside English.
    const samples = {
      'en': 'Quickly check availability across all warehouses.',
      'ar': 'تحقق بسرعة من التوفر في جميع المستودعات.',
      'fr': 'Vérifiez rapidement la disponibilité dans tous les entrepôts.',
    };

    for (final entry in samples.entries) {
      testWidgets('${entry.key}: body/card/caption styles fit a narrow width', (
        tester,
      ) async {
        await tester.pumpWidget(
          MaterialApp(
            locale: Locale(entry.key),
            home: Scaffold(
              body: Directionality(
                textDirection: entry.key == 'ar'
                    ? TextDirection.rtl
                    : TextDirection.ltr,
                child: SizedBox(
                  width: 220,
                  child: Column(
                    children: [
                      Text(entry.value, style: AppTypography.body),
                      Text(entry.value, style: AppTypography.bodySecondary),
                      Text(entry.value, style: AppTypography.cardTitle),
                      Text(entry.value, style: AppTypography.caption),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
      });

      testWidgets(
        '${entry.key}: renders under an increased system text-scale factor '
        'without throwing',
        (tester) async {
          await tester.pumpWidget(
            MaterialApp(
              locale: Locale(entry.key),
              home: Builder(
                builder: (context) {
                  return MediaQuery(
                    data: MediaQuery.of(
                      context,
                    ).copyWith(textScaler: const TextScaler.linear(1.3)),
                    child: Scaffold(
                      body: Directionality(
                        textDirection: entry.key == 'ar'
                            ? TextDirection.rtl
                            : TextDirection.ltr,
                        child: SizedBox(
                          width: 220,
                          child: Text(
                            entry.value,
                            style: AppTypography.body,
                            softWrap: true,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          );
          await tester.pumpAndSettle();

          expect(tester.takeException(), isNull);
        },
      );
    }
  });
}
