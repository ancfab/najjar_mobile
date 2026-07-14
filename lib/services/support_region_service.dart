import '../data/support_regions_data.dart';
import '../models/support_region.dart';

/// Supplies region-specific Support content (office address, hotline
/// numbers, WhatsApp number, support email, business hours) for the Support
/// screen.
///
/// This is the single service boundary the Support screen calls through —
/// it never reads [kSupportRegions] directly — so the underlying data
/// source (local vs. CMS/API) can change without touching the screen.
///
/// TODO: Replace local [kSupportRegions] data with a CMS/backend Support
/// regions endpoint once backend/product confirm:
///  - Whether this content is CMS-managed or served from application
///    config, and the endpoint (e.g. `GET /support/regions`) if CMS-managed.
///  - The response payload shape per region — expected to map directly onto
///    [SupportRegionData] (id, displayName, whatsappNumber, supportEmail,
///    officeAddress, hotlineNumbers[], supportHours).
///  - Authentication requirements for the endpoint, if any.
///  - A caching strategy, so the last successful response can be shown if a
///    later fetch fails (e.g. offline, API outage).
/// Real CMS integration is blocked pending this confirmation. Until then,
/// this always resolves with [kSupportRegions]; the Support screen still
/// treats the call as fallible (loading/error/local fallback) so no screen
/// changes are needed once a real implementation lands.
class SupportRegionService {
  const SupportRegionService();

  Future<List<SupportRegionData>> fetchSupportRegions() async {
    return kSupportRegions;
  }
}
