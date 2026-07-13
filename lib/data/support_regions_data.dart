import '../models/support_region.dart';

// TODO: No verified WhatsApp number, support email, office address,
// hotline number, or support-hours schedule exists in this project for any
// region yet. Every contact field below is intentionally left unset rather
// than filled with a placeholder-looking value, so the Support screen falls
// back to a neutral "not yet available" message instead of ever displaying
// invented company data. Replace individual fields here once the
// business/ops team confirms real values per region.
const List<SupportRegionData> kSupportRegions = [
  SupportRegionData(id: SupportRegionId.uae, displayName: 'UAE'),
  SupportRegionData(id: SupportRegionId.syria, displayName: 'Syria'),
  SupportRegionData(id: SupportRegionId.iraq, displayName: 'Iraq'),
  SupportRegionData(id: SupportRegionId.oman, displayName: 'Oman'),
  SupportRegionData(id: SupportRegionId.lebanon, displayName: 'Lebanon'),
];
