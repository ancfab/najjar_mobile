import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/client_display_name.dart';
import '../services/local_customer_profile_store.dart';
import '../theme/app_colors.dart';
import '../utils/user_initials.dart';

/// The real signed-in client's identity in a screen header — an initials
/// badge plus their real name, resolved via [resolveClientDisplayName].
/// Replaces every screen's former hardcoded "IL" / "Indigo Loom" fake-brand
/// header (removed 2026-09-03, per product decision: no fabricated company
/// branding anywhere in the app — the header always shows this customer's
/// own identity instead).
///
/// Three render modes, matching the three header layouts already in use
/// across the app:
/// - Default (bare): badge + the name on one line — e.g. Invoice Details'
///   AppBar title.
/// - [pageTitle] supplied: badge + a column of [small eyebrow name] above
///   [pageTitle] — e.g. Support/Contact Us/Orders' AppBar title.
/// - [badgeOnly] `true`: just the initials badge, no name text at all — for
///   a trailing AppBar-action-style spot with no room for a name (`pageTitle`
///   is ignored in this mode).
///
/// The badge/name are blank while the name hasn't resolved yet (no
/// perceptible session read is instant) and stay blank if there is no
/// session at all — [userInitials]'s neutral `'·'` fallback, never a
/// fabricated name.
class ClientBrandTitle extends StatefulWidget {
  const ClientBrandTitle({
    super.key,
    this.pageTitle,
    this.badgeOnly = false,
    this.badgeSize = 36,
    this.badgeFontSize = 13,
    this.authService,
    this.localProfileStore,
  });

  /// When supplied, renders the "eyebrow name above page title" layout
  /// instead of the plain inline "badge + name" layout.
  final String? pageTitle;

  /// When `true`, renders only the initials badge — no name text.
  final bool badgeOnly;

  final double badgeSize;
  final double badgeFontSize;

  /// Identity seam — used only to read the current session (display only,
  /// never to decide authentication). Defaults (lazily, in State) to a
  /// real, owned [AuthService.production]; overridable so tests can inject
  /// a fake instead of touching real secure storage.
  final AuthService? authService;

  /// Local customer-profile seam feeding the real name — see
  /// [resolveClientDisplayName]. Overridable so tests can inject a fake.
  final LocalCustomerProfileStore? localProfileStore;

  @override
  State<ClientBrandTitle> createState() => _ClientBrandTitleState();
}

class _ClientBrandTitleState extends State<ClientBrandTitle> {
  late final AuthService _authService;
  AuthService? _ownedAuthService;
  late final LocalCustomerProfileStore _localProfileStore;

  String? _displayName;

  @override
  void initState() {
    super.initState();
    final injectedAuthService = widget.authService;
    if (injectedAuthService != null) {
      _authService = injectedAuthService;
    } else {
      final owned = AuthService.production();
      _ownedAuthService = owned;
      _authService = owned;
    }
    _localProfileStore =
        widget.localProfileStore ?? SecureLocalCustomerProfileStore();
    _loadName();
  }

  @override
  void dispose() {
    _ownedAuthService?.close();
    super.dispose();
  }

  Future<void> _loadName() async {
    final name = await resolveClientDisplayName(
      authService: _authService,
      localProfileStore: _localProfileStore,
    );
    if (!mounted) return;
    setState(() => _displayName = name);
  }

  @override
  Widget build(BuildContext context) {
    final name = _displayName ?? '';
    final badge = Container(
      width: widget.badgeSize,
      height: widget.badgeSize,
      decoration: BoxDecoration(
        color: AppColors.primaryNavy,
        borderRadius: BorderRadius.circular(widget.badgeSize >= 36 ? 10 : 8),
      ),
      alignment: Alignment.center,
      child: Text(
        userInitials(name, fallback: '·'),
        style: TextStyle(
          fontSize: widget.badgeFontSize,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),
    );

    if (widget.badgeOnly) return badge;

    final pageTitle = widget.pageTitle;
    return Row(
      children: [
        badge,
        const SizedBox(width: 10),
        Expanded(
          child: pageTitle == null
              ? Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textNavy,
                  ),
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.4,
                        color: AppColors.grayText,
                      ),
                    ),
                    Text(
                      pageTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textNavy,
                      ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}
