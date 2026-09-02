// Widget checks for the Support screen: intro content, the region
// selector's initial/selected state, and that the WhatsApp/Email/Hotline
// actions respond safely without throwing.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anc_fabrics/data/support_regions_data.dart';
import 'package:anc_fabrics/models/auth/auth_session.dart';
import 'package:anc_fabrics/models/support_region.dart';
import 'package:anc_fabrics/screens/contact_us_screen.dart';
import 'package:anc_fabrics/screens/edit_profile_screen.dart';
import 'package:anc_fabrics/screens/orders_screen.dart';
import 'package:anc_fabrics/screens/support_screen.dart';
import 'package:anc_fabrics/services/auth_service.dart';
import 'package:anc_fabrics/services/phone_launcher.dart';
import 'package:anc_fabrics/services/support_region_service.dart';
import 'package:anc_fabrics/services/url_launcher_client.dart';
import 'package:anc_fabrics/services/whatsapp_launcher.dart';
import 'package:anc_fabrics/utils/phone_number.dart';
import 'package:anc_fabrics/widgets/custom_bottom_nav.dart';
import 'package:anc_fabrics/widgets/support_action_card.dart';
import 'package:anc_fabrics/widgets/support_hours_card.dart';
import 'package:anc_fabrics/widgets/support_info_card.dart';
import 'package:anc_fabrics/widgets/support_region_selector.dart';

import 'helpers/fake_auth_session_store.dart';
import 'helpers/fake_url_launcher_client.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:anc_fabrics/localization/app_translations_delegate.dart';

const _syntheticToken = 'synthetic-id|synthetic-secret';

// English translations for the addresses that now have confirmed
// translation keys (see assets/translation/english.json under
// supportAddress) — Support renders these instead of the raw stored
// literal once a key is set. Addresses left unconfirmed (Aleppo, Erbil,
// Sulaymaniyah, Oman) keep rendering their raw stored literal untouched.
const _uaeSharjahAddressEn = 'Industrial City, Zone 18';
const _syriaDamascusAddressEn =
    'Damascus International Airport Road, ANC Najjar Fabric';
const _lebanonBeirutAddressEn = 'Next to the Kuwaiti Embassy';

/// The confirmed English address translation for a region's office
/// location, or its raw stored [SupportOfficeLocation.address] when that
/// location's wording is still unconfirmed.
String _expectedAddressEn(SupportOfficeLocation location) {
  switch (location.city) {
    case 'Sharjah':
      return _uaeSharjahAddressEn;
    case 'Damascus':
      return _syriaDamascusAddressEn;
    case 'Beirut':
      return _lebanonBeirutAddressEn;
    default:
      return location.address;
  }
}

/// An authenticated session with [country] as its login country, otherwise
/// filled with unremarkable sample identity data — mirrors the shape
/// `AuthSession.fromLoginResponse` would produce after a real login.
AuthSession _sessionWithCountry(String country) => AuthSession(
  token: _syntheticToken,
  userId: 7,
  username: 'sample.user',
  phone: '+9715xxxxxxxx',
  country: country,
  clientId: 'ANCNAJJAR',
  mustChangePassword: false,
);

/// Builds a real [AuthService] over a [FakeAuthSessionStore] seeded with
/// [session] (or left empty when null, simulating no persisted session) —
/// the same real-service-over-fake-store pattern used in
/// edit_profile_screen_test.dart, so SupportScreen's real
/// [AuthService.currentSession] call is exercised for real. The network
/// [AncApiClient] this leaves at its real default is never touched, since
/// [AuthService.currentSession] only reads local session storage.
AuthService _authServiceFor(AuthSession? session) {
  final store = FakeAuthSessionStore();
  if (session != null) store.seed(session);
  return AuthService.production(sessionStore: store);
}

void main() {
  Future<void> pumpSupport(WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        supportedLocales: [Locale('en'), Locale('ar'), Locale('fr')],
        localizationsDelegates: [
          AppTranslationsDelegate(),
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: SupportScreen(),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> pumpSupportLocale(WidgetTester tester, Locale locale) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: locale,
        supportedLocales: const [Locale('en'), Locale('ar'), Locale('fr')],
        localizationsDelegates: const [
          AppTranslationsDelegate(),
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: const SupportScreen(),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('Displays the intro section, region pills, and all cards', (
    tester,
  ) async {
    await pumpSupport(tester);

    expect(find.text('SUPPORT CENTER'), findsOneWidget);
    expect(find.text('How can we help your business thrive?'), findsOneWidget);

    for (final region in ['UAE', 'Syria', 'Iraq', 'Oman', 'Lebanon']) {
      expect(find.text(region), findsOneWidget);
    }

    expect(find.byType(SupportActionCard), findsOneWidget);
    expect(find.text('Live Specialist Support'), findsOneWidget);
    expect(find.text('CHAT ON WHATSAPP'), findsOneWidget);
    expect(find.text('EMAIL SUPPORT'), findsOneWidget);

    expect(find.byType(SupportInfoCard), findsNWidgets(2));
    expect(find.text('CORPORATE OFFICE'), findsOneWidget);
    expect(find.text('DIRECT HOTLINE'), findsOneWidget);
    expect(find.byType(SupportHoursCard), findsOneWidget);
    expect(find.text('SUPPORT HOURS'), findsOneWidget);
  });

  testWidgets(
    'Does not render the removed "24/7 Precision" textile visual section',
    (tester) async {
      await pumpSupport(tester);

      expect(find.text('24/7 Precision'), findsNothing);

      // Other Support content stays intact.
      expect(find.text('SUPPORT CENTER'), findsOneWidget);
      expect(find.byType(SupportActionCard), findsOneWidget);
      expect(find.byType(SupportInfoCard), findsNWidgets(2));
      expect(find.byType(SupportHoursCard), findsOneWidget);
    },
  );

  testWidgets('UAE region pill is selected initially', (tester) async {
    await pumpSupport(tester);

    final selector = tester.widget<SupportRegionSelector>(
      find.byType(SupportRegionSelector),
    );
    expect(selector.selectedRegionId, kSupportRegions.first.id);
  });

  testWidgets('Selecting another region updates the selected state', (
    tester,
  ) async {
    await pumpSupport(tester);

    final lebanon = kSupportRegions.firstWhere(
      (region) => region.id == SupportRegionId.lebanon,
    );

    await tester.tap(find.text(lebanon.displayName));
    await tester.pumpAndSettle();

    final selector = tester.widget<SupportRegionSelector>(
      find.byType(SupportRegionSelector),
    );
    expect(selector.selectedRegionId, lebanon.id);
    // Lebanon now has verified office locations, so the office fallback no
    // longer applies to it — only support hours (still unverified for every
    // region) falls back.
    for (final location in lebanon.officeLocations) {
      expect(find.text(location.city), findsOneWidget);
      expect(find.text(_expectedAddressEn(location)), findsOneWidget);
    }
    expect(
      find.text(
        'Support hours for ${lebanon.displayName} will be confirmed soon.',
      ),
      findsOneWidget,
    );
  });

  testWidgets(
    'Selecting multiple regions sequentially leaves no stale information '
    'from the previous region',
    (tester) async {
      await pumpSupport(tester);

      for (final region in kSupportRegions) {
        await tester.tap(find.text(region.displayName));
        await tester.pumpAndSettle();

        final selector = tester.widget<SupportRegionSelector>(
          find.byType(SupportRegionSelector),
        );
        expect(selector.selectedRegionId, region.id);
        // Every current region has at least one verified office location,
        // so the "will be added soon" fallback never applies to any of
        // them today.
        if (region.officeLocations.isEmpty) {
          expect(
            find.text(
              'Office details for ${region.displayName} will be added soon.',
            ),
            findsOneWidget,
          );
        } else {
          for (final location in region.officeLocations) {
            expect(find.text(location.city), findsOneWidget);
            expect(find.text(_expectedAddressEn(location)), findsOneWidget);
          }
        }
        expect(
          find.text(
            'Support hours for ${region.displayName} will be confirmed '
            'soon.',
          ),
          findsOneWidget,
        );

        for (final other in kSupportRegions) {
          if (other.id == region.id) continue;
          for (final location in other.officeLocations) {
            // Skip cities that also belong to the selected region (e.g.
            // none currently overlap, but this keeps the check honest if
            // that ever changes) to avoid a false negative.
            final sharedCity = region.officeLocations.any(
              (l) => l.city == location.city,
            );
            if (sharedCity) continue;
            expect(find.text(location.city), findsNothing);
          }
        }
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets('Screen remains stable after repeated region changes', (
    tester,
  ) async {
    await pumpSupport(tester);

    for (var i = 0; i < 3; i++) {
      for (final region in kSupportRegions) {
        await tester.tap(find.text(region.displayName));
        await tester.pumpAndSettle();
      }
    }

    expect(find.byType(SupportScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('WhatsApp button reflects the currently selected region', (
    tester,
  ) async {
    await pumpSupport(tester);

    final uae = kSupportRegions.first;
    await tester.tap(find.byKey(const ValueKey('support-whatsapp-button')));
    await tester.pump();
    expect(
      find.text(
        'WhatsApp support is not available for ${uae.displayName} '
        'yet.',
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);

    final lebanon = kSupportRegions.firstWhere(
      (region) => region.id == SupportRegionId.lebanon,
    );
    await tester.tap(find.text(lebanon.displayName));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('support-whatsapp-button')));
    // The previous SnackBar's hide animation (triggered by
    // hideCurrentSnackBar in _onChatOnWhatsApp) needs a moment to finish
    // before the new one is shown, well short of its own auto-dismiss
    // duration.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      find.text(
        'WhatsApp support is not available for '
        '${lebanon.displayName} yet.',
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        'WhatsApp support is not available for ${uae.displayName} '
        'yet.',
      ),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  group('WhatsApp launch flow', () {
    final testRegion = SupportRegionData(
      id: SupportRegionId.uae,
      displayName: 'Testland',
      whatsappNumber: '+971 50 123 4567',
    );

    Future<void> pumpSupportWithRegion(
      WidgetTester tester,
      SupportRegionData region,
      WhatsAppLauncher launcher,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          supportedLocales: const [Locale('en'), Locale('ar'), Locale('fr')],
          localizationsDelegates: const [
            AppTranslationsDelegate(),
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: SupportScreen(regions: [region], whatsAppLauncher: launcher),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets(
      'Native launch success does not attempt the web fallback and shows '
      'no error',
      (tester) async {
        final client = FakeUrlLauncherClient(nativeResult: true);
        await pumpSupportWithRegion(
          tester,
          testRegion,
          WhatsAppLauncher(client: client),
        );

        await tester.tap(find.byKey(const ValueKey('support-whatsapp-button')));
        await tester.pumpAndSettle();

        final expectedNumber = normalizeWhatsAppNumber(
          testRegion.whatsappNumber,
        );
        expect(client.attemptedUris, hasLength(1));
        expect(
          client.attemptedUris.single.toString(),
          'whatsapp://send?phone=$expectedNumber',
        );
        expect(find.textContaining("Couldn't open WhatsApp"), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'Native launch returning false attempts the web fallback and shows '
      'no error when it succeeds',
      (tester) async {
        final client = FakeUrlLauncherClient(
          nativeResult: false,
          webResult: true,
        );
        await pumpSupportWithRegion(
          tester,
          testRegion,
          WhatsAppLauncher(client: client),
        );

        await tester.tap(find.byKey(const ValueKey('support-whatsapp-button')));
        await tester.pumpAndSettle();

        final expectedNumber = normalizeWhatsAppNumber(
          testRegion.whatsappNumber,
        );
        expect(client.attemptedUris, hasLength(2));
        expect(
          client.attemptedUris[0].toString(),
          'whatsapp://send?phone=$expectedNumber',
        );
        expect(
          client.attemptedUris[1].toString(),
          'https://wa.me/$expectedNumber',
        );
        expect(find.textContaining("Couldn't open WhatsApp"), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('Native launch throwing attempts the web fallback', (
      tester,
    ) async {
      final client = FakeUrlLauncherClient(
        nativeResult: Exception('native failed'),
        webResult: true,
      );
      await pumpSupportWithRegion(
        tester,
        testRegion,
        WhatsAppLauncher(client: client),
      );

      await tester.tap(find.byKey(const ValueKey('support-whatsapp-button')));
      await tester.pumpAndSettle();

      expect(client.attemptedUris, hasLength(2));
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'Both native and web launches failing shows a user-friendly error',
      (tester) async {
        final client = FakeUrlLauncherClient(
          nativeResult: false,
          webResult: false,
        );
        await pumpSupportWithRegion(
          tester,
          testRegion,
          WhatsAppLauncher(client: client),
        );

        await tester.tap(find.byKey(const ValueKey('support-whatsapp-button')));
        await tester.pumpAndSettle();

        // The message interpolates the localized country name for
        // testRegion.id (UAE), not its custom test-only displayName.
        expect(
          find.text("Couldn't open WhatsApp for UAE. Please try again later."),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'A region with no whatsappNumber never calls the launcher and shows '
      'the unavailable message',
      (tester) async {
        final client = FakeUrlLauncherClient();
        const unavailableRegion = SupportRegionData(
          id: SupportRegionId.syria,
          displayName: 'NoNumberLand',
        );
        await pumpSupportWithRegion(
          tester,
          unavailableRegion,
          WhatsAppLauncher(client: client),
        );

        await tester.tap(find.byKey(const ValueKey('support-whatsapp-button')));
        await tester.pump();

        expect(client.attemptedUris, isEmpty);
        // The message interpolates the localized country name for
        // unavailableRegion.id (Syria), not its custom test-only
        // displayName.
        expect(
          find.text('WhatsApp support is not available for Syria yet.'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'Selecting another region before tapping uses the new region\'s '
      'number, not the previous region\'s',
      (tester) async {
        final client = FakeUrlLauncherClient(nativeResult: true);
        final regionA = SupportRegionData(
          id: SupportRegionId.uae,
          displayName: 'RegionA',
          whatsappNumber: '+971 50 123 4567',
        );
        final regionB = SupportRegionData(
          id: SupportRegionId.lebanon,
          displayName: 'RegionB',
          whatsappNumber: '+961 3 123 456',
        );
        await tester.pumpWidget(
          MaterialApp(
            supportedLocales: const [Locale('en'), Locale('ar'), Locale('fr')],
            localizationsDelegates: const [
              AppTranslationsDelegate(),
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: SupportScreen(
              regions: [regionA, regionB],
              whatsAppLauncher: WhatsAppLauncher(client: client),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // The pill renders the localized country name for regionB.id
        // (Lebanon), not its custom test-only displayName.
        await tester.tap(find.text('Lebanon'));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const ValueKey('support-whatsapp-button')));
        await tester.pumpAndSettle();

        expect(client.attemptedUris, hasLength(1));
        expect(
          client.attemptedUris.single.toString(),
          'whatsapp://send?phone='
          '${normalizeWhatsAppNumber(regionB.whatsappNumber)}',
        );
      },
    );

    testWidgets('Rapid repeated taps only trigger a single launch attempt', (
      tester,
    ) async {
      // A launch that resolves purely through microtasks (as the other
      // fakes in this suite do) would finish draining before a second
      // `tester.tap()` even returns, making the guard untestable. Holding
      // the native launch open on a Completer keeps it "in flight" so the
      // guard can be observed blocking the repeated taps.
      final inFlight = Completer<bool>();
      final client = _ControlledUrlLauncherClient(inFlight.future);
      await pumpSupportWithRegion(
        tester,
        testRegion,
        WhatsAppLauncher(client: client),
      );

      final button = find.byKey(const ValueKey('support-whatsapp-button'));
      await tester.tap(button);
      await tester.tap(button);
      await tester.tap(button);

      expect(client.attemptedUris, hasLength(1));

      inFlight.complete(true);
      await tester.pumpAndSettle();

      expect(client.attemptedUris, hasLength(1));
      expect(tester.takeException(), isNull);
    });
  });

  group('Corporate Office locations', () {
    testWidgets('UAE shows Sharjah', (tester) async {
      await pumpSupport(tester);

      expect(find.text('Sharjah'), findsOneWidget);
    });

    testWidgets('Syria shows Damascus and Aleppo', (tester) async {
      await pumpSupport(tester);

      await tester.tap(find.text('Syria'));
      await tester.pumpAndSettle();

      expect(find.text('Damascus'), findsOneWidget);
      expect(find.text('Aleppo'), findsOneWidget);
    });

    testWidgets('Lebanon shows Beirut', (tester) async {
      await pumpSupport(tester);

      await tester.tap(find.text('Lebanon'));
      await tester.pumpAndSettle();

      expect(find.text('Beirut'), findsOneWidget);
    });

    testWidgets('Oman shows Muscat / Seeb', (tester) async {
      await pumpSupport(tester);

      await tester.tap(find.text('Oman'));
      await tester.pumpAndSettle();

      expect(find.text('Muscat / Seeb'), findsOneWidget);
    });

    testWidgets('Iraq shows Erbil and Sulaymaniyah', (tester) async {
      await pumpSupport(tester);

      await tester.tap(find.text('Iraq'));
      await tester.pumpAndSettle();

      expect(find.text('Erbil'), findsOneWidget);
      expect(find.text('Sulaymaniyah'), findsOneWidget);
    });

    testWidgets(
      'Changing the Support region updates Corporate Office locations',
      (tester) async {
        await pumpSupport(tester);

        expect(find.text('Sharjah'), findsOneWidget);

        await tester.tap(find.text('Syria'));
        await tester.pumpAndSettle();

        expect(find.text('Sharjah'), findsNothing);
        expect(find.text('Damascus'), findsOneWidget);
        expect(find.text('Aleppo'), findsOneWidget);
      },
    );

    testWidgets(
      'A region with multiple offices renders every location, each with '
      'its own city/address/phone',
      (tester) async {
        await pumpSupport(tester);

        await tester.tap(find.text('Iraq'));
        await tester.pumpAndSettle();

        final iraq = kSupportRegions.firstWhere(
          (region) => region.id == SupportRegionId.iraq,
        );
        expect(iraq.officeLocations, hasLength(2));
        for (final location in iraq.officeLocations) {
          expect(find.text(location.city), findsOneWidget);
          expect(find.text(location.address), findsOneWidget);
          if (location.phone != null) {
            expect(find.text(location.phone!), findsOneWidget);
          }
        }
      },
    );

    testWidgets(
      'A region with a single office renders it with no placeholder for '
      'missing optional fields',
      (tester) async {
        await pumpSupport(tester);

        final uae = kSupportRegions.firstWhere(
          (region) => region.id == SupportRegionId.uae,
        );
        final sharjah = uae.officeLocations.single;
        expect(sharjah.phone, isNull);

        expect(find.text(sharjah.city), findsOneWidget);
        expect(find.text(_uaeSharjahAddressEn), findsOneWidget);
        // No verified phone for Sharjah, so no tappable call row is
        // rendered for that office location (the Direct Hotline card
        // below still has its own unrelated call icon).
        expect(
          find.byKey(const ValueKey('office-location-call-Sharjah')),
          findsNothing,
        );
      },
    );

    testWidgets(
      'Missing optional name/phone values never show placeholder text',
      (tester) async {
        await pumpSupport(tester);

        await tester.tap(find.text('Syria'));
        await tester.pumpAndSettle();

        // Damascus and Aleppo have no verified business name or phone.
        expect(
          find.byKey(const ValueKey('office-location-call-Damascus')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('office-location-call-Aleppo')),
          findsNothing,
        );
        expect(find.textContaining('null'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'Iraq office location phone actions generate the correct tel: URIs '
      'from Support',
      (tester) async {
        final client = FakeUrlLauncherClient(telResult: true);
        await tester.pumpWidget(
          MaterialApp(
            supportedLocales: const [Locale('en'), Locale('ar'), Locale('fr')],
            localizationsDelegates: const [
              AppTranslationsDelegate(),
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: SupportScreen(phoneLauncher: PhoneLauncher(client: client)),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Iraq'));
        await tester.pumpAndSettle();

        final erbilCall = find.byKey(
          const ValueKey('office-location-call-Erbil'),
        );
        await tester.ensureVisible(erbilCall);
        await tester.pumpAndSettle();
        await tester.tap(erbilCall);
        await tester.pumpAndSettle();

        expect(client.attemptedUris, hasLength(1));
        expect(client.attemptedUris.single.toString(), 'tel:+9647514018777');

        final sulaymaniyahCall = find.byKey(
          const ValueKey('office-location-call-Sulaymaniyah'),
        );
        await tester.ensureVisible(sulaymaniyahCall);
        await tester.pumpAndSettle();
        await tester.tap(sulaymaniyahCall);
        await tester.pumpAndSettle();

        expect(client.attemptedUris, hasLength(2));
        expect(client.attemptedUris.last.toString(), 'tel:+9647501661000');
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('No old officeAddress value is rendered after migration', (
      tester,
    ) async {
      await pumpSupport(tester);

      final lebanon = kSupportRegions.firstWhere(
        (region) => region.id == SupportRegionId.lebanon,
      );
      await tester.tap(find.text('Lebanon'));
      await tester.pumpAndSettle();

      // Lebanon's Beirut office location (from officeLocations) is shown...
      expect(find.text('Beirut'), findsOneWidget);
      // ...but the separate, no-longer-used-by-Support officeAddress
      // string is not.
      expect(find.text(lebanon.officeAddress!), findsNothing);
    });
  });

  group('Hotline tap-to-call flow', () {
    final singleNumberRegion = SupportRegionData(
      id: SupportRegionId.uae,
      displayName: 'PhoneLand',
      hotlineNumbers: const ['+961 1 275 019'],
    );
    final multiNumberRegion = SupportRegionData(
      id: SupportRegionId.uae,
      displayName: 'MultiLand',
      hotlineNumbers: const ['+971 4 123 4567', '+971 4 987 6543'],
    );

    Future<void> pumpSupportWithPhoneRegions(
      WidgetTester tester,
      List<SupportRegionData> regions,
      PhoneLauncher launcher,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          supportedLocales: const [Locale('en'), Locale('ar'), Locale('fr')],
          localizationsDelegates: const [
            AppTranslationsDelegate(),
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: SupportScreen(regions: regions, phoneLauncher: launcher),
        ),
      );
      await tester.pumpAndSettle();
    }

    // The hotline card sits below the fold at the default test viewport, so
    // every tap needs to scroll it into view first.
    Finder hotlineFinder(String number) =>
        find.byKey(ValueKey('support-hotline-number-$number'));

    Future<void> tapHotlineNumber(WidgetTester tester, String number) async {
      final finder = hotlineFinder(number);
      await tester.ensureVisible(finder);
      await tester.pumpAndSettle();
      await tester.tap(finder);
      await tester.pumpAndSettle();
    }

    testWidgets('Hotline numbers render for the default region', (
      tester,
    ) async {
      await pumpSupportWithPhoneRegions(tester, [
        singleNumberRegion,
      ], PhoneLauncher(client: FakeUrlLauncherClient()));

      await tester.ensureVisible(
        hotlineFinder(singleNumberRegion.hotlineNumbers.first),
      );
      expect(
        hotlineFinder(singleNumberRegion.hotlineNumbers.first),
        findsOneWidget,
      );
    });

    testWidgets('Tapping a hotline number launches a tel: URI with that exact '
        'normalized number, preserving the leading + and stripping display '
        'formatting', (tester) async {
      final client = FakeUrlLauncherClient(telResult: true);
      await pumpSupportWithPhoneRegions(tester, [
        singleNumberRegion,
      ], PhoneLauncher(client: client));

      await tapHotlineNumber(tester, singleNumberRegion.hotlineNumbers.first);

      expect(client.attemptedUris, hasLength(1));
      expect(client.attemptedUris.single.toString(), 'tel:+9611275019');
      expect(tester.takeException(), isNull);
    });

    testWidgets('No country code is guessed for a local hotline number', (
      tester,
    ) async {
      final client = FakeUrlLauncherClient(telResult: true);
      final localRegion = SupportRegionData(
        id: SupportRegionId.oman,
        displayName: 'LocalLand',
        hotlineNumbers: const ['(01) 234 567'],
      );
      await pumpSupportWithPhoneRegions(tester, [
        localRegion,
      ], PhoneLauncher(client: client));

      await tapHotlineNumber(tester, localRegion.hotlineNumbers.first);

      expect(client.attemptedUris.single.toString(), 'tel:01234567');
    });

    testWidgets(
      'With multiple hotline numbers, tapping the second launches only the '
      'second number',
      (tester) async {
        final client = FakeUrlLauncherClient(telResult: true);
        await pumpSupportWithPhoneRegions(tester, [
          multiNumberRegion,
        ], PhoneLauncher(client: client));

        await tapHotlineNumber(tester, multiNumberRegion.hotlineNumbers[1]);

        expect(client.attemptedUris, hasLength(1));
        expect(client.attemptedUris.single.toString(), 'tel:+97149876543');
      },
    );

    testWidgets('Launch success shows no failure SnackBar', (tester) async {
      final client = FakeUrlLauncherClient(telResult: true);
      await pumpSupportWithPhoneRegions(tester, [
        singleNumberRegion,
      ], PhoneLauncher(client: client));

      await tapHotlineNumber(tester, singleNumberRegion.hotlineNumbers.first);

      expect(
        find.text('Unable to open the phone dialer. Please try again.'),
        findsNothing,
      );
      expect(find.text('This hotline number is not available.'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Launch returning false shows a user-friendly failure '
        'message', (tester) async {
      final client = FakeUrlLauncherClient(telResult: false);
      await pumpSupportWithPhoneRegions(tester, [
        singleNumberRegion,
      ], PhoneLauncher(client: client));

      await tapHotlineNumber(tester, singleNumberRegion.hotlineNumbers.first);

      expect(
        find.text('Unable to open the phone dialer. Please try again.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('Launch throwing shows a user-friendly failure message', (
      tester,
    ) async {
      final client = FakeUrlLauncherClient(
        telResult: Exception('dialer launch failed'),
      );
      await pumpSupportWithPhoneRegions(tester, [
        singleNumberRegion,
      ], PhoneLauncher(client: client));

      await tapHotlineNumber(tester, singleNumberRegion.hotlineNumbers.first);

      expect(
        find.text('Unable to open the phone dialer. Please try again.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'An invalid hotline number never calls the launcher and shows the '
      'unavailable message',
      (tester) async {
        final client = FakeUrlLauncherClient();
        const invalidRegion = SupportRegionData(
          id: SupportRegionId.iraq,
          displayName: 'InvalidLand',
          // Formatting characters only, with no usable digits — text is
          // non-empty (unlike '') so the tap can hit-test the row.
          hotlineNumbers: ['(--)'],
        );
        await pumpSupportWithPhoneRegions(tester, [
          invalidRegion,
        ], PhoneLauncher(client: client));

        await tapHotlineNumber(tester, invalidRegion.hotlineNumbers.first);

        expect(client.attemptedUris, isEmpty);
        expect(
          find.text('This hotline number is not available.'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets("Selecting another region before tapping uses the new region's "
        "hotline number, not the previous region's", (tester) async {
      final client = FakeUrlLauncherClient(telResult: true);
      final regionA = SupportRegionData(
        id: SupportRegionId.uae,
        displayName: 'HotlineRegionA',
        hotlineNumbers: const ['+971 4 123 4567'],
      );
      final regionB = SupportRegionData(
        id: SupportRegionId.lebanon,
        displayName: 'HotlineRegionB',
        hotlineNumbers: const ['+961 1 275 019'],
      );
      await pumpSupportWithPhoneRegions(tester, [
        regionA,
        regionB,
      ], PhoneLauncher(client: client));

      // The pill renders the localized country name for regionB.id
      // (Lebanon), not its custom test-only displayName.
      await tester.tap(find.text('Lebanon'));
      await tester.pumpAndSettle();

      await tapHotlineNumber(tester, regionB.hotlineNumbers.first);

      expect(client.attemptedUris, hasLength(1));
      expect(client.attemptedUris.single.toString(), 'tel:+9611275019');
    });

    testWidgets(
      'Repeated region changes do not leave stale hotline numbers behind',
      (tester) async {
        final client = FakeUrlLauncherClient(telResult: true);
        final regionA = SupportRegionData(
          id: SupportRegionId.uae,
          displayName: 'HotlineRegionA',
          hotlineNumbers: const ['+971 4 123 4567'],
        );
        final regionB = SupportRegionData(
          id: SupportRegionId.lebanon,
          displayName: 'HotlineRegionB',
          hotlineNumbers: const ['+961 1 275 019'],
        );
        await pumpSupportWithPhoneRegions(tester, [
          regionA,
          regionB,
        ], PhoneLauncher(client: client));

        // Both pills render the localized country name for their id (UAE,
        // Lebanon), not their custom test-only displayName.
        for (var i = 0; i < 3; i++) {
          await tester.tap(find.text('Lebanon'));
          await tester.pumpAndSettle();
          expect(hotlineFinder(regionA.hotlineNumbers.first), findsNothing);

          await tester.tap(find.text('UAE'));
          await tester.pumpAndSettle();
          expect(hotlineFinder(regionB.hotlineNumbers.first), findsNothing);
        }
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('Rapid repeated taps only trigger a single dialer launch', (
      tester,
    ) async {
      final inFlight = Completer<bool>();
      final client = _ControlledUrlLauncherClient(inFlight.future);
      await pumpSupportWithPhoneRegions(tester, [
        singleNumberRegion,
      ], PhoneLauncher(client: client));

      final number = hotlineFinder(singleNumberRegion.hotlineNumbers.first);
      await tester.ensureVisible(number);
      await tester.pumpAndSettle();
      await tester.tap(number);
      await tester.tap(number);
      await tester.tap(number);

      expect(client.attemptedUris, hasLength(1));

      inFlight.complete(true);
      await tester.pumpAndSettle();

      expect(client.attemptedUris, hasLength(1));
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('Email button opens the Contact Us screen without throwing', (
    tester,
  ) async {
    await pumpSupport(tester);

    // The bottom navigation footer now occupies part of the default test
    // viewport's height, so the email button — well below the fold on a
    // short screen — needs an explicit scroll into view before tapping.
    await tester.ensureVisible(
      find.byKey(const ValueKey('support-email-button')),
    );
    await tester.tap(find.byKey(const ValueKey('support-email-button')));
    await tester.pumpAndSettle();
    expect(find.byType(ContactUsScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  group('Region loading', () {
    testWidgets(
      'Shows a loading indicator while regions are being fetched, then the '
      'loaded region content',
      (tester) async {
        final pending = Completer<List<SupportRegionData>>();
        await tester.pumpWidget(
          MaterialApp(
            supportedLocales: const [Locale('en'), Locale('ar'), Locale('fr')],
            localizationsDelegates: const [
              AppTranslationsDelegate(),
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: SupportScreen(
              regionService: _ControlledSupportRegionService(pending.future),
            ),
          ),
        );
        await tester.pump();

        expect(
          find.byKey(const ValueKey('support-regions-loading')),
          findsOneWidget,
        );
        expect(find.byType(SupportRegionSelector), findsNothing);

        pending.complete(kSupportRegions);
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('support-regions-loading')),
          findsNothing,
        );
        expect(find.text(kSupportRegions.first.displayName), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'A region service that throws falls back to local support region '
      'data instead of crashing or getting stuck loading',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            supportedLocales: const [Locale('en'), Locale('ar'), Locale('fr')],
            localizationsDelegates: const [
              AppTranslationsDelegate(),
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: SupportScreen(regionService: _ThrowingSupportRegionService()),
          ),
        );
        await tester.pumpAndSettle();

        for (final region in kSupportRegions) {
          expect(find.text(region.displayName), findsOneWidget);
        }
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'A region service that resolves with no regions falls back to local '
      'support region data instead of leaving the screen empty',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            supportedLocales: const [Locale('en'), Locale('ar'), Locale('fr')],
            localizationsDelegates: const [
              AppTranslationsDelegate(),
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: SupportScreen(regionService: _EmptySupportRegionService()),
          ),
        );
        await tester.pumpAndSettle();

        for (final region in kSupportRegions) {
          expect(find.text(region.displayName), findsOneWidget);
        }
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'Passing an explicit regions override skips the region service and '
      'loads synchronously',
      (tester) async {
        final region = SupportRegionData(
          id: SupportRegionId.uae,
          displayName: 'OverrideLand',
        );
        await tester.pumpWidget(
          MaterialApp(
            supportedLocales: const [Locale('en'), Locale('ar'), Locale('fr')],
            localizationsDelegates: const [
              AppTranslationsDelegate(),
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: SupportScreen(regions: [region]),
          ),
        );
        await tester.pump();

        expect(
          find.byKey(const ValueKey('support-regions-loading')),
          findsNothing,
        );
        // The pill renders the localized country name for the override
        // region's id (UAE), not its custom test-only displayName — so the
        // override is instead confirmed via the selector's own region list.
        final selector = tester.widget<SupportRegionSelector>(
          find.byType(SupportRegionSelector),
        );
        expect(selector.regions, [region]);
        expect(find.text('UAE'), findsOneWidget);
      },
    );
  });

  group('Login country default region', () {
    Future<void> pumpSupportForCountry(
      WidgetTester tester,
      String? country,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          supportedLocales: const [Locale('en'), Locale('ar'), Locale('fr')],
          localizationsDelegates: const [
            AppTranslationsDelegate(),
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: SupportScreen(
            authService: _authServiceFor(
              country == null ? null : _sessionWithCountry(country),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    for (final entry in <String, SupportRegionId>{
      'LB': SupportRegionId.lebanon,
      'SY': SupportRegionId.syria,
      'IQ': SupportRegionId.iraq,
      'AE': SupportRegionId.uae,
      'OM': SupportRegionId.oman,
    }.entries) {
      final country = entry.key;
      final expectedRegionId = entry.value;

      testWidgets('Login country $country defaults Support to '
          '${expectedRegionId.name}, visibly selected', (tester) async {
        await pumpSupportForCountry(tester, country);

        final expectedRegion = kSupportRegions.firstWhere(
          (region) => region.id == expectedRegionId,
        );

        final selector = tester.widget<SupportRegionSelector>(
          find.byType(SupportRegionSelector),
        );
        expect(selector.selectedRegionId, expectedRegionId);
        // The region-scoped content (e.g. a verified office location)
        // renders from the defaulted region immediately, not just the
        // selector's internal state.
        if (expectedRegion.officeLocations.isNotEmpty) {
          expect(
            find.text(expectedRegion.officeLocations.first.city),
            findsOneWidget,
          );
        }
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets(
      'A session with no recognized country falls back to the first region',
      (tester) async {
        await pumpSupportForCountry(tester, 'US');

        final selector = tester.widget<SupportRegionSelector>(
          find.byType(SupportRegionSelector),
        );
        expect(selector.selectedRegionId, kSupportRegions.first.id);
      },
    );

    testWidgets(
      'No persisted session (e.g. a legacy/unauthenticated read) falls '
      'back to the first region',
      (tester) async {
        await pumpSupportForCountry(tester, null);

        final selector = tester.widget<SupportRegionSelector>(
          find.byType(SupportRegionSelector),
        );
        expect(selector.selectedRegionId, kSupportRegions.first.id);
      },
    );

    testWidgets('Manually switching region after the login-country default is '
        'applied is preserved, not reset back', (tester) async {
      await pumpSupportForCountry(tester, 'LB');

      final selector = tester.widget<SupportRegionSelector>(
        find.byType(SupportRegionSelector),
      );
      expect(selector.selectedRegionId, SupportRegionId.lebanon);

      final syria = kSupportRegions.firstWhere(
        (region) => region.id == SupportRegionId.syria,
      );
      await tester.tap(find.text(syria.displayName));
      await tester.pumpAndSettle();

      final updatedSelector = tester.widget<SupportRegionSelector>(
        find.byType(SupportRegionSelector),
      );
      expect(updatedSelector.selectedRegionId, SupportRegionId.syria);

      // Pumping further (simulating time passing, e.g. any late-settling
      // async work) must never silently revert the manual choice back to
      // the login country.
      await tester.pump(const Duration(seconds: 1));
      final settledSelector = tester.widget<SupportRegionSelector>(
        find.byType(SupportRegionSelector),
      );
      expect(settledSelector.selectedRegionId, SupportRegionId.syria);
    });

    testWidgets(
      'The Support-selected region (after switching away from the login '
      'country) is passed to Contact Us, taking priority over login country',
      (tester) async {
        await pumpSupportForCountry(tester, 'LB');

        final syria = kSupportRegions.firstWhere(
          (region) => region.id == SupportRegionId.syria,
        );
        await tester.tap(find.text(syria.displayName));
        await tester.pumpAndSettle();

        await tester.ensureVisible(
          find.byKey(const ValueKey('support-email-button')),
        );
        await tester.tap(find.byKey(const ValueKey('support-email-button')));
        await tester.pumpAndSettle();

        expect(find.byType(ContactUsScreen), findsOneWidget);
        final contactUs = tester.widget<ContactUsScreen>(
          find.byType(ContactUsScreen),
        );
        expect(contactUs.region?.id, SupportRegionId.syria);
        // The region selector is hidden on Contact Us since an explicit
        // region was handed off — confirming priority over the login
        // country, not just a matching id.
        expect(find.byType(SupportRegionSelector), findsNothing);
        // Syria-specific contact content (its Regional Contacts section)
        // renders, confirming the hand-off drove real content, not just the
        // widget's region field.
        expect(find.text('REGIONAL CONTACTS'), findsOneWidget);
      },
    );
  });

  group('Bottom navigation', () {
    // SupportScreen's own app bar title is also the literal text "Support"
    // (see 'support.title'), so a plain `find.text('Support')` is ambiguous
    // here — this scopes the match to the footer's own tab label.
    Finder supportNavTab() => find.descendant(
      of: find.byType(CustomBottomNav),
      matching: find.text('Support'),
    );

    testWidgets('Shows the Home, Orders, Support, and Profile tabs', (
      tester,
    ) async {
      await pumpSupport(tester);

      expect(find.text('Home'), findsOneWidget);
      expect(find.text('Orders'), findsOneWidget);
      expect(supportNavTab(), findsOneWidget);
      expect(find.text('Profile'), findsOneWidget);
    });

    testWidgets('Reuses CustomBottomNav with Support selected', (tester) async {
      await pumpSupport(tester);

      expect(find.byType(CustomBottomNav), findsOneWidget);
      expect(find.byType(CustomBottomNavItem), findsNWidgets(4));

      final bottomNav = tester.widget<CustomBottomNav>(
        find.byType(CustomBottomNav),
      );
      expect(bottomNav.currentIndex, 2);
    });

    testWidgets(
      'Selecting the already-selected Support tab does not push a new '
      'route',
      (tester) async {
        await pumpSupport(tester);

        await tester.tap(supportNavTab());
        await tester.pumpAndSettle();

        expect(find.byType(SupportScreen), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'Selecting Home is safe when there is no screen to pop back to',
      (tester) async {
        await pumpSupport(tester);

        await tester.tap(find.text('Home'));
        await tester.pumpAndSettle();

        expect(find.byType(SupportScreen), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('Selecting Orders and Profile pushes each screen', (
      tester,
    ) async {
      await pumpSupport(tester);

      await tester.tap(find.text('Orders'));
      await tester.pumpAndSettle();
      expect(find.byType(OrdersScreen), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();

      await tester.tap(find.text('Profile'));
      await tester.pumpAndSettle();
      expect(find.byType(EditProfileScreen), findsOneWidget);
    });

    testWidgets(
      'Hopping between tabs repeatedly never leaves duplicate screens on '
      'the stack',
      (tester) async {
        await pumpSupport(tester);

        await tester.tap(find.text('Orders'));
        await tester.pumpAndSettle();
        await tester.tap(supportNavTab());
        await tester.pumpAndSettle();
        await tester.tap(find.text('Orders'));
        await tester.pumpAndSettle();

        expect(find.byType(OrdersScreen), findsOneWidget);
        expect(find.byType(SupportScreen), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('Contact Us (a nested screen) does not show the footer', (
      tester,
    ) async {
      await pumpSupport(tester);

      await tester.ensureVisible(
        find.byKey(const ValueKey('support-email-button')),
      );
      await tester.tap(find.byKey(const ValueKey('support-email-button')));
      await tester.pumpAndSettle();

      expect(find.byType(ContactUsScreen), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(ContactUsScreen),
          matching: find.byType(CustomBottomNav),
        ),
        findsNothing,
      );
    });
  });

  group('Localization', () {
    testWidgets('Region selector pills render the localized country name in '
        'English, Arabic, and French', (tester) async {
      await pumpSupportLocale(tester, const Locale('en'));
      for (final name in ['UAE', 'Syria', 'Iraq', 'Oman', 'Lebanon']) {
        expect(find.text(name), findsOneWidget);
      }

      await pumpSupportLocale(tester, const Locale('ar'));
      for (final name in [
        'الإمارات العربية المتحدة',
        'سوريا',
        'العراق',
        'عُمان',
        'لبنان',
      ]) {
        expect(find.text(name), findsOneWidget);
      }
      // None of the raw English country names leak through in Arabic.
      for (final name in ['UAE', 'Syria', 'Iraq', 'Oman', 'Lebanon']) {
        expect(find.text(name), findsNothing);
      }
      final arContext = tester.element(find.byType(SupportScreen));
      expect(Directionality.of(arContext), TextDirection.rtl);

      await pumpSupportLocale(tester, const Locale('fr'));
      for (final name in [
        'Émirats arabes unis',
        'Syrie',
        'Irak',
        'Oman',
        'Liban',
      ]) {
        expect(find.text(name), findsOneWidget);
      }
      // None of the raw English country names leak through in French
      // (Oman is spelled the same in EN/FR, so it's excluded here).
      for (final name in ['UAE', 'Syria', 'Iraq', 'Lebanon']) {
        expect(find.text(name), findsNothing);
      }
      final frContext = tester.element(find.byType(SupportScreen));
      expect(Directionality.of(frContext), TextDirection.ltr);

      await pumpSupportLocale(tester, const Locale('en'));
      final enContext = tester.element(find.byType(SupportScreen));
      expect(Directionality.of(enContext), TextDirection.ltr);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Live language switch EN -> AR -> FR updates the region '
        'selector without navigating away or remounting the screen', (
      tester,
    ) async {
      final hostKey = GlobalKey<_LocaleHostState>();
      await tester.pumpWidget(
        _LocaleHost(key: hostKey, child: const SupportScreen()),
      );
      await tester.pumpAndSettle();

      expect(find.text('Lebanon'), findsOneWidget);
      expect(find.text('لبنان'), findsNothing);
      expect(
        Directionality.of(tester.element(find.byType(SupportScreen))),
        TextDirection.ltr,
      );

      hostKey.currentState!.setLocale(const Locale('ar'));
      await tester.pumpAndSettle();
      expect(find.text('لبنان'), findsOneWidget);
      expect(find.text('Lebanon'), findsNothing);
      expect(
        Directionality.of(tester.element(find.byType(SupportScreen))),
        TextDirection.rtl,
      );

      hostKey.currentState!.setLocale(const Locale('fr'));
      await tester.pumpAndSettle();
      expect(find.text('Liban'), findsOneWidget);
      expect(find.text('لبنان'), findsNothing);
      expect(
        Directionality.of(tester.element(find.byType(SupportScreen))),
        TextDirection.ltr,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('Arabic: hotline phone numbers stay LTR-readable even while '
        'the rest of the screen is RTL', (tester) async {
      final client = FakeUrlLauncherClient();
      final region = SupportRegionData(
        id: SupportRegionId.lebanon,
        displayName: 'Lebanon',
        hotlineNumbers: const ['+961 79 303 551', '+961 81 107 942'],
      );
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('ar'),
          supportedLocales: const [Locale('en'), Locale('ar'), Locale('fr')],
          localizationsDelegates: const [
            AppTranslationsDelegate(),
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: SupportScreen(
            regions: [region],
            phoneLauncher: PhoneLauncher(client: client),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final screenContext = tester.element(find.byType(SupportScreen));
      expect(Directionality.of(screenContext), TextDirection.rtl);

      for (final number in region.hotlineNumbers) {
        final numberContext = tester.element(find.text(number));
        expect(Directionality.of(numberContext), TextDirection.ltr);
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets("Lebanon's Corporate Office city/address switch language "
        'with the selected locale; the phone numbers below do not', (
      tester,
    ) async {
      final lebanon = kSupportRegions.firstWhere(
        (region) => region.id == SupportRegionId.lebanon,
      );

      await pumpSupportLocale(tester, const Locale('en'));
      final enPill = find.text('Lebanon');
      await tester.ensureVisible(enPill);
      await tester.tap(enPill);
      await tester.pumpAndSettle();
      expect(find.text('Beirut'), findsOneWidget);
      expect(find.text(_lebanonBeirutAddressEn), findsOneWidget);

      await pumpSupportLocale(tester, const Locale('ar'));
      final arPill = find.text('لبنان');
      await tester.ensureVisible(arPill);
      await tester.tap(arPill);
      await tester.pumpAndSettle();
      expect(find.text('بيروت'), findsOneWidget);
      expect(find.text('بجانب السفارة الكويتية'), findsOneWidget);
      for (final number in lebanon.hotlineNumbers) {
        expect(find.text(number), findsOneWidget);
      }

      await pumpSupportLocale(tester, const Locale('fr'));
      final frPill = find.text('Liban');
      await tester.ensureVisible(frPill);
      await tester.tap(frPill);
      await tester.pumpAndSettle();
      expect(find.text('Beyrouth'), findsOneWidget);
      expect(find.text("À côté de l'ambassade du Koweït"), findsOneWidget);
      for (final number in lebanon.hotlineNumbers) {
        expect(find.text(number), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    });
  });
}

/// Hosts [child] under a [MaterialApp] whose `locale` can be switched live
/// via [_LocaleHostState.setLocale], without ever calling `pumpWidget`
/// again — unlike `pumpSupportLocale`, which tears down and rebuilds the
/// whole tree on every call. This is the only way to catch a region label
/// that resolves correctly on first build but fails to update when the
/// app's language is switched mid-session (the real app's actual
/// language-switch mechanism: `LocaleController.setLocale` notifies a
/// `ListenableBuilder` that rebuilds `MaterialApp` in place).
class _LocaleHost extends StatefulWidget {
  const _LocaleHost({super.key, required this.child});

  final Widget child;

  @override
  State<_LocaleHost> createState() => _LocaleHostState();
}

class _LocaleHostState extends State<_LocaleHost> {
  Locale _locale = const Locale('en');

  void setLocale(Locale locale) => setState(() => _locale = locale);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      locale: _locale,
      supportedLocales: const [Locale('en'), Locale('ar'), Locale('fr')],
      localizationsDelegates: const [
        AppTranslationsDelegate(),
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: widget.child,
    );
  }
}

/// Fake [SupportRegionService] whose fetch stays pending until the caller
/// completes [result], used to observe the loading state while the fetch is
/// still in flight.
class _ControlledSupportRegionService implements SupportRegionService {
  _ControlledSupportRegionService(this.result);

  final Future<List<SupportRegionData>> result;

  @override
  Future<List<SupportRegionData>> fetchSupportRegions() => result;
}

/// Fake [SupportRegionService] simulating a CMS/API outage.
class _ThrowingSupportRegionService implements SupportRegionService {
  @override
  Future<List<SupportRegionData>> fetchSupportRegions() async {
    throw Exception('support regions unavailable');
  }
}

/// Fake [SupportRegionService] simulating a CMS/API response with no
/// regions.
class _EmptySupportRegionService implements SupportRegionService {
  @override
  Future<List<SupportRegionData>> fetchSupportRegions() async => [];
}

/// Fake [UrlLauncherClient] whose native launch stays pending until the
/// caller completes [result], used to observe the launch-in-progress
/// guard while a launch attempt is still in flight.
class _ControlledUrlLauncherClient implements UrlLauncherClient {
  _ControlledUrlLauncherClient(this.result);

  final Future<bool> result;
  final List<Uri> attemptedUris = [];

  @override
  Future<bool> launch(Uri uri) {
    attemptedUris.add(uri);
    return result;
  }
}
