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
  });

  group('Oman', () {
    test('has verified email and phone, no office/regional contacts', () {
      final oman = region(SupportRegionId.oman);

      expect(oman.supportEmail, 'mhd.oman@anc-uae.com');
      expect(oman.hotlineNumbers, ['+968 9819 8501']);
      expect(oman.officeAddress, isNull);
      expect(oman.regionalContacts, isEmpty);
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
