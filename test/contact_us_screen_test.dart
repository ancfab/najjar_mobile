// Widget checks for the Contact Us screen: navigation from/to the Support
// landing screen, region-aware contact info (email/office/hotline/regional
// contacts), the region selector shown when no region is supplied, tappable
// Email/Call actions, form validation, and the mailto-based Send action
// (replacing the old unconnected submission service).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anc_fabrics/data/support_regions_data.dart';
import 'package:anc_fabrics/models/contact_subject.dart';
import 'package:anc_fabrics/models/support_region.dart';
import 'package:anc_fabrics/screens/contact_us_screen.dart';
import 'package:anc_fabrics/screens/support_screen.dart';
import 'package:anc_fabrics/services/email_launcher.dart';
import 'package:anc_fabrics/services/phone_launcher.dart';
import 'package:anc_fabrics/services/url_launcher_client.dart';

import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:anc_fabrics/localization/app_translations_delegate.dart';

import 'helpers/fake_url_launcher_client.dart';

// English translations for the addresses/areas/availability that now have
// confirmed translation keys (see assets/translation/english.json under
// supportAddress/supportArea/supportAvailability) — these screens render
// these values instead of the raw stored literal once a key is set.
const _lebanonOfficeAddressEn = 'Airport Road - ANC Najjar Fabric';
const _uaeSharjahAddressEn = 'Industrial City, Zone 18';
const _syriaDamascusAddressEn =
    'Damascus International Airport Road, ANC Najjar Fabric';
const _lebanonBeirutAddressEn = 'Next to the Kuwaiti Embassy';
const _ezzAvailabilityEn = 'From 6:00 PM to 9:00 PM';
const _syriaAreaTranslationsEn = {
  'درعا - السويداء': 'Daraa - Sweida',
  'إدلب': 'Idlib',
  'مركز المدينة وغوطة غربية': 'City Center & Western Ghouta',
  'غوطة شرقية': 'Eastern Ghouta',
  'حمص - حماة': 'Homs - Hama',
  'الساحل': 'The Coast',
  'جميع المحافظات': 'All Governorates',
  'دمشق': 'Damascus',
};

void main() {
  SupportRegionData region(SupportRegionId id) =>
      kSupportRegions.firstWhere((r) => r.id == id);

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

  Future<void> pumpContactUs(
    WidgetTester tester, {
    SupportRegionData? region,
    PhoneLauncher? phoneLauncher,
    EmailLauncher? emailLauncher,
    String? initialName,
    String? initialEmail,
    Locale locale = const Locale('en'),
  }) async {
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
        home: ContactUsScreen(
          region: region,
          phoneLauncher: phoneLauncher ?? const PhoneLauncher(),
          emailLauncher: emailLauncher ?? const EmailLauncher(),
          initialName: initialName,
          initialEmail: initialEmail,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> fillValidForm(
    WidgetTester tester, {
    String subjectLabel = 'Technical Support',
  }) async {
    await tester.enterText(
      find.byKey(const ValueKey('contact-full-name-field')),
      'Jane Weaver',
    );
    await tester.enterText(
      find.byKey(const ValueKey('contact-work-email-field')),
      'jane@textile.co',
    );
    await tester.ensureVisible(
      find.byKey(const ValueKey('contact-subject-field')),
    );
    await tester.tap(find.byKey(const ValueKey('contact-subject-field')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(subjectLabel).last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('contact-message-field')),
      'We need help scheduling a shipment.',
    );
  }

  // Reads a field's live controller text directly rather than via
  // find.text(...), since the full name/email fields' hintText ('Jane
  // Weaver' / 'jane@textile.co') stays mounted (only faded, not removed)
  // once the field has content, and would otherwise produce a false
  // "found 2" match whenever a test's entered value happens to equal the
  // hint sample.
  String fieldText(WidgetTester tester, Key key) {
    return tester.widget<TextFormField>(find.byKey(key)).controller!.text;
  }

  group('Navigation integration', () {
    testWidgets('Tapping EMAIL SUPPORT opens ContactUsScreen', (tester) async {
      await pumpSupport(tester);

      await tester.ensureVisible(
        find.byKey(const ValueKey('support-email-button')),
      );
      await tester.tap(find.byKey(const ValueKey('support-email-button')));
      await tester.pumpAndSettle();

      expect(find.byType(ContactUsScreen), findsOneWidget);
      expect(find.byType(SupportScreen), findsNothing);
    });

    testWidgets('Screen displays Back to Support', (tester) async {
      await pumpContactUs(tester);

      expect(find.text('Back to Support'), findsOneWidget);
    });

    testWidgets('Tapping EMAIL SUPPORT passes the currently selected region '
        "to ContactUsScreen, with that region's verified contact info shown "
        'and no region selector', (tester) async {
      await pumpSupport(tester);

      final lebanon = region(SupportRegionId.lebanon);
      await tester.tap(find.text(lebanon.displayName));
      await tester.pumpAndSettle();

      await tester.ensureVisible(
        find.byKey(const ValueKey('support-email-button')),
      );
      await tester.tap(find.byKey(const ValueKey('support-email-button')));
      await tester.pumpAndSettle();

      final contactUsScreen = tester.widget<ContactUsScreen>(
        find.byType(ContactUsScreen),
      );
      expect(contactUsScreen.region?.id, lebanon.id);
      expect(find.text(lebanon.supportEmail!), findsOneWidget);
      expect(find.text(_lebanonOfficeAddressEn), findsOneWidget);
      expect(
        find.byKey(const ValueKey('contact-region-selector')),
        findsNothing,
      );
    });

    testWidgets('Tapping Back to Support returns to SupportScreen', (
      tester,
    ) async {
      await pumpSupport(tester);

      await tester.ensureVisible(
        find.byKey(const ValueKey('support-email-button')),
      );
      await tester.tap(find.byKey(const ValueKey('support-email-button')));
      await tester.pumpAndSettle();
      expect(find.byType(ContactUsScreen), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey('contact-back-to-support-button')),
      );
      await tester.pumpAndSettle();

      expect(find.byType(SupportScreen), findsOneWidget);
      expect(find.byType(ContactUsScreen), findsNothing);
    });
  });

  group('Screen content (no initial region — default UAE selection)', () {
    testWidgets('Displays intro, region selector, contact summary, and '
        'form', (tester) async {
      await pumpContactUs(tester);

      expect(find.text('SUPPORT CENTER'), findsOneWidget);
      expect(find.text('Contact Us'), findsWidgets);
      expect(
        find.text(
          'Connect with our textile experts to streamline your supply '
          'chain or inquire about our premium weave collections.',
        ),
        findsOneWidget,
      );

      expect(
        find.byKey(const ValueKey('contact-region-selector')),
        findsOneWidget,
      );
      for (final r in kSupportRegions) {
        expect(find.text(r.displayName), findsOneWidget);
      }

      expect(
        find.byKey(const ValueKey('contact-full-name-field')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('contact-work-email-field')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('contact-subject-field')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('contact-message-field')),
        findsOneWidget,
      );
      expect(find.text('SEND EMAIL'), findsOneWidget);

      final uae = region(SupportRegionId.uae);
      expect(find.text('EMAIL US'), findsOneWidget);
      expect(find.text(uae.supportEmail!), findsOneWidget);
      expect(find.text('CALL US'), findsOneWidget);
      expect(find.text(uae.hotlineNumbers.single), findsOneWidget);
      expect(
        find.byKey(const ValueKey('contact-main-office-card')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('contact-regional-contacts-section')),
        findsNothing,
      );
    });
  });

  group('Region-aware contact data', () {
    testWidgets('Lebanon shows verified email + office + all three verified '
        'phone numbers as separate Call actions, no regional contacts', (
      tester,
    ) async {
      final lebanon = region(SupportRegionId.lebanon);
      await pumpContactUs(tester, region: lebanon);

      expect(find.text(lebanon.supportEmail!), findsOneWidget);
      expect(find.text(_lebanonOfficeAddressEn), findsOneWidget);
      expect(lebanon.hotlineNumbers, hasLength(3));
      expect(
        find.byKey(const ValueKey('contact-call-us-card')),
        findsOneWidget,
      );
      for (final number in lebanon.hotlineNumbers) {
        expect(
          find.byKey(ValueKey('contact-hotline-number-$number')),
          findsOneWidget,
        );
        expect(find.text(number), findsOneWidget);
      }
      // Never presented as WhatsApp — no verified WhatsApp number exists.
      expect(lebanon.whatsappNumber, isNull);
      expect(find.textContaining('WhatsApp'), findsNothing);
      expect(
        find.byKey(const ValueKey('contact-regional-contacts-section')),
        findsNothing,
      );
    });

    testWidgets("Tapping each of Lebanon's three phone numbers launches the "
        'correct tel: URI', (tester) async {
      final lebanon = region(SupportRegionId.lebanon);
      final client = FakeUrlLauncherClient(telResult: true);
      await pumpContactUs(
        tester,
        region: lebanon,
        phoneLauncher: PhoneLauncher(client: client),
      );

      for (final number in lebanon.hotlineNumbers) {
        final finder = find.byKey(ValueKey('contact-hotline-number-$number'));
        await tester.ensureVisible(finder);
        await tester.tap(finder);
        await tester.pumpAndSettle();
      }

      expect(client.attemptedUris, hasLength(3));
      final normalized = client.attemptedUris
          .map((uri) => uri.toString())
          .toList();
      expect(
        normalized,
        containsAll([
          'tel:+96179303551',
          'tel:+96181107942',
          'tel:+96176408455',
        ]),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('UAE shows verified email + call, no office card, no '
        'regional contacts', (tester) async {
      final uae = region(SupportRegionId.uae);
      await pumpContactUs(tester, region: uae);

      expect(find.text(uae.supportEmail!), findsOneWidget);
      expect(find.text(uae.hotlineNumbers.single), findsOneWidget);
      expect(
        find.byKey(const ValueKey('contact-main-office-card')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('contact-regional-contacts-section')),
        findsNothing,
      );
    });

    testWidgets('Oman shows verified email + call, no office card, no '
        'regional contacts', (tester) async {
      final oman = region(SupportRegionId.oman);
      await pumpContactUs(tester, region: oman);

      expect(find.text(oman.supportEmail!), findsOneWidget);
      expect(find.text(oman.hotlineNumbers.single), findsOneWidget);
      expect(
        find.byKey(const ValueKey('contact-main-office-card')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('contact-regional-contacts-section')),
        findsNothing,
      );
    });

    testWidgets('Iraq shows only the verified email; office and call cards '
        'are both omitted (not shown with a placeholder)', (tester) async {
      final iraq = region(SupportRegionId.iraq);
      await pumpContactUs(tester, region: iraq);

      expect(find.text(iraq.supportEmail!), findsOneWidget);
      expect(
        find.byKey(const ValueKey('contact-main-office-card')),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('contact-call-us-card')), findsNothing);
      expect(
        find.byKey(const ValueKey('contact-regional-contacts-section')),
        findsNothing,
      );
    });

    testWidgets('Syria shows the verified email and a Regional Contacts '
        'section grouped into Upholstery Fabrics and Curtains', (tester) async {
      final syria = region(SupportRegionId.syria);
      await pumpContactUs(tester, region: syria);

      expect(find.text(syria.supportEmail!), findsOneWidget);
      expect(
        find.byKey(const ValueKey('contact-regional-contacts-section')),
        findsOneWidget,
      );
      expect(find.text('REGIONAL CONTACTS'), findsOneWidget);
      expect(find.text('Upholstery Fabrics'), findsOneWidget);
      expect(find.text('Curtains'), findsOneWidget);

      // Every representative's area is shown, translated (all Syria areas
      // have a confirmed supportArea.* translation key).
      for (final contact in syria.regionalContacts) {
        final translatedArea = _syriaAreaTranslationsEn[contact.area];
        expect(
          translatedArea,
          isNotNull,
          reason:
              'no EN translation stubbed '
              'in this test for area "${contact.area}"',
        );
        expect(find.text(translatedArea!), findsWidgets);
      }

      // عز has no phone of its own: no call action for it, but its
      // availability window is shown, translated.
      final ezz = syria.regionalContacts.firstWhere((c) => c.name == 'عز');
      expect(
        find.byKey(
          ValueKey(
            'regional-contact-call-${ezz.category.name}-${ezz.name}-'
            '${ezz.area}',
          ),
        ),
        findsNothing,
      );
      expect(find.text(_ezzAvailabilityEn), findsOneWidget);

      // A representative with a phone shows the number as call action.
      final rawiaIdlib = syria.regionalContacts.firstWhere(
        (c) => c.name == 'روى' && c.area == 'إدلب',
      );
      expect(find.text(rawiaIdlib.phone!), findsOneWidget);
    });
  });

  group('No invented placeholder contact information', () {
    for (final r in kSupportRegions) {
      testWidgets(
        '${r.displayName}: no "will be added soon" style fallback text '
        'appears',
        (tester) async {
          await pumpContactUs(tester, region: r);

          expect(find.textContaining('will be added soon'), findsNothing);
          expect(find.textContaining('not yet available'), findsNothing);
          expect(tester.takeException(), isNull);
        },
      );
    }
  });

  group('Region selector (no initial region)', () {
    testWidgets('Changing the selected region updates the displayed contact '
        'info immediately', (tester) async {
      await pumpContactUs(tester);

      final uae = region(SupportRegionId.uae);
      final lebanon = region(SupportRegionId.lebanon);
      expect(find.text(uae.supportEmail!), findsOneWidget);
      expect(find.text(lebanon.supportEmail!), findsNothing);

      await tester.tap(find.text(lebanon.displayName));
      await tester.pumpAndSettle();

      expect(find.text(lebanon.supportEmail!), findsOneWidget);
      expect(find.text(_lebanonOfficeAddressEn), findsOneWidget);
      expect(find.text(uae.hotlineNumbers.single), findsNothing);
    });

    testWidgets('Selecting Syria reveals the Regional Contacts section', (
      tester,
    ) async {
      await pumpContactUs(tester);

      expect(
        find.byKey(const ValueKey('contact-regional-contacts-section')),
        findsNothing,
      );

      await tester.tap(find.text('Syria'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('contact-regional-contacts-section')),
        findsOneWidget,
      );
    });
  });

  group('Email action (tap to open email app)', () {
    testWidgets('Tapping EMAIL US opens the device email app addressed to '
        "the region's verified email", (tester) async {
      final client = FakeUrlLauncherClient(webResult: true);
      final uae = region(SupportRegionId.uae);
      await pumpContactUs(
        tester,
        region: uae,
        emailLauncher: EmailLauncher(client: client),
      );

      await tester.tap(find.byKey(const ValueKey('contact-email-us-action')));
      await tester.pumpAndSettle();

      expect(client.attemptedUris, hasLength(1));
      final uri = client.attemptedUris.single;
      expect(uri.scheme, 'mailto');
      expect(uri.path, uae.supportEmail);
      expect(tester.takeException(), isNull);
    });

    testWidgets('A failed email app launch shows the approved error '
        'message', (tester) async {
      final client = FakeUrlLauncherClient(webResult: false);
      final uae = region(SupportRegionId.uae);
      await pumpContactUs(
        tester,
        region: uae,
        emailLauncher: EmailLauncher(client: client),
      );

      await tester.tap(find.byKey(const ValueKey('contact-email-us-action')));
      await tester.pumpAndSettle();

      expect(
        find.text("Couldn't open your email app. Please try again."),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('Call action (main hotline)', () {
    testWidgets('Tapping the phone number opens the dialer with a tel: URI', (
      tester,
    ) async {
      final client = FakeUrlLauncherClient(telResult: true);
      final uae = region(SupportRegionId.uae);
      await pumpContactUs(
        tester,
        region: uae,
        phoneLauncher: PhoneLauncher(client: client),
      );

      await tester.tap(
        find.byKey(
          ValueKey('contact-hotline-number-${uae.hotlineNumbers.single}'),
        ),
      );
      await tester.pumpAndSettle();

      expect(client.attemptedUris, hasLength(1));
      expect(client.attemptedUris.single.scheme, 'tel');
      expect(tester.takeException(), isNull);
    });

    testWidgets('A failed dialer launch shows the approved error message', (
      tester,
    ) async {
      final client = FakeUrlLauncherClient(telResult: false);
      final uae = region(SupportRegionId.uae);
      await pumpContactUs(
        tester,
        region: uae,
        phoneLauncher: PhoneLauncher(client: client),
      );

      await tester.tap(
        find.byKey(
          ValueKey('contact-hotline-number-${uae.hotlineNumbers.single}'),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Unable to open the phone dialer. Please try again.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('Call action (Syria regional contacts)', () {
    testWidgets("Tapping a representative's number opens the dialer with "
        'that number', (tester) async {
      final client = FakeUrlLauncherClient(telResult: true);
      final syria = region(SupportRegionId.syria);
      final rawiaIdlib = syria.regionalContacts.firstWhere(
        (c) => c.name == 'روى' && c.area == 'إدلب',
      );
      await pumpContactUs(
        tester,
        region: syria,
        phoneLauncher: PhoneLauncher(client: client),
      );

      final callButton = find.byKey(
        ValueKey(
          'regional-contact-call-${rawiaIdlib.category.name}-'
          '${rawiaIdlib.name}-${rawiaIdlib.area}',
        ),
      );
      await tester.ensureVisible(callButton);
      await tester.tap(callButton);
      await tester.pumpAndSettle();

      expect(client.attemptedUris, hasLength(1));
      expect(client.attemptedUris.single.toString(), 'tel:${rawiaIdlib.phone}');
      expect(tester.takeException(), isNull);
    });
  });

  group('Office locations', () {
    testWidgets('Syria renders both Damascus and Aleppo, each with its '
        'verified address and no phone/name placeholder', (tester) async {
      final syria = region(SupportRegionId.syria);
      await pumpContactUs(tester, region: syria);

      expect(
        find.byKey(const ValueKey('contact-locations-section')),
        findsOneWidget,
      );
      expect(find.text('LOCATIONS'), findsOneWidget);
      expect(syria.officeLocations, hasLength(2));
      final aleppo = syria.officeLocations.firstWhere(
        (l) => l.city == 'Aleppo',
      );
      // Damascus has a confirmed address translation; Aleppo's wording is
      // still unconfirmed, so it keeps rendering the raw stored literal.
      // Scoped to the Locations section: "Damascus" is also حلا's Curtains
      // area translation, rendered separately in Regional Contacts.
      final locationsSection = find.byKey(
        const ValueKey('contact-locations-section'),
      );
      expect(
        find.descendant(of: locationsSection, matching: find.text('Damascus')),
        findsOneWidget,
      );
      expect(find.text(_syriaDamascusAddressEn), findsOneWidget);
      expect(find.text('Aleppo'), findsOneWidget);
      expect(find.text(aleppo.address), findsOneWidget);
      for (final location in syria.officeLocations) {
        expect(location.phone, isNull);
        expect(location.name, isNull);
      }
    });

    testWidgets('Lebanon renders its verified Beirut location', (tester) async {
      final lebanon = region(SupportRegionId.lebanon);
      await pumpContactUs(tester, region: lebanon);

      expect(lebanon.officeLocations, hasLength(1));
      final beirut = lebanon.officeLocations.single;
      expect(beirut.city, 'Beirut');
      expect(find.text(beirut.city), findsOneWidget);
      expect(find.text(_lebanonBeirutAddressEn), findsOneWidget);
    });

    testWidgets(
      'UAE renders Sharjah with the Industrial Area 18 address and the '
      'ANC Najjar Fabric business name',
      (tester) async {
        final uae = region(SupportRegionId.uae);
        await pumpContactUs(tester, region: uae);

        expect(uae.officeLocations, hasLength(1));
        final sharjah = uae.officeLocations.single;
        expect(sharjah.city, 'Sharjah');
        expect(sharjah.address, 'المدينة الصناعية، منطقة 18');
        expect(sharjah.name, 'ANC Najjar Fabric');
        expect(find.text(sharjah.city), findsOneWidget);
        expect(find.text(_uaeSharjahAddressEn), findsOneWidget);
        expect(find.text(sharjah.name!), findsOneWidget);
      },
    );

    testWidgets('Oman renders the Muscat/Seeb location', (tester) async {
      final oman = region(SupportRegionId.oman);
      await pumpContactUs(tester, region: oman);

      expect(oman.officeLocations, hasLength(1));
      final muscat = oman.officeLocations.single;
      expect(find.text(muscat.city), findsOneWidget);
      expect(find.text(muscat.address), findsOneWidget);
    });

    testWidgets('Iraq renders both Erbil and Sulaymaniyah, each with its own '
        'verified phone number', (tester) async {
      final iraq = region(SupportRegionId.iraq);
      await pumpContactUs(tester, region: iraq);

      expect(iraq.officeLocations, hasLength(2));
      final erbil = iraq.officeLocations.firstWhere((l) => l.city == 'Erbil');
      final sulaymaniyah = iraq.officeLocations.firstWhere(
        (l) => l.city == 'Sulaymaniyah',
      );
      expect(erbil.phone, '+964 751 401 8777');
      expect(sulaymaniyah.phone, '+964 750 166 1000');

      expect(find.text(erbil.city), findsOneWidget);
      expect(find.text(erbil.address), findsOneWidget);
      expect(find.text(erbil.phone!), findsOneWidget);
      expect(find.text(sulaymaniyah.city), findsOneWidget);
      expect(find.text(sulaymaniyah.address), findsOneWidget);
      expect(find.text(sulaymaniyah.phone!), findsOneWidget);
    });

    testWidgets("Tapping Erbil's number produces tel:+9647514018777 and "
        "Sulaymaniyah's produces tel:+9647501661000", (tester) async {
      final client = FakeUrlLauncherClient(telResult: true);
      final iraq = region(SupportRegionId.iraq);
      await pumpContactUs(
        tester,
        region: iraq,
        phoneLauncher: PhoneLauncher(client: client),
      );

      final erbilCall = find.byKey(
        const ValueKey('office-location-call-Erbil'),
      );
      await tester.ensureVisible(erbilCall);
      await tester.tap(erbilCall);
      await tester.pumpAndSettle();

      final sulaymaniyahCall = find.byKey(
        const ValueKey('office-location-call-Sulaymaniyah'),
      );
      await tester.ensureVisible(sulaymaniyahCall);
      await tester.tap(sulaymaniyahCall);
      await tester.pumpAndSettle();

      expect(client.attemptedUris.map((uri) => uri.toString()).toList(), [
        'tel:+9647514018777',
        'tel:+9647501661000',
      ]);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Changing region updates the displayed locations', (
      tester,
    ) async {
      await pumpContactUs(tester);

      expect(find.text('Sharjah'), findsOneWidget);
      expect(find.text('Damascus'), findsNothing);

      await tester.tap(find.text('Syria'));
      await tester.pumpAndSettle();

      // Scoped to the Locations section: "Damascus" is also حلا's Curtains
      // area translation, rendered separately in Regional Contacts.
      final locationsSection = find.byKey(
        const ValueKey('contact-locations-section'),
      );
      expect(find.text('Sharjah'), findsNothing);
      expect(
        find.descendant(of: locationsSection, matching: find.text('Damascus')),
        findsOneWidget,
      );
      expect(find.text('Aleppo'), findsOneWidget);
    });
  });

  group('Form validation', () {
    testWidgets('Empty submission shows required validation and attempts no '
        'email launch', (tester) async {
      final client = FakeUrlLauncherClient(webResult: true);
      await pumpContactUs(tester, emailLauncher: EmailLauncher(client: client));

      await tester.ensureVisible(
        find.byKey(const ValueKey('contact-send-email-button')),
      );
      await tester.tap(find.byKey(const ValueKey('contact-send-email-button')));
      await tester.pumpAndSettle();

      expect(find.text('Please enter your full name.'), findsOneWidget);
      expect(find.text('Please enter your work email.'), findsOneWidget);
      expect(find.text('Please select a subject.'), findsOneWidget);
      expect(find.text('Please enter a message.'), findsOneWidget);
      expect(client.attemptedUris, isEmpty);
    });

    testWidgets('Invalid email shows email validation', (tester) async {
      await pumpContactUs(tester);

      await tester.enterText(
        find.byKey(const ValueKey('contact-full-name-field')),
        'Jane Weaver',
      );
      await tester.enterText(
        find.byKey(const ValueKey('contact-work-email-field')),
        'not-an-email',
      );
      await tester.enterText(
        find.byKey(const ValueKey('contact-message-field')),
        'Hello there',
      );

      await tester.ensureVisible(
        find.byKey(const ValueKey('contact-send-email-button')),
      );
      await tester.tap(find.byKey(const ValueKey('contact-send-email-button')));
      await tester.pumpAndSettle();

      expect(find.text('Please enter a valid email address.'), findsOneWidget);
    });
  });

  group('Subject selection', () {
    testWidgets('Selecting a subject updates the displayed value', (
      tester,
    ) async {
      await pumpContactUs(tester);

      expect(find.text('Select a subject'), findsOneWidget);

      await tester.ensureVisible(
        find.byKey(const ValueKey('contact-subject-field')),
      );
      await tester.tap(find.byKey(const ValueKey('contact-subject-field')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Invoice or Payment').last);
      await tester.pumpAndSettle();

      expect(find.text('Invoice or Payment'), findsOneWidget);
    });
  });

  group('Subject dropdown source of truth', () {
    testWidgets('Every subject defined by ContactSubject.values appears in '
        'the dropdown, in the same order', (tester) async {
      await pumpContactUs(tester);

      await tester.ensureVisible(
        find.byKey(const ValueKey('contact-subject-field')),
      );
      await tester.tap(find.byKey(const ValueKey('contact-subject-field')));
      await tester.pumpAndSettle();

      final labelContext = tester.element(find.byType(ContactUsScreen));
      final labels = [
        for (final s in ContactSubject.values) s.localizedLabel(labelContext),
      ];
      final positions = <double>[];
      for (final label in labels) {
        final finder = find.text(label);
        expect(finder, findsOneWidget, reason: 'Missing subject: $label');
        positions.add(tester.getTopLeft(finder).dy);
      }

      for (var i = 0; i < positions.length - 1; i++) {
        expect(
          positions[i],
          lessThan(positions[i + 1]),
          reason: 'Expected "${labels[i]}" to appear above "${labels[i + 1]}"',
        );
      }
    });

    for (final subject in ContactSubject.values) {
      testWidgets(
        'Selecting ContactSubject.${subject.name} sends it as the mailto '
        'subject',
        (tester) async {
          final client = FakeUrlLauncherClient(webResult: true);
          await pumpContactUs(
            tester,
            emailLauncher: EmailLauncher(client: client),
          );

          final subjectContext = tester.element(find.byType(ContactUsScreen));
          await fillValidForm(
            tester,
            subjectLabel: subject.localizedLabel(subjectContext),
          );
          await tester.ensureVisible(
            find.byKey(const ValueKey('contact-send-email-button')),
          );
          await tester.tap(
            find.byKey(const ValueKey('contact-send-email-button')),
          );
          await tester.pumpAndSettle();

          expect(client.attemptedUris, hasLength(1));
          expect(
            client.attemptedUris.single.queryParameters['subject'],
            subject.localizedLabel(subjectContext),
          );
        },
      );
    }
  });

  group('Valid submission opens the email app (mailto)', () {
    testWidgets(
      'Sends a mailto to the current region addressed with trimmed name, '
      'email, and message in the body',
      (tester) async {
        final client = FakeUrlLauncherClient(webResult: true);
        final lebanon = region(SupportRegionId.lebanon);
        await pumpContactUs(
          tester,
          region: lebanon,
          emailLauncher: EmailLauncher(client: client),
        );

        await tester.enterText(
          find.byKey(const ValueKey('contact-full-name-field')),
          '  Jane Weaver  ',
        );
        await tester.enterText(
          find.byKey(const ValueKey('contact-work-email-field')),
          '  jane@textile.co  ',
        );
        await tester.ensureVisible(
          find.byKey(const ValueKey('contact-subject-field')),
        );
        await tester.tap(find.byKey(const ValueKey('contact-subject-field')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Technical Support').last);
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('contact-message-field')),
          '  We need help scheduling a shipment.  ',
        );

        await tester.ensureVisible(
          find.byKey(const ValueKey('contact-send-email-button')),
        );
        await tester.tap(
          find.byKey(const ValueKey('contact-send-email-button')),
        );
        await tester.pumpAndSettle();

        expect(client.attemptedUris, hasLength(1));
        final uri = client.attemptedUris.single;
        expect(uri.path, lebanon.supportEmail);
        expect(uri.queryParameters['subject'], 'Technical Support');
        final body = uri.queryParameters['body']!;
        expect(body, contains('Jane Weaver'));
        expect(body, contains('jane@textile.co'));
        expect(body, contains('We need help scheduling a shipment.'));
      },
    );

    testWidgets('Shows a loading state while the email app launch is '
        'pending', (tester) async {
      final inFlight = Completer<bool>();
      final client = _ControlledUrlLauncherClient(inFlight.future);
      await pumpContactUs(tester, emailLauncher: EmailLauncher(client: client));
      await fillValidForm(tester);

      await tester.ensureVisible(
        find.byKey(const ValueKey('contact-send-email-button')),
      );
      await tester.tap(find.byKey(const ValueKey('contact-send-email-button')));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      inFlight.complete(true);
      await tester.pumpAndSettle();

      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('Rapid repeated taps only trigger a single launch attempt', (
      tester,
    ) async {
      final inFlight = Completer<bool>();
      final client = _ControlledUrlLauncherClient(inFlight.future);
      await pumpContactUs(tester, emailLauncher: EmailLauncher(client: client));
      await fillValidForm(tester);

      final button = find.byKey(const ValueKey('contact-send-email-button'));
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.tap(button);
      await tester.tap(button);

      expect(client.attemptedUris, hasLength(1));

      inFlight.complete(true);
      await tester.pumpAndSettle();

      expect(client.attemptedUris, hasLength(1));
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'A failed launch shows the approved error message and keeps form '
      'values available for retry',
      (tester) async {
        final client = FakeUrlLauncherClient(webResult: false);
        await pumpContactUs(
          tester,
          emailLauncher: EmailLauncher(client: client),
        );
        await fillValidForm(tester);

        await tester.ensureVisible(
          find.byKey(const ValueKey('contact-send-email-button')),
        );
        await tester.tap(
          find.byKey(const ValueKey('contact-send-email-button')),
        );
        await tester.pumpAndSettle();

        expect(
          find.text("Couldn't open your email app. Please try again."),
          findsOneWidget,
        );
        expect(
          fieldText(tester, const ValueKey('contact-full-name-field')),
          'Jane Weaver',
        );
        expect(
          fieldText(tester, const ValueKey('contact-work-email-field')),
          'jane@textile.co',
        );
        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('A thrown exception does not crash the screen and shows the '
        'approved error message', (tester) async {
      final client = FakeUrlLauncherClient(
        webResult: Exception('email app unreachable'),
      );
      await pumpContactUs(tester, emailLauncher: EmailLauncher(client: client));
      await fillValidForm(tester);

      await tester.ensureVisible(
        find.byKey(const ValueKey('contact-send-email-button')),
      );
      await tester.tap(find.byKey(const ValueKey('contact-send-email-button')));
      await tester.pumpAndSettle();

      expect(
        find.text("Couldn't open your email app. Please try again."),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('The user can retry successfully after a failure', (
      tester,
    ) async {
      final client = _MutableUrlLauncherClient(result: false);
      await pumpContactUs(tester, emailLauncher: EmailLauncher(client: client));
      await fillValidForm(tester);

      final button = find.byKey(const ValueKey('contact-send-email-button'));
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(
        find.text("Couldn't open your email app. Please try again."),
        findsOneWidget,
      );

      client.result = true;
      await tester.tap(button);
      await tester.pumpAndSettle();

      expect(client.attemptedUris, hasLength(2));
      expect(tester.takeException(), isNull);
    });
  });

  group('Profile prefill', () {
    testWidgets('Prefills name and email when initial values are supplied', (
      tester,
    ) async {
      await pumpContactUs(
        tester,
        initialName: 'Jane Weaver',
        initialEmail: 'jane@textile.co',
      );

      expect(
        fieldText(tester, const ValueKey('contact-full-name-field')),
        'Jane Weaver',
      );
      expect(
        fieldText(tester, const ValueKey('contact-work-email-field')),
        'jane@textile.co',
      );
    });

    testWidgets('Prefilled fields remain editable', (tester) async {
      await pumpContactUs(tester, initialName: 'Jane Weaver');

      await tester.enterText(
        find.byKey(const ValueKey('contact-full-name-field')),
        'Jane Edited',
      );
      await tester.pump();

      expect(
        fieldText(tester, const ValueKey('contact-full-name-field')),
        'Jane Edited',
      );
    });

    testWidgets(
      "A rebuild with the same initial value does not reset a user's edit",
      (tester) async {
        final rebuildTrigger = ValueNotifier<int>(0);
        await tester.pumpWidget(
          MaterialApp(
            supportedLocales: const [Locale('en'), Locale('ar'), Locale('fr')],
            localizationsDelegates: const [
              AppTranslationsDelegate(),
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: AnimatedBuilder(
              animation: rebuildTrigger,
              builder: (context, _) =>
                  const ContactUsScreen(initialName: 'Jane Weaver'),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const ValueKey('contact-full-name-field')),
          'Jane Edited',
        );
        await tester.pump();

        rebuildTrigger.value++;
        await tester.pumpAndSettle();

        expect(
          fieldText(tester, const ValueKey('contact-full-name-field')),
          'Jane Edited',
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'Late-arriving profile data does not overwrite a field the user has '
      'already edited',
      (tester) async {
        final initialName = ValueNotifier<String?>(null);
        await tester.pumpWidget(
          MaterialApp(
            supportedLocales: const [Locale('en'), Locale('ar'), Locale('fr')],
            localizationsDelegates: const [
              AppTranslationsDelegate(),
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: ValueListenableBuilder<String?>(
              valueListenable: initialName,
              builder: (context, value, _) =>
                  ContactUsScreen(initialName: value),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const ValueKey('contact-full-name-field')),
          'Customer Typed Name',
        );
        await tester.pump();

        initialName.value = 'Jane Weaver';
        await tester.pumpAndSettle();

        expect(
          fieldText(tester, const ValueKey('contact-full-name-field')),
          'Customer Typed Name',
        );
      },
    );

    testWidgets(
      'Late-arriving profile data fills a still-empty, untouched field',
      (tester) async {
        final initialName = ValueNotifier<String?>(null);
        await tester.pumpWidget(
          MaterialApp(
            supportedLocales: const [Locale('en'), Locale('ar'), Locale('fr')],
            localizationsDelegates: const [
              AppTranslationsDelegate(),
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: ValueListenableBuilder<String?>(
              valueListenable: initialName,
              builder: (context, value, _) =>
                  ContactUsScreen(initialName: value),
            ),
          ),
        );
        await tester.pumpAndSettle();

        initialName.value = 'Jane Weaver';
        await tester.pumpAndSettle();

        expect(
          fieldText(tester, const ValueKey('contact-full-name-field')),
          'Jane Weaver',
        );
      },
    );

    testWidgets('With no profile data, fields remain empty and usable', (
      tester,
    ) async {
      await pumpContactUs(tester);

      expect(fieldText(tester, const ValueKey('contact-full-name-field')), '');
      await tester.enterText(
        find.byKey(const ValueKey('contact-full-name-field')),
        'Someone Else',
      );
      await tester.pump();
      expect(
        fieldText(tester, const ValueKey('contact-full-name-field')),
        'Someone Else',
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('Responsive coverage', () {
    const sizes = [
      Size(320, 568),
      Size(375, 667),
      Size(768, 1024),
      Size(844, 390),
    ];

    for (final size in sizes) {
      testWidgets(
        'No overflow at ${size.width.toInt()}x${size.height.toInt()}',
        (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);

          await pumpContactUs(tester);
          expect(tester.takeException(), isNull);
        },
      );
    }

    testWidgets(
      'No overflow at a narrow width with Syria selected (largest content: '
      'the Regional Contacts section)',
      (tester) async {
        tester.view.physicalSize = const Size(320, 568);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await pumpContactUs(tester, region: region(SupportRegionId.syria));
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('No overflow at 1.5x system text scale', (tester) async {
      tester.view.physicalSize = const Size(375, 667);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.platformDispatcher.textScaleFactorTestValue = 1.5;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await pumpContactUs(tester);
      expect(tester.takeException(), isNull);
    });
  });

  group('Keyboard safety', () {
    testWidgets(
      'Message body remains reachable when the keyboard opens on a small '
      'screen',
      (tester) async {
        tester.view.physicalSize = const Size(320, 568);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await pumpContactUs(tester);

        await tester.ensureVisible(
          find.byKey(const ValueKey('contact-message-field')),
        );
        await tester.tap(find.byKey(const ValueKey('contact-message-field')));
        await tester.pumpAndSettle();

        tester.view.viewInsets = const FakeViewPadding(bottom: 300);
        addTearDown(() => tester.view.resetViewInsets());
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('contact-message-field')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('contact-send-email-button')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('Localization and RTL', () {
    testWidgets('Arabic: screen renders with RTL layout and shows Arabic '
        'contact info, including Syria regional contact data', (tester) async {
      await pumpContactUs(
        tester,
        region: region(SupportRegionId.syria),
        locale: const Locale('ar'),
      );

      expect(find.text('تواصل معنا'), findsWidgets);
      final context = tester.element(find.byType(ContactUsScreen));
      expect(Directionality.of(context), TextDirection.rtl);

      final syria = region(SupportRegionId.syria);
      expect(find.text(syria.supportEmail!), findsOneWidget);
      final ezz = syria.regionalContacts.firstWhere((c) => c.name == 'عز');
      expect(find.text(ezz.availability!), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('French: labels are localized', (tester) async {
      await pumpContactUs(tester, locale: const Locale('fr'));

      expect(find.text('Contactez-nous'), findsWidgets);
      final context = tester.element(find.byType(ContactUsScreen));
      expect(Directionality.of(context), TextDirection.ltr);
      expect(tester.takeException(), isNull);
    });

    // The country name itself is only ever rendered by the region selector
    // pills, which the screen hides whenever a region is supplied directly
    // (the hand-off flow from Support) — see _showRegionSelector. So
    // country-name translation is verified here via the selector, and
    // city/address/area/availability translation is verified separately
    // below via a directly-supplied region (which is how Support hands off
    // to Contact Us in production).
    group('Region selector: country name switches language', () {
      testWidgets('English, Arabic, and French pills', (tester) async {
        await pumpContactUs(tester, locale: const Locale('en'));
        for (final name in ['UAE', 'Syria', 'Iraq', 'Oman', 'Lebanon']) {
          expect(find.text(name), findsOneWidget);
        }

        await pumpContactUs(tester, locale: const Locale('ar'));
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

        await pumpContactUs(tester, locale: const Locale('fr'));
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
        // (Oman happens to be spelled the same in EN/FR, so it's excluded
        // from this negative check).
        for (final name in ['UAE', 'Syria', 'Iraq', 'Lebanon']) {
          expect(find.text(name), findsNothing);
        }
        expect(tester.takeException(), isNull);
      });

      testWidgets('Lebanon and UAE specifically: English shows "Lebanon", '
          'Arabic shows "لبنان" (never "Lebanon"), French shows "Liban" '
          '(never "Lebanon")', (tester) async {
        await pumpContactUs(tester, locale: const Locale('en'));
        expect(find.text('Lebanon'), findsOneWidget);

        await pumpContactUs(tester, locale: const Locale('ar'));
        expect(find.text('لبنان'), findsOneWidget);
        expect(find.text('Lebanon'), findsNothing);
        expect(find.text('الإمارات العربية المتحدة'), findsOneWidget);

        await pumpContactUs(tester, locale: const Locale('fr'));
        expect(find.text('Liban'), findsOneWidget);
        expect(find.text('Lebanon'), findsNothing);
        expect(find.text('Émirats arabes unis'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('Live language switch EN -> AR -> FR -> EN updates the '
          'region selector without navigating away or remounting the '
          'screen', (tester) async {
        final hostKey = GlobalKey<_LocaleHostState>();
        await tester.pumpWidget(
          _LocaleHost(key: hostKey, child: const ContactUsScreen()),
        );
        await tester.pumpAndSettle();

        expect(find.text('Lebanon'), findsOneWidget);
        expect(find.text('لبنان'), findsNothing);
        expect(
          Directionality.of(tester.element(find.byType(ContactUsScreen))),
          TextDirection.ltr,
        );

        hostKey.currentState!.setLocale(const Locale('ar'));
        await tester.pumpAndSettle();
        expect(find.text('لبنان'), findsOneWidget);
        expect(find.text('Lebanon'), findsNothing);
        expect(
          Directionality.of(tester.element(find.byType(ContactUsScreen))),
          TextDirection.rtl,
        );

        hostKey.currentState!.setLocale(const Locale('fr'));
        await tester.pumpAndSettle();
        expect(find.text('Liban'), findsOneWidget);
        expect(find.text('لبنان'), findsNothing);
        expect(
          Directionality.of(tester.element(find.byType(ContactUsScreen))),
          TextDirection.ltr,
        );

        hostKey.currentState!.setLocale(const Locale('en'));
        await tester.pumpAndSettle();
        expect(find.text('Lebanon'), findsOneWidget);
        expect(find.text('Liban'), findsNothing);
        expect(tester.takeException(), isNull);
      });
    });

    testWidgets('Arabic: phone numbers and the email address stay '
        'LTR-readable even while the rest of the screen is RTL', (
      tester,
    ) async {
      final lebanon = region(SupportRegionId.lebanon);
      await pumpContactUs(tester, region: lebanon, locale: const Locale('ar'));

      final screenContext = tester.element(find.byType(ContactUsScreen));
      expect(Directionality.of(screenContext), TextDirection.rtl);

      final emailContext = tester.element(find.text(lebanon.supportEmail!));
      expect(Directionality.of(emailContext), TextDirection.ltr);

      for (final number in lebanon.hotlineNumbers) {
        final numberContext = tester.element(find.text(number));
        expect(Directionality.of(numberContext), TextDirection.ltr);
      }
      expect(tester.takeException(), isNull);
    });

    group('Lebanon: city/address switch language, phone/email do not', () {
      testWidgets('English', (tester) async {
        final lebanon = region(SupportRegionId.lebanon);
        await pumpContactUs(
          tester,
          region: lebanon,
          locale: const Locale('en'),
        );

        expect(find.text('LOCATIONS'), findsOneWidget);
        expect(find.text('Beirut'), findsOneWidget);
        expect(find.text(_lebanonBeirutAddressEn), findsOneWidget);
        expect(find.text(_lebanonOfficeAddressEn), findsOneWidget);
        expect(find.text(lebanon.supportEmail!), findsOneWidget);
        for (final number in lebanon.hotlineNumbers) {
          expect(find.text(number), findsOneWidget);
        }
        expect(tester.takeException(), isNull);
      });

      testWidgets('Arabic', (tester) async {
        final lebanon = region(SupportRegionId.lebanon);
        await pumpContactUs(
          tester,
          region: lebanon,
          locale: const Locale('ar'),
        );

        expect(find.text('بيروت'), findsOneWidget);
        expect(find.text('بجانب السفارة الكويتية'), findsOneWidget);
        expect(find.text('طريق المطار - شركة النجار'), findsOneWidget);
        // Phone/email are never translated.
        expect(find.text(lebanon.supportEmail!), findsOneWidget);
        for (final number in lebanon.hotlineNumbers) {
          expect(find.text(number), findsOneWidget);
        }
        expect(tester.takeException(), isNull);
      });

      testWidgets('French', (tester) async {
        final lebanon = region(SupportRegionId.lebanon);
        await pumpContactUs(
          tester,
          region: lebanon,
          locale: const Locale('fr'),
        );

        expect(find.text('Beyrouth'), findsOneWidget);
        expect(find.text("À côté de l'ambassade du Koweït"), findsOneWidget);
        expect(
          find.text("Route de l'aéroport - ANC Najjar Fabric"),
          findsOneWidget,
        );
        expect(find.text(lebanon.supportEmail!), findsOneWidget);
        for (final number in lebanon.hotlineNumbers) {
          expect(find.text(number), findsOneWidget);
        }
        expect(tester.takeException(), isNull);
      });
    });

    testWidgets('UAE (non-Lebanon) in Arabic: city and confirmed address '
        'switch language; email/phone stay as-is', (tester) async {
      final uae = region(SupportRegionId.uae);
      await pumpContactUs(tester, region: uae, locale: const Locale('ar'));

      expect(find.text('الشارقة'), findsOneWidget);
      expect(find.text('المدينة الصناعية، منطقة 18'), findsOneWidget);
      expect(find.text('ANC Najjar Fabric'), findsOneWidget);
      expect(find.text(uae.supportEmail!), findsOneWidget);
      expect(find.text(uae.hotlineNumbers.single), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Syria (non-Lebanon) in French: city, confirmed Damascus '
        'address, regional area, and availability all switch language; the '
        'still-unconfirmed Aleppo address does not', (tester) async {
      final syria = region(SupportRegionId.syria);
      await pumpContactUs(tester, region: syria, locale: const Locale('fr'));

      // Scoped to the Locations section: the city "Damas" (Damascus) and
      // حلا's Curtains area (also "دمشق") translate to the same French
      // word, so an unscoped lookup would be ambiguous.
      final locationsSection = find.byKey(
        const ValueKey('contact-locations-section'),
      );
      expect(
        find.descendant(of: locationsSection, matching: find.text('Damas')),
        findsOneWidget,
      );
      expect(
        find.text(
          "Route de l'aéroport international de Damas, ANC Najjar Fabric",
        ),
        findsOneWidget,
      );
      expect(find.text('Alep'), findsOneWidget);
      // Aleppo's address wording isn't confirmed yet, so it stays as the
      // original stored Arabic literal even in French.
      final aleppo = syria.officeLocations.firstWhere(
        (l) => l.city == 'Aleppo',
      );
      expect(find.text(aleppo.address), findsOneWidget);

      // روى (Idlib)'s area is translated.
      expect(find.text('Idlib'), findsOneWidget);
      // عز's availability window is translated.
      expect(find.text('De 18h00 à 21h00'), findsOneWidget);
      // Category grouping labels are translated too.
      expect(find.text("Tissus d'ameublement"), findsOneWidget);
      expect(find.text('Rideaux'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Syria in Arabic: regional area and availability render '
        'their (unchanged) Arabic wording, category labels are localized', (
      tester,
    ) async {
      final syria = region(SupportRegionId.syria);
      await pumpContactUs(tester, region: syria, locale: const Locale('ar'));

      final rawiaIdlib = syria.regionalContacts.firstWhere(
        (c) => c.name == 'روى' && c.area == 'إدلب',
      );
      expect(find.text(rawiaIdlib.area), findsWidgets);
      final ezz = syria.regionalContacts.firstWhere((c) => c.name == 'عز');
      expect(find.text(ezz.availability!), findsOneWidget);
      expect(find.text('أقمشة التنجيد'), findsOneWidget);
      expect(find.text('الستائر'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}

/// Hosts [child] under a [MaterialApp] whose `locale` can be switched live
/// via [_LocaleHostState.setLocale], without ever calling `pumpWidget`
/// again — unlike `pumpContactUs(..., locale: ...)`, which tears down and
/// rebuilds the whole tree on every call. This is the only way to catch a
/// region label that resolves correctly on first build but fails to update
/// when the app's language is switched mid-session (the real app's actual
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

/// Fake [UrlLauncherClient] with a mutable outcome, used by the retry test
/// where the same client instance must fail once and then succeed.
class _MutableUrlLauncherClient implements UrlLauncherClient {
  _MutableUrlLauncherClient({required this.result});

  bool result;
  final List<Uri> attemptedUris = [];

  @override
  Future<bool> launch(Uri uri) async {
    attemptedUris.add(uri);
    return result;
  }
}

/// Fake [UrlLauncherClient] whose launch stays pending until [result]
/// completes, used to observe the launch-in-progress guard and loading
/// state while a launch attempt is still in flight.
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
