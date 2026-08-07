// Widget checks for the Support screen: intro content, the region
// selector's initial/selected state, and that the WhatsApp/Email/Hotline
// actions respond safely without throwing.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anc_fabrics/data/support_regions_data.dart';
import 'package:anc_fabrics/models/support_region.dart';
import 'package:anc_fabrics/screens/contact_us_screen.dart';
import 'package:anc_fabrics/screens/edit_profile_screen.dart';
import 'package:anc_fabrics/screens/orders_screen.dart';
import 'package:anc_fabrics/screens/support_screen.dart';
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

import 'helpers/fake_url_launcher_client.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:anc_fabrics/localization/app_translations_delegate.dart';

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
    expect(
      find.text(
        'Office details for ${lebanon.displayName} will be added soon.',
      ),
      findsOneWidget,
    );
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
        expect(
          find.text(
            'Office details for ${region.displayName} will be added soon.',
          ),
          findsOneWidget,
        );
        expect(
          find.text(
            'Support hours for ${region.displayName} will be confirmed '
            'soon.',
          ),
          findsOneWidget,
        );

        for (final other in kSupportRegions) {
          if (other.id == region.id) continue;
          expect(
            find.text(
              'Office details for ${other.displayName} will be added soon.',
            ),
            findsNothing,
          );
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

        expect(
          find.text(
            "Couldn't open WhatsApp for ${testRegion.displayName}. Please "
            'try again later.',
          ),
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
        expect(
          find.text(
            'WhatsApp support is not available for '
            '${unavailableRegion.displayName} yet.',
          ),
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

        await tester.tap(find.text(regionB.displayName));
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

      await tester.tap(find.text(regionB.displayName));
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

        for (var i = 0; i < 3; i++) {
          await tester.tap(find.text(regionB.displayName));
          await tester.pumpAndSettle();
          expect(hotlineFinder(regionA.hotlineNumbers.first), findsNothing);

          await tester.tap(find.text(regionA.displayName));
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
        expect(find.text('OverrideLand'), findsOneWidget);
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
