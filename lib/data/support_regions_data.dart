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
        address: 'المدينة الصناعية، منطقة 18',
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
        address: 'طريق المطار دمشق الدولي، شركة النجار',
      ),
      SupportOfficeLocation(city: 'Aleppo', address: 'استراد دمشق'),
    ],
    regionalContacts: [
      SupportRegionalContact(
        name: 'روى',
        category: SupportContactCategory.upholsteryFabrics,
        area: 'درعا - السويداء',
        phone: '0989204480',
      ),
      SupportRegionalContact(
        name: 'روى',
        category: SupportContactCategory.upholsteryFabrics,
        area: 'إدلب',
        phone: '0989433377',
      ),
      SupportRegionalContact(
        name: 'نور',
        category: SupportContactCategory.upholsteryFabrics,
        area: 'مركز المدينة وغوطة غربية',
        phone: '0993180888',
      ),
      SupportRegionalContact(
        name: 'ندى',
        category: SupportContactCategory.upholsteryFabrics,
        area: 'غوطة شرقية',
        phone: '0994180888',
      ),
      SupportRegionalContact(
        name: 'نجوان',
        category: SupportContactCategory.upholsteryFabrics,
        area: 'حمص - حماة',
        phone: '0989204492',
      ),
      SupportRegionalContact(
        name: 'دلع',
        category: SupportContactCategory.upholsteryFabrics,
        area: 'الساحل',
        phone: '0989204491',
      ),
      SupportRegionalContact(
        name: 'عز',
        category: SupportContactCategory.upholsteryFabrics,
        area: 'جميع المحافظات',
        availability: 'من الساعة 6 مساءً وحتى الساعة 9 مساءً',
      ),
      SupportRegionalContact(
        name: 'حلا',
        category: SupportContactCategory.curtains,
        area: 'دمشق',
        phone: '0989443381',
      ),
      SupportRegionalContact(
        name: 'حلا',
        category: SupportContactCategory.curtains,
        area: 'جميع المحافظات',
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
        address: 'شارع 60، جانب جليل خياط',
        phone: '+964 751 401 8777',
      ),
      SupportOfficeLocation(
        city: 'Sulaymaniyah',
        address: 'شارع 60، جانب مستشفى بخشين',
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
        address: 'مسقط - السيب، شركة النجار للأعمال العالمية',
      ),
    ],
  ),
  SupportRegionData(
    id: SupportRegionId.lebanon,
    displayName: 'Lebanon',
    supportEmail: 'info@najjar-lb.com',
    officeAddress: 'طريق المطار - شركة النجار',
    hotlineNumbers: ['+961 79 303 551', '+961 81 107 942', '+961 76 408 455'],
    officeLocations: [
      SupportOfficeLocation(city: 'Beirut', address: 'جنب السفارة الكويتية'),
    ],
  ),
];
