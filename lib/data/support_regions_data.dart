import '../models/support_region.dart';

// Verified contact details per region. Fields left unset (whatsappNumber,
// supportHours, and any officeAddress/hotlineNumbers not listed below) have
// no confirmed production value yet — leave them null/empty rather than
// filling them with a placeholder-looking value. The Support and Contact Us
// screens both treat an unset field as "omit", never as "not yet
// available" invented copy.
const List<SupportRegionData> kSupportRegions = [
  SupportRegionData(
    id: SupportRegionId.uae,
    displayName: 'UAE',
    supportEmail: 'accounting01@anc-uae.com',
    hotlineNumbers: ['+971 56 511 0448'],
    officeLocations: [
      SupportOfficeLocation(
        city: 'Sharjah',
        cityIds: [SupportCityId.sharjah],
        address: 'المدينة الصناعية، منطقة 18',
        addressKey: 'supportAddress.uaeSharjah',
        name: 'ANC Najjar Fabric',
      ),
    ],
  ),
  SupportRegionData(
    id: SupportRegionId.syria,
    displayName: 'Syria',
    supportEmail: 'info@anc-syr.com',
    officeLocations: [
      SupportOfficeLocation(
        city: 'Damascus',
        cityIds: [SupportCityId.damascus],
        address: 'طريق المطار دمشق الدولي، شركة النجار',
        addressKey: 'supportAddress.syriaDamascus',
      ),
      SupportOfficeLocation(
        city: 'Aleppo',
        cityIds: [SupportCityId.aleppo],
        address: 'استراد دمشق',
        // addressKey intentionally omitted: this address's wording is not
        // yet confirmed for translation — see the localization audit.
      ),
    ],
    regionalContacts: [
      SupportRegionalContact(
        name: 'روى',
        category: SupportContactCategory.upholsteryFabrics,
        area: 'درعا - السويداء',
        areaId: SupportAreaId.daraaSweida,
        phone: '0989204480',
      ),
      SupportRegionalContact(
        name: 'روى',
        category: SupportContactCategory.upholsteryFabrics,
        area: 'إدلب',
        areaId: SupportAreaId.idlib,
        phone: '0989433377',
      ),
      SupportRegionalContact(
        name: 'نور',
        category: SupportContactCategory.upholsteryFabrics,
        area: 'مركز المدينة وغوطة غربية',
        areaId: SupportAreaId.cityCenterWesternGhouta,
        phone: '0993180888',
      ),
      SupportRegionalContact(
        name: 'ندى',
        category: SupportContactCategory.upholsteryFabrics,
        area: 'غوطة شرقية',
        areaId: SupportAreaId.easternGhouta,
        phone: '0994180888',
      ),
      SupportRegionalContact(
        name: 'نجوان',
        category: SupportContactCategory.upholsteryFabrics,
        area: 'حمص - حماة',
        areaId: SupportAreaId.homsHama,
        phone: '0989204492',
      ),
      SupportRegionalContact(
        name: 'دلع',
        category: SupportContactCategory.upholsteryFabrics,
        area: 'الساحل',
        areaId: SupportAreaId.coast,
        phone: '0989204491',
      ),
      SupportRegionalContact(
        name: 'عز',
        category: SupportContactCategory.upholsteryFabrics,
        area: 'جميع المحافظات',
        areaId: SupportAreaId.allGovernorates,
        availability: 'من الساعة 6 مساءً وحتى الساعة 9 مساءً',
        availabilityKey: 'supportAvailability.sixPmToNinePm',
      ),
      SupportRegionalContact(
        name: 'حلا',
        category: SupportContactCategory.curtains,
        area: 'دمشق',
        areaId: SupportAreaId.damascus,
        phone: '0989443381',
      ),
      SupportRegionalContact(
        name: 'حلا',
        category: SupportContactCategory.curtains,
        area: 'جميع المحافظات',
        areaId: SupportAreaId.allGovernorates,
        phone: '0989443382',
      ),
    ],
  ),
  SupportRegionData(
    id: SupportRegionId.iraq,
    displayName: 'Iraq',
    supportEmail: 'accounting@najjar-lb.com',
    officeLocations: [
      SupportOfficeLocation(
        city: 'Erbil',
        cityIds: [SupportCityId.erbil],
        address: 'شارع 60، جانب جليل خياط',
        // addressKey intentionally omitted: this address's wording is not
        // yet confirmed for translation — see the localization audit.
        phone: '+964 751 401 8777',
      ),
      SupportOfficeLocation(
        city: 'Sulaymaniyah',
        cityIds: [SupportCityId.sulaymaniyah],
        address: 'شارع 60، جانب مستشفى بخشين',
        // addressKey intentionally omitted: this address's wording is not
        // yet confirmed for translation — see the localization audit.
        phone: '+964 750 166 1000',
      ),
    ],
  ),
  SupportRegionData(
    id: SupportRegionId.oman,
    displayName: 'Oman',
    supportEmail: 'mhd.oman@anc-uae.com',
    hotlineNumbers: ['+968 9819 8501'],
    officeLocations: [
      SupportOfficeLocation(
        city: 'Muscat / Seeb',
        cityIds: [SupportCityId.muscat, SupportCityId.seeb],
        address: 'مسقط - السيب، شركة النجار للأعمال العالمية',
        // addressKey intentionally omitted: this address's wording is not
        // yet confirmed for translation — see the localization audit.
      ),
    ],
  ),
  SupportRegionData(
    id: SupportRegionId.lebanon,
    displayName: 'Lebanon',
    supportEmail: 'info@najjar-lb.com',
    officeAddress: 'طريق المطار - شركة النجار',
    officeAddressKey: 'supportAddress.lebanonOffice',
    hotlineNumbers: ['+961 79 303 551', '+961 81 107 942', '+961 76 408 455'],
    officeLocations: [
      SupportOfficeLocation(
        city: 'Beirut',
        cityIds: [SupportCityId.beirut],
        address: 'جنب السفارة الكويتية',
        addressKey: 'supportAddress.lebanonBeirut',
      ),
    ],
  ),
];
