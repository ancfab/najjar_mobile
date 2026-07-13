/// Static identifier for each region offered in the Support screen's region
/// selector.
enum SupportRegionId { uae, syria, iraq, oman, lebanon }

/// Region-specific support contact details shown in the Support screen's
/// Live Specialist Support, Corporate Office, Direct Hotline, and Support
/// Hours cards.
///
/// Every contact field is nullable/empty by default because no verified
/// production value exists yet for any region — see
/// `lib/data/support_regions_data.dart` for where confirmed values get
/// plugged in later.
class SupportRegionData {
  const SupportRegionData({
    required this.id,
    required this.displayName,
    this.whatsappNumber,
    this.supportEmail,
    this.officeAddress,
    this.hotlineNumbers = const [],
    this.supportHours,
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
}
