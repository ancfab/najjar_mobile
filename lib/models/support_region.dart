import 'package:flutter/widgets.dart';

import '../localization/translations.dart';

/// Static identifier for each region offered in the Support screen's region
/// selector.
enum SupportRegionId {
  uae,
  syria,
  iraq,
  oman,
  lebanon;

  /// Maps a login's ISO country code (e.g. `AuthSession.country` — `AE`,
  /// `IQ`, `SY`, `LB`, `OM`) to the matching Support region, so the Support
  /// screen can default its initial region selection to the authenticated
  /// user's login country without parsing a phone number.
  ///
  /// Returns `null` for a missing, empty, or unrecognized code (e.g. an
  /// older persisted session with no country) — callers must fall back to
  /// their own existing default in that case, never guess.
  static SupportRegionId? fromCountryIsoCode(String? isoCode) {
    switch (isoCode) {
      case 'AE':
        return SupportRegionId.uae;
      case 'SY':
        return SupportRegionId.syria;
      case 'IQ':
        return SupportRegionId.iraq;
      case 'OM':
        return SupportRegionId.oman;
      case 'LB':
        return SupportRegionId.lebanon;
      default:
        return null;
    }
  }

  /// Translation key for this region's localized country name (e.g.
  /// `supportRegion.uae`), matching the enum's own `name` 1:1 with the
  /// `supportRegion.*` keys in the translation JSON files.
  String get translationKey => 'supportRegion.$name';
}

/// Single centralized resolver for a region's user-facing country name,
/// mirroring the `ContactSubjectLabel.localizedLabel` pattern. Every screen
/// that shows a country name to the user (region selector pills, fallback
/// messages that interpolate the region name, etc.) must call this instead
/// of re-deriving the translation key inline or reading
/// [SupportRegionData.displayName] — [displayName] is English-only and
/// exists solely for internal/non-UI use (log messages, test fixture
/// identity, `orElse` fallbacks).
extension SupportRegionIdLabel on SupportRegionId {
  String localizedName(BuildContext context) => context.t(translationKey);
}

/// Which product line a [SupportRegionalContact] represents, used to group
/// Syria's regional representatives on the Contact Us screen.
enum SupportContactCategory { upholsteryFabrics, curtains }

/// Stable identifier for a verified office city, used to look up its
/// localized display name under the `supportCity.*` translation keys.
/// [SupportOfficeLocation.cityIds] is empty for a city that hasn't been
/// added here yet, in which case callers fall back to the raw
/// [SupportOfficeLocation.city] string.
enum SupportCityId {
  sharjah,
  damascus,
  aleppo,
  erbil,
  sulaymaniyah,
  muscat,
  seeb,
  beirut;

  String get translationKey => 'supportCity.$name';
}

/// Stable identifier for a Syria regional-contact's coverage area, used to
/// look up its localized display name under the `supportArea.*`
/// translation keys. Null on a [SupportRegionalContact] whose area text
/// hasn't been confirmed for translation yet, in which case callers fall
/// back to the raw [SupportRegionalContact.area] string.
enum SupportAreaId {
  daraaSweida,
  idlib,
  cityCenterWesternGhouta,
  easternGhouta,
  homsHama,
  coast,
  allGovernorates,
  damascus;

  String get translationKey => 'supportArea.$name';
}

/// A single named regional support representative for a region (currently
/// only populated for Syria), shown in the Contact Us screen's "Regional
/// Contacts" section.
///
/// [phone] is nullable: at least one verified representative (Syria's "عز")
/// has no telephone number of their own and is reached through the numbers
/// already listed for the other representatives, so no number should be
/// fabricated for them.
class SupportRegionalContact {
  const SupportRegionalContact({
    required this.name,
    required this.category,
    required this.area,
    this.areaId,
    this.phone,
    this.availability,
    this.availabilityKey,
  });

  final String name;
  final SupportContactCategory category;
  final String area;

  /// Stable id for [area]'s localized display text. Null when this area's
  /// wording hasn't been confirmed for translation yet, in which case the
  /// UI falls back to the raw [area] string unchanged.
  final SupportAreaId? areaId;
  final String? phone;

  /// Human-readable availability window (e.g. "6pm-9pm"), when this
  /// representative is only reachable during specific hours. Null when not
  /// applicable.
  final String? availability;

  /// Translation key for [availability]'s localized text. Null when
  /// [availability] hasn't been confirmed for translation yet, in which
  /// case the UI falls back to the raw [availability] string unchanged.
  final String? availabilityKey;
}

/// A single verified physical office/location for a region, shown in the
/// Contact Us screen's "Locations" section. Regions with more than one
/// verified location (e.g. Syria, Iraq) list one entry per city; regions
/// with a single verified location still use a one-item list so the UI can
/// iterate uniformly instead of branching per region.
class SupportOfficeLocation {
  const SupportOfficeLocation({
    required this.city,
    required this.address,
    this.cityIds = const [],
    this.addressKey,
    this.name,
    this.phone,
  });

  final String city;
  final String address;

  /// Stable id(s) for [city]'s localized display text — more than one
  /// (e.g. Oman's combined "Muscat / Seeb") when the raw [city] string
  /// itself combines more than one place name. Empty when this city hasn't
  /// been added for translation yet, in which case the UI falls back to
  /// the raw [city] string unchanged.
  final List<SupportCityId> cityIds;

  /// Translation key for [address]'s localized text. Null when this
  /// address's wording hasn't been confirmed for translation yet, in which
  /// case the UI falls back to the raw [address] string unchanged.
  final String? addressKey;

  /// Business/location name for this specific office (e.g. "ANC Najjar
  /// Fabric" for Sharjah). Null when no verified name exists for this
  /// office beyond the region's own display name.
  final String? name;

  /// Direct phone number for this specific office, in international
  /// format. Null when no verified number exists for this office — do not
  /// fall back to the region's general hotline numbers, since those are not
  /// verified as belonging to this office.
  final String? phone;
}

/// Region-specific support contact details shown in the Support screen's
/// Live Specialist Support, Corporate Office, Direct Hotline, and Support
/// Hours cards, and in the Contact Us screen's region-scoped contact
/// summary.
///
/// Every contact field is nullable/empty by default: only populate a field
/// once a verified production value exists for that region.
class SupportRegionData {
  const SupportRegionData({
    required this.id,
    required this.displayName,
    this.whatsappNumber,
    this.supportEmail,
    this.officeAddress,
    this.officeAddressKey,
    this.officeLocations = const [],
    this.hotlineNumbers = const [],
    this.supportHours,
    this.regionalContacts = const [],
  });

  final SupportRegionId id;
  final String displayName;

  /// WhatsApp contact number in international format (e.g. `+9715xxxxxxx`),
  /// used to build a `wa.me` link. Null until a verified number exists.
  final String? whatsappNumber;

  /// Support inbox address for this region. Null until a verified address
  /// exists.
  final String? supportEmail;

  /// Corporate office / mailing address for this region. Null until a
  /// verified address exists.
  ///
  /// Used only by the Support screen's single-address "Corporate Office"
  /// card. The Contact Us screen's "Locations" section uses
  /// [officeLocations] instead, since a region may have more than one
  /// verified office.
  final String? officeAddress;

  /// Translation key for [officeAddress]'s localized text. Null when this
  /// address's wording hasn't been confirmed for translation yet, in which
  /// case the UI falls back to the raw [officeAddress] string unchanged.
  final String? officeAddressKey;

  /// Every verified physical office/location for this region, shown in the
  /// Contact Us screen's "Locations" section. Empty until verified location
  /// data exists for this region.
  final List<SupportOfficeLocation> officeLocations;

  /// One or more direct support phone numbers for this region. Empty until
  /// verified numbers exist.
  final List<String> hotlineNumbers;

  /// Human-readable support-hours schedule for this region (e.g.
  /// "Mon-Fri 09:00-18:00"). Null until a verified schedule exists.
  final String? supportHours;

  /// Named regional representatives for this region (currently only
  /// populated for Syria). Empty for regions with no such representatives.
  final List<SupportRegionalContact> regionalContacts;
}
