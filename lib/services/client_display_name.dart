import 'auth_service.dart';
import 'local_customer_profile_store.dart';

/// Resolves the signed-in account's real display name: the locally-stored
/// customer profile's full name (seeded at login from the account's own
/// Business Central Customer Details row, or the user's own edit on Edit
/// Profile — see `AuthService._seedLocalProfile`) when present, else the
/// session username. Mirrors `AccountBalanceScreen._loadHeaderIdentity`'s
/// exact resolution order, factored out so every screen's header can share
/// it instead of re-implementing its own copy.
///
/// Returns `null` when there is no persisted session at all (display only —
/// never used to decide authentication). A local-profile-store failure is
/// swallowed and falls back to the session username, same as
/// `AccountBalanceScreen`'s own tolerance for that failure — display-only
/// data must never crash a screen's header.
Future<String?> resolveClientDisplayName({
  required AuthService authService,
  required LocalCustomerProfileStore localProfileStore,
}) async {
  final session = await authService.currentSession();
  if (session == null) return null;

  var name = session.username;
  try {
    final profile = await localProfileStore.load(session.userId);
    final fullName = profile?.fullName.trim() ?? '';
    if (fullName.isNotEmpty) name = fullName;
  } catch (_) {
    // Local profile lookup is display-only; the username fallback above
    // already covers it.
  }
  return name;
}
