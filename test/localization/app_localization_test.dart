// End-to-end localization tests driven through the real app root (MyApp):
// language rendering/direction per locale, the language selector's open/
// select flow, immediate UI updates on language change, and overflow safety
// of the Home header and bottom navigation under Arabic RTL.

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anc_fabrics/localization/app_locale.dart';
import 'package:anc_fabrics/localization/app_translations_delegate.dart';
import 'package:anc_fabrics/main.dart';
import 'package:anc_fabrics/models/home_dashboard_data.dart';
import 'package:anc_fabrics/services/current_balance_service.dart';
import 'package:anc_fabrics/services/locale_controller.dart';
import 'package:anc_fabrics/services/session_storage_keys.dart';
import 'package:anc_fabrics/widgets/custom_bottom_nav.dart';

import '../helpers/fake_current_balance_data_source.dart';
import '../helpers/fake_home_dashboard_service.dart';
import '../helpers/fake_last_payment_data_source.dart';

Future<void> _pumpApp(WidgetTester tester, {double width = 390}) async {
  tester.view.physicalSize = Size(width, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  // Last Payment, Current Balance, and the dashboard metrics all default to
  // live Business Central endpoints (real HTTP/secure storage), which never
  // resolve in this widget-test sandbox — inject fakes so pumpAndSettle
  // below doesn't wait forever on their loading spinners (these tests don't
  // exercise any of them specifically).
  await tester.pumpWidget(
    MyApp(
      isLoggedIn: true,
      lastPaymentSource: FakeLastPaymentDataSource(entry: null),
      currentBalanceSource: FakeCurrentBalanceDataSource(
        amount: const CurrentBalanceAmount(
          amount: 15320.75,
          currencyCode: 'AED',
        ),
      ),
      dashboardService: FakeHomeDashboardService(
        data: const HomeDashboardData(
          activeOrdersCount: '3',
          overdueInvoicesAmount: '1,250.00',
        ),
      ),
    ),
  );
  await tester.pump();
  // Home screen loads dashboard data on initState; advance past the fake's
  // async resolution explicitly (matching home_screen_test.dart's
  // convention) so the "Active Orders" metric card — not just its loading
  // skeleton — is on screen before assertions run.
  await tester.pump(const Duration(milliseconds: 700));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() async {
    // MyApp is driven by this app-wide singleton — reset it so a language
    // choice made in one test never leaks into the next.
    await localeController.setLocale(AppLocale.english);
  });

  group('Locale rendering', () {
    testWidgets('English is available and renders LTR', (tester) async {
      await _pumpApp(tester);

      expect(find.text('Active Orders'), findsOneWidget);
      final context = tester.element(find.text('Active Orders'));
      expect(Directionality.of(context), TextDirection.ltr);
    });

    testWidgets('French is available and renders LTR', (tester) async {
      await localeController.setLocale(AppLocale.french);
      await _pumpApp(tester);

      expect(find.text('Commandes actives'), findsOneWidget);
      final context = tester.element(find.text('Commandes actives'));
      expect(Directionality.of(context), TextDirection.ltr);
    });

    testWidgets('Arabic is available and renders RTL', (tester) async {
      await localeController.setLocale(AppLocale.arabic);
      await _pumpApp(tester);

      expect(find.text('الطلبات النشطة'), findsOneWidget);
      final context = tester.element(find.text('الطلبات النشطة'));
      expect(Directionality.of(context), TextDirection.rtl);
    });
  });

  group('Language selector', () {
    testWidgets(
      'pressing the globe icon opens an anchored popup, not a page or a '
      'bottom sheet, and Home stays visible behind it',
      (tester) async {
        await _pumpApp(tester);

        await tester.tap(
          find.byKey(const ValueKey('home-header-language-button')),
        );
        await tester.pumpAndSettle();

        // Home's own content is still onstage underneath the popup — unlike
        // a page push (which would offstage it) or a full-screen sheet.
        expect(find.text('Active Orders'), findsOneWidget);
        expect(find.byType(BottomSheet), findsNothing);

        expect(find.text('Select Language'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('language-option-en')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('language-option-ar')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('language-option-fr')),
          findsOneWidget,
        );
      },
    );

    testWidgets('tapping outside the popup closes it', (tester) async {
      await _pumpApp(tester);

      await tester.tap(
        find.byKey(const ValueKey('home-header-language-button')),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('language-option-en')), findsOneWidget);

      // The popup anchors near the top-right globe icon; tapping the
      // opposite corner hits the barrier, not the menu.
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('language-option-en')), findsNothing);
      expect(find.text('Select Language'), findsNothing);
      expect(find.text('Active Orders'), findsOneWidget);
    });

    testWidgets(
      'selecting Arabic immediately updates visible text and direction, '
      'closes the popup, and stays on Home',
      (tester) async {
        await _pumpApp(tester);
        expect(find.text('Active Orders'), findsOneWidget);

        await tester.tap(
          find.byKey(const ValueKey('home-header-language-button')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('language-option-ar')));
        await tester.pumpAndSettle();

        // Applied immediately, popup closed, still on Home.
        expect(find.byKey(const ValueKey('language-option-ar')), findsNothing);
        expect(find.text('الطلبات النشطة'), findsOneWidget);
        expect(find.text('Active Orders'), findsNothing);
        final context = tester.element(find.text('الطلبات النشطة'));
        expect(Directionality.of(context), TextDirection.rtl);
      },
    );

    testWidgets('selecting French immediately updates visible text, stays LTR, '
        'closes the popup, and stays on Home', (tester) async {
      await _pumpApp(tester);
      expect(find.text('Active Orders'), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey('home-header-language-button')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('language-option-fr')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('language-option-fr')), findsNothing);
      expect(find.text('Commandes actives'), findsOneWidget);
      expect(find.text('Active Orders'), findsNothing);
      final context = tester.element(find.text('Commandes actives'));
      expect(Directionality.of(context), TextDirection.ltr);
    });

    testWidgets('selecting English from Arabic switches back to LTR', (
      tester,
    ) async {
      await localeController.setLocale(AppLocale.arabic);
      await _pumpApp(tester);
      expect(find.text('الطلبات النشطة'), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey('home-header-language-button')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('language-option-en')));
      await tester.pumpAndSettle();

      expect(find.text('Active Orders'), findsOneWidget);
      final context = tester.element(find.text('Active Orders'));
      expect(Directionality.of(context), TextDirection.ltr);
    });

    testWidgets('shows a clear selected state for the current language', (
      tester,
    ) async {
      await localeController.setLocale(AppLocale.french);
      await _pumpApp(tester);

      await tester.tap(
        find.byKey(const ValueKey('home-header-language-button')),
      );
      await tester.pumpAndSettle();

      final frenchOption = find.byKey(const ValueKey('language-option-fr'));
      expect(
        find.descendant(
          of: frenchOption,
          matching: find.byIcon(Icons.check_rounded),
        ),
        findsOneWidget,
        reason: 'the active language should show a selected checkmark',
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('language-option-en')),
          matching: find.byIcon(Icons.check_rounded),
        ),
        findsNothing,
      );
    });

    testWidgets(
      'persists the selected locale via SharedPreferences so it survives '
      'restart',
      (tester) async {
        await _pumpApp(tester);

        await tester.tap(
          find.byKey(const ValueKey('home-header-language-button')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('language-option-ar')));
        await tester.pumpAndSettle();

        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString(SessionStorageKeys.localeCode), 'ar');
      },
    );
  });

  group('Overflow safety', () {
    for (final width in [320.0, 360.0, 390.0, 430.0]) {
      testWidgets('Home header does not overflow in Arabic at width $width', (
        tester,
      ) async {
        await localeController.setLocale(AppLocale.arabic);
        await _pumpApp(tester, width: width);

        expect(tester.takeException(), isNull);
      });

      testWidgets('Home header does not overflow in French at width $width', (
        tester,
      ) async {
        await localeController.setLocale(AppLocale.french);
        await _pumpApp(tester, width: width);

        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('Bottom navigation does not overflow in Arabic', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('ar'),
          supportedLocales: AppLocale.supportedLocales,
          localizationsDelegates: const [
            AppTranslationsDelegate(),
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: Scaffold(body: CustomBottomNav(currentIndex: 0, onTap: (_) {})),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('الرئيسية'), findsOneWidget);
      expect(find.text('الطلبات'), findsOneWidget);
      expect(find.text('الدعم'), findsOneWidget);
      expect(find.text('الملف الشخصي'), findsOneWidget);
    });

    testWidgets(
      'Bottom navigation does not overflow in Arabic on a tablet width',
      (tester) async {
        tester.view.physicalSize = const Size(768, 1024);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('ar'),
            supportedLocales: AppLocale.supportedLocales,
            localizationsDelegates: const [
              AppTranslationsDelegate(),
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: Scaffold(
              body: CustomBottomNav(currentIndex: 0, onTap: (_) {}),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
      },
    );
  });
}
