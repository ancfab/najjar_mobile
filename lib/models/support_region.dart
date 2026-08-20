/// Static identifier for each region offered in the Support screen's region
/// selector.
enum SupportRegionId { uae, syria, iraq, oman, lebanon }

/// Which product line a [SupportRegionalContact] represents, used to group
/// Syria's regional representatives on the Contact Us screen.
enum SupportContactCategory { upholsteryFabrics, curtains }

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
    this.phone,
    this.availability,
  });

  final String name;
  final SupportContactCategory category;
  final String area;
  final String? phone;

  /// Human-readable availability window (e.g. "6pm-9pm"), when this
  /// representative is only reachable during specific hours. Null when not
  /// applicable.
  final String? availability;
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
  final String? officeAddress;

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
