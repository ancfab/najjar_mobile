// Unit tests for the verified per-region Contact Us / Support data in
// kSupportRegions, and the SupportRegionalContact model it's built from.
// These are pure data checks: no widget pumping needed, so a future edit
// that accidentally invents or drops a verified contact field fails fast
// here.

import 'package:flutter_test/flutter_test.dart';

import 'package:anc_fabrics/data/support_regions_data.dart';
import 'package:anc_fabrics/models/support_region.dart';

void main() {
  SupportRegionData region(SupportRegionId id) =>
      kSupportRegions.firstWhere((r) => r.id == id);

  group('SupportRegionalContact', () {
    test('stores the required fields and defaults phone/availability to '
        'null', () {
      const contact = SupportRegionalContact(
        name: 'روى',
        category: SupportContactCategory.upholsteryFabrics,
        area: 'درعا - السويداء',
      );

      expect(contact.name, 'روى');
      expect(contact.category, SupportContactCategory.upholsteryFabrics);
      expect(contact.area, 'درعا - السويداء');
      expect(contact.phone, isNull);
      expect(contact.availability, isNull);
    });
  });

  group('SupportOfficeLocation', () {
    test('stores the required fields and defaults name/phone to null', () {
      const location = SupportOfficeLocation(
        city: 'Beirut',
        address: 'جنب السفارة الكويتية',
      );

      expect(location.city, 'Beirut');
      expect(location.address, 'جنب السفارة الكويتية');
      expect(location.name, isNull);
      expect(location.phone, isNull);
    });
  });

  group('Lebanon', () {
    test('has verified email, office, and three verified phone numbers; no '
        'regional contacts', () {
      final lebanon = region(SupportRegionId.lebanon);

      expect(lebanon.supportEmail, 'info@najjar-lb.com');
      expect(lebanon.officeAddress, 'طريق المطار - شركة النجار');
      expect(lebanon.hotlineNumbers, [
        '+961 79 303 551',
        '+961 81 107 942',
        '+961 76 408 455',
      ]);
      expect(lebanon.regionalContacts, isEmpty);
    });

    test('has exactly one verified office location: Beirut, with the '
        'newly supplied address (not the older Airport Road address used '
        'by the single-address officeAddress field)', () {
      final lebanon = region(SupportRegionId.lebanon);

      expect(lebanon.officeLocations, hasLength(1));
      final beirut = lebanon.officeLocations.single;
      expect(beirut.city, 'Beirut');
      expect(beirut.address, 'جنب السفارة الكويتية');
      expect(beirut.name, isNull);
      expect(beirut.phone, isNull);
    });

    test('the phone numbers are not labeled as WhatsApp: no verified '
        'WhatsApp number exists for Lebanon', () {
      final lebanon = region(SupportRegionId.lebanon);

      expect(lebanon.whatsappNumber, isNull);
    });

    test('has no verified support-hours schedule', () {
      final lebanon = region(SupportRegionId.lebanon);

      expect(lebanon.supportHours, isNull);
    });
  });

  group('UAE', () {
    test('has verified email and phone, no office/regional contacts', () {
      final uae = region(SupportRegionId.uae);

      expect(uae.supportEmail, 'accounting01@anc-uae.com');
      expect(uae.hotlineNumbers, ['+971 56 511 0448']);
      expect(uae.officeAddress, isNull);
      expect(uae.regionalContacts, isEmpty);
    });

    test('has exactly one verified office location: Sharjah, with the '
        'ANC Najjar Fabric business name', () {
      final uae = region(SupportRegionId.uae);

      expect(uae.officeLocations, hasLength(1));
      final sharjah = uae.officeLocations.single;
      expect(sharjah.city, 'Sharjah');
      expect(sharjah.address, 'المدينة الصناعية، منطقة 18');
      expect(sharjah.name, 'ANC Najjar Fabric');
      expect(sharjah.phone, isNull);
    });
  });

  group('Oman', () {
    test('has verified email and phone, no office/regional contacts', () {
      final oman = region(SupportRegionId.oman);

      expect(oman.supportEmail, 'mhd.oman@anc-uae.com');
      expect(oman.hotlineNumbers, ['+968 9819 8501']);
      expect(oman.officeAddress, isNull);
      expect(oman.regionalContacts, isEmpty);
    });

    test('has exactly one verified office location: Muscat / Seeb', () {
      final oman = region(SupportRegionId.oman);

      expect(oman.officeLocations, hasLength(1));
      final muscat = oman.officeLocations.single;
      expect(muscat.city, 'Muscat / Seeb');
      expect(muscat.address, 'مسقط - السيب، شركة النجار للأعمال العالمية');
      expect(muscat.name, isNull);
      expect(muscat.phone, isNull);
    });
  });

  group('Iraq', () {
    test('has only a verified email; no office, hotline, or regional '
        'contacts', () {
      final iraq = region(SupportRegionId.iraq);

      expect(iraq.supportEmail, 'accounting@najjar-lb.com');
      expect(iraq.officeAddress, isNull);
      expect(iraq.hotlineNumbers, isEmpty);
      expect(iraq.regionalContacts, isEmpty);
    });

    test('has exactly two verified office locations, each with its own '
        'verified phone number: Erbil and Sulaymaniyah', () {
      final iraq = region(SupportRegionId.iraq);

      expect(iraq.officeLocations, hasLength(2));
      final erbil = iraq.officeLocations.firstWhere((l) => l.city == 'Erbil');
      final sulaymaniyah = iraq.officeLocations.firstWhere(
        (l) => l.city == 'Sulaymaniyah',
      );

      expect(erbil.address, 'شارع 60، جانب جليل خياط');
      expect(erbil.phone, '+964 751 401 8777');
      expect(erbil.name, isNull);

      expect(sulaymaniyah.address, 'شارع 60، جانب مستشفى بخشين');
      expect(sulaymaniyah.phone, '+964 750 166 1000');
      expect(sulaymaniyah.name, isNull);
    });
  });

  group('Syria', () {
    late SupportRegionData syria;

    setUp(() {
      syria = region(SupportRegionId.syria);
    });

    test('has a verified email and no direct office/hotline of its own', () {
      expect(syria.supportEmail, 'info@anc-syr.com');
      expect(syria.officeAddress, isNull);
      expect(syria.hotlineNumbers, isEmpty);
    });

    test('has exactly two verified office locations: Damascus and Aleppo, '
        'neither with a verified phone or business name', () {
      expect(syria.officeLocations, hasLength(2));
      final damascus = syria.officeLocations.firstWhere(
        (l) => l.city == 'Damascus',
      );
      final aleppo = syria.officeLocations.firstWhere(
        (l) => l.city == 'Aleppo',
      );

      expect(damascus.address, 'طريق المطار دمشق الدولي، شركة النجار');
      expect(damascus.phone, isNull);
      expect(damascus.name, isNull);

      expect(aleppo.address, 'استراد دمشق');
      expect(aleppo.phone, isNull);
      expect(aleppo.name, isNull);
    });

    test('has exactly 9 regional contacts: 7 upholstery, 2 curtains', () {
      final upholstery = syria.regionalContacts
          .where((c) => c.category == SupportContactCategory.upholsteryFabrics)
          .toList();
      final curtains = syria.regionalContacts
          .where((c) => c.category == SupportContactCategory.curtains)
          .toList();

      expect(syria.regionalContacts, hasLength(9));
      expect(upholstery, hasLength(7));
      expect(curtains, hasLength(2));
    });

    test('روى (Idlib) has the verified phone number', () {
      final match = syria.regionalContacts.firstWhere(
        (c) => c.name == 'روى' && c.area == 'إدلب',
      );
      expect(match.phone, '0989433377');
      expect(match.category, SupportContactCategory.upholsteryFabrics);
    });

    test('عز has no phone of its own but has a verified availability '
        'window (uses the numbers already listed above)', () {
      final ezz = syria.regionalContacts.firstWhere((c) => c.name == 'عز');

      expect(ezz.phone, isNull);
      expect(ezz.availability, 'من الساعة 6 مساءً وحتى الساعة 9 مساءً');
      expect(ezz.area, 'جميع المحافظات');
    });

    test('حلا appears twice under Curtains with distinct areas/numbers', () {
      final hala = syria.regionalContacts
          .where((c) => c.name == 'حلا')
          .toList();

      expect(hala, hasLength(2));
      expect(
        hala.every((c) => c.category == SupportContactCategory.curtains),
        isTrue,
      );
      expect(hala.map((c) => c.area), containsAll(['دمشق', 'جميع المحافظات']));
      expect(
        hala.map((c) => c.phone),
        containsAll(['0989443381', '0989443382']),
      );
    });
  });

  test('no region has an invented WhatsApp number or support-hours '
      'schedule', () {
    for (final region in kSupportRegions) {
      expect(
        region.whatsappNumber,
        isNull,
        reason: '${region.displayName} has no verified WhatsApp number',
      );
      expect(
        region.supportHours,
        isNull,
        reason:
            '${region.displayName} has no verified support-hours '
            'schedule',
      );
    }
  });
}
