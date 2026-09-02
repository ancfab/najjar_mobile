import 'dart:io';

import 'package:flutter/material.dart';

import '../data/country_codes.dart';
import '../data/mock_profile_data.dart';
import '../localization/translations.dart';
import '../models/auth/update_profile_result.dart';
import '../models/auth/upload_avatar_result.dart';
import '../models/country_code.dart';
import '../models/local_customer_profile.dart';
import '../models/user_profile.dart';
import '../services/avatar_cropper_service.dart';
import '../services/avatar_image_processor.dart';
import '../services/avatar_permission_service.dart';
import '../services/avatar_picker_service.dart';
import '../services/auth_service.dart';
import '../services/current_user_avatar_controller.dart';
import '../services/local_customer_profile_store.dart';
import '../services/logout_service.dart';
import '../services/profile_service.dart';
import '../services/session_storage_exception.dart';
import '../theme/app_colors.dart';
import '../utils/auth_result_navigation.dart';
import '../utils/contact_form_validators.dart';
import '../utils/responsive.dart';
import '../widgets/contact_form_field.dart';
import '../widgets/custom_bottom_nav.dart';
import 'change_password_screen.dart';
import 'login_screen.dart';
import 'orders_screen.dart';
import 'support_screen.dart';

/// Result of the "Use Photo" / "Choose Again" / "Cancel" preview step shown
/// after cropping.
enum _AvatarPreviewAction { usePhoto, chooseAgain, cancel }

// Bottom tab bar indexes, matching HomeScreen's. This screen is itself the
// Profile tab's destination, so Profile is kept as the selected tab.
const int _navIndexHome = 0;
const int _navIndexOrders = 1;
const int _navIndexSupport = 2;
const int _navIndexProfile = 3;

/// Edit Profile screen: avatar with a camera/edit overlay, client info
/// (ANC ID + last-updated label), a prefilled editable form, a full-width
/// "Save Changes" action, and a "Logout" action.
///
/// The full name/email/company/business-address fields are locally-owned
/// display data (see [LocalCustomerProfile]/[LocalCustomerProfileStore]):
/// no confirmed backend endpoint returns or accepts them yet. They start
/// genuinely empty and are populated only from a profile already saved
/// locally for the signed-in account (see
/// [_EditProfileScreenState._loadIdentity]) — never from [kMockUserProfile]
/// or any other fabricated value, so demo data can never appear as, or be
/// saved as, real customer information. Once the user saves, the local
/// store is the sole source of truth for these fields going forward.
class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({
    super.key,
    this.profile = kMockUserProfile,
    ProfileService? service,
    this.logoutService,
    this.authService,
    this.localProfileStore,
    AvatarPickerService? avatarPickerService,
    AvatarPermissionService? avatarPermissionService,
    AvatarCropperService? avatarCropperService,
    AvatarImageProcessor? avatarImageProcessor,
    this.avatarController,
  }) : service = service ?? const UnavailableProfileService(),
       avatarPickerService =
           avatarPickerService ?? const ImagePickerAvatarPickerService(),
       avatarPermissionService =
           avatarPermissionService ??
           const PermissionHandlerAvatarPermissionService(),
       avatarCropperService =
           avatarCropperService ?? const ImageCropperAvatarCropperService(),
       avatarImageProcessor =
           avatarImageProcessor ?? const DefaultAvatarImageProcessor();

  /// Display-only values for this screen's client-info section (the "ANC
  /// ID: #..." label and the "Profile updated ... ago" caption — see
  /// [_buildAvatarSection]) and for the fixed `phone` value forwarded to
  /// [ProfileService.updateProfile]. Deliberately **not** used to prefill
  /// the full name/email/company/business-address fields — those are
  /// locally-owned customer data (see [LocalCustomerProfile]) and must
  /// never be seeded from mock/fabricated values (see
  /// [_EditProfileScreenState._loadIdentity]). Defaults to the isolated
  /// mock profile; overridable so tests can inject fixed values. Does not
  /// carry username/phone for the editable identity fields — those are
  /// real, authenticated-identity fields prefilled from
  /// [AuthService.currentSession] instead.
  final UserProfile profile;

  /// Remote save-changes seam for the full name/email/company/business-
  /// address fields only — no confirmed backend endpoint exists yet, so
  /// this always reports [ProfileUpdateOutcome.unavailable] in production;
  /// [LocalCustomerProfileStore] (via [localProfileStore]) is these
  /// fields' actual persistence. Defaults to the explicitly non-production
  /// [UnavailableProfileService]; overridable so tests can inject a fake.
  final ProfileService service;

  /// Explicit-logout seam: attempts best-effort remote revocation, then
  /// unconditionally clears the local secure session — see
  /// [LogoutService]/[AuthService.logout]. Defaults (lazily, in State — see
  /// [_EditProfileScreenState]) to the same instance as [authService];
  /// overridable so tests can inject a fake without making a real network
  /// call or touching real secure storage.
  final LogoutService? logoutService;

  /// Real-backend seam for username/phone updates
  /// ([AuthService.updateProfile]) and avatar uploads
  /// ([AuthService.uploadAvatar]). Defaults (lazily, in State — see
  /// [_EditProfileScreenState]) to a real, owned [AuthService.production];
  /// overridable so tests can inject an [AuthService] wired to fakes
  /// instead of making a real network call or touching real secure
  /// storage.
  final AuthService? authService;

  /// Local-persistence seam for the full name/email/company/business-
  /// address fields, scoped per authenticated `userId` (see
  /// [LocalCustomerProfileStore]). Defaults (lazily, in State — see
  /// [_EditProfileScreenState]) to a real [SecureLocalCustomerProfileStore];
  /// overridable so tests can inject a fake instead of touching real secure
  /// storage.
  final LocalCustomerProfileStore? localProfileStore;

  /// Camera/gallery selection seam. Overridable so tests can inject a fake
  /// instead of invoking the real platform picker.
  final AvatarPickerService avatarPickerService;

  /// Camera/gallery permission seam. Overridable so tests can inject a
  /// fake instead of invoking the real platform permission channel.
  final AvatarPermissionService avatarPermissionService;

  /// Square-crop seam. Overridable so tests can inject a fake instead of
  /// invoking the real platform cropper UI.
  final AvatarCropperService avatarCropperService;

  /// Picked-image validation seam. Overridable so tests can simulate an
  /// invalid/unreadable file without needing one on disk.
  final AvatarImageProcessor avatarImageProcessor;

  /// Shared current-user avatar state. Defaults (lazily, in State — see
  /// [_EditProfileScreenState]) to the app-wide [currentUserAvatarController]
  /// singleton; overridable so tests can inject a fresh instance instead of
  /// sharing that mutable singleton across test cases.
  final CurrentUserAvatarController? avatarController;

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();

  // Real, authenticated-identity fields — prefilled asynchronously from
  // AuthService.currentSession() (see _loadIdentity), not from
  // widget.profile. Start empty; _loadIdentity populates both the
  // controllers and the _initial*/​_selectedCountry baselines together, so
  // _isDirty never reports a false "changed" before that load completes.
  final _usernameController = TextEditingController();
  final _phoneController = TextEditingController();

  // Locally-owned customer fields — prefilled asynchronously from
  // LocalCustomerProfileStore (see _loadIdentity), never from
  // widget.profile/kMockUserProfile: fabricated demo data must never appear
  // as if it were this customer's real information, nor be savable back
  // into their local profile. Start empty; a signed-in account with no
  // locally-saved profile yet is expected to see genuinely empty fields
  // until they enter their own values.
  final _fullNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _companyController = TextEditingController();
  final _businessAddressController = TextEditingController();

  final _usernameFocusNode = FocusNode();
  final _phoneFocusNode = FocusNode();
  final _fullNameFocusNode = FocusNode();
  final _emailFocusNode = FocusNode();
  final _companyFocusNode = FocusNode();
  final _businessAddressFocusNode = FocusNode();

  // Normalized snapshot of the profile as loaded, kept separately from
  // [widget.profile] so dirty-state comparison survives widget rebuilds
  // without re-reading (and re-trimming) the source profile each time.
  // Mutable (not `late final`): a successful save moves this snapshot
  // forward to the just-submitted values, so the form is clean again
  // afterwards instead of permanently reporting unsaved changes.
  late String _initialFullName;
  late String _initialEmail;
  late String _initialCompany;
  late String _initialBusinessAddress;

  // Identity baselines, populated once by _loadIdentity(). Empty strings
  // until then, matching the also-empty controllers above, so dirty
  // tracking never falsely trips during the brief load.
  String _initialUsername = '';
  String _initialPhoneDigits = '';

  // The authenticated userId, populated once by _loadIdentity() — the key
  // LocalCustomerProfileStore scopes this account's full name/email/
  // company/business-address fields under. Null until that load completes
  // or if it never does (e.g. no session), in which case Save Changes
  // skips local persistence rather than guessing a key.
  int? _currentUserId;

  // The authenticated user's country, resolved from AuthSession.country —
  // fixed/read-only on this screen (see the class doc comment); only used
  // to render/compose the phone field's dial-code prefix. Defaults to
  // kDefaultCountryCode until _loadIdentity resolves the real one.
  CountryCode _selectedCountry = kDefaultCountryCode;

  // Backend-vetted field-level errors from the most recent identity save
  // attempt (HTTP 422 errors.username/errors.phone) — cleared as soon as
  // the user edits the corresponding field again, the same way a
  // TextFormField's own validator error clears on next input.
  String? _usernameServerError;
  String? _phoneServerError;

  bool _isSaving = false;
  bool _isLoggingOut = false;
  AutovalidateMode _autovalidateMode = AutovalidateMode.disabled;

  // Resolved lazily (not in the widget's const constructor, since the
  // default is a mutable app-wide singleton, not a const value) so
  // production call sites share one avatar state while tests can inject a
  // fresh instance via `widget.avatarController`.
  late final CurrentUserAvatarController _avatarController =
      widget.avatarController ?? currentUserAvatarController;

  // Real-backend seam for username/phone updates and avatar uploads,
  // resolved in initState (not the widget's constructor) since the
  // production default owns a real AncApiClient that must be closed —
  // mirrors LoginScreen's AuthService.production ownership pattern rather
  // than instantiating one per build().
  late final AuthService _authService;

  // Local-persistence seam for full name/email/company/business address,
  // resolved lazily the same way _avatarController is (the production
  // default is a real SecureLocalCustomerProfileStore, not a const value).
  late final LocalCustomerProfileStore _localProfileStore =
      widget.localProfileStore ?? SecureLocalCustomerProfileStore();

  // Explicit-logout seam. Defaults to _authService itself (AuthService
  // implements LogoutService) unless a narrower fake is injected via
  // widget.logoutService.
  late final LogoutService _logoutService;

  // Only set when this State created its own AuthService.production() (no
  // widget.authService was injected) — that instance is the only thing
  // this screen ever closes; a caller-injected AuthService is left alone.
  AuthService? _ownedAuthService;

  // Guards the whole camera-icon-to-confirmation flow (source selection,
  // permission request, picking, validation, cropping, preview, and the
  // avatar service call) so repeated taps can't start overlapping
  // operations. Disables the camera button for the flow's entire duration.
  bool _isAvatarFlowActive = false;

  // Purely visual: true only while an actual async device/service call is
  // in flight (permission request, picker, cropper, or the avatar service),
  // so the camera button shows a spinner in place of its icon. Deliberately
  // false while the source-selection sheet or the preview dialog is simply
  // waiting on a user choice — an indeterminate CircularProgressIndicator
  // animates forever, so leaving it showing during a user-paced modal wait
  // would never let `pumpAndSettle` (or a real user watching an endlessly
  // spinning icon) settle.
  bool _isAvatarBusy = false;

  List<TextEditingController> get _formControllers => [
    _usernameController,
    _phoneController,
    _fullNameController,
    _emailController,
    _companyController,
    _businessAddressController,
  ];

  // Whether the locally-owned customer fields (full name, email, company,
  // business address) differ from their loaded baseline — gates whether
  // Save Changes attempts the existing ProfileService call. Name kept as
  // "MockProfile" to match ProfileService/UnavailableProfileService's
  // existing naming for this same seam, not because the field values
  // themselves are mock-derived (they are not — see _loadIdentity).
  bool get _isMockProfileDirty {
    return _fullNameController.text.trim() != _initialFullName ||
        _emailController.text.trim() != _initialEmail ||
        _companyController.text.trim() != _initialCompany ||
        _businessAddressController.text.trim() != _initialBusinessAddress;
  }

  // Whether the real identity fields (username, phone) differ from their
  // loaded baseline — gates whether Save Changes attempts
  // AuthService.updateProfile, and ensures an empty PATCH is never sent.
  bool get _isIdentityDirty {
    return _usernameController.text.trim() != _initialUsername ||
        _phoneController.text.trim() != _initialPhoneDigits;
  }

  // Trimmed current values compared against the initial snapshot, so Save
  // Changes stays disabled until the form actually differs from the
  // loaded profile (whitespace-only edits don't count as a change).
  bool get _isDirty => _isMockProfileDirty || _isIdentityDirty;

  @override
  void initState() {
    super.initState();
    // Genuinely empty — not widget.profile/kMockUserProfile — until
    // _loadIdentity's LocalCustomerProfileStore lookup resolves (see its
    // doc comment). Kept in sync with the also-empty controllers above so
    // _isDirty never falsely trips before that load completes.
    _initialFullName = '';
    _initialEmail = '';
    _initialCompany = '';
    _initialBusinessAddress = '';
    for (final controller in _formControllers) {
      controller.addListener(_handleFormChanged);
    }

    final injectedAuthService = widget.authService;
    if (injectedAuthService != null) {
      _authService = injectedAuthService;
    } else {
      final owned = AuthService.production();
      _ownedAuthService = owned;
      _authService = owned;
    }
    _logoutService = widget.logoutService ?? _authService;

    _loadIdentity();
  }

  // Prefills username/phone from the currently persisted session (display
  // only — never used to decide authentication, see
  // AuthService.currentSession's doc comment). Resolves the dial code from
  // AuthSession.country via kCountryCodes and strips it from the stored
  // E.164 phone so the field shows only the locally-editable digits — the
  // dial code itself is rendered read-only (see _buildFormFields) and is
  // re-attached exactly once, at submit time (see _composePhoneForSubmit),
  // so it can never be double-prefixed.
  //
  // Also loads this account's locally-persisted profile (full name/email/
  // company/business address — see LocalCustomerProfileStore), keyed by
  // the session's userId. The production LocalCustomerProfileStore never
  // throws from load() (see its doc comment) — no profile saved yet for
  // this account resolves to null, in which case the fields stay exactly
  // as initState left them: genuinely empty, never a mock/fabricated
  // value. The try/catch below is defense-in-depth against any other
  // implementation (e.g. a test double) that doesn't honor that contract:
  // this screen must never crash over the local profile lookup.
  Future<void> _loadIdentity() async {
    final session = await _authService.currentSession();
    if (!mounted || session == null) return;

    final country = kCountryCodes.firstWhere(
      (candidate) => candidate.isoCode == session.country,
      orElse: () => kDefaultCountryCode,
    );
    final phoneDigits = session.phone.startsWith(country.dialCode)
        ? session.phone.substring(country.dialCode.length)
        : session.phone;

    LocalCustomerProfile? localProfile;
    try {
      localProfile = await _localProfileStore.load(session.userId);
    } catch (error) {
      debugPrint('Failed to load local customer profile: $error');
    }
    if (!mounted) return;

    setState(() {
      _selectedCountry = country;
      _usernameController.text = session.username;
      _phoneController.text = phoneDigits;
      _initialUsername = session.username;
      _initialPhoneDigits = phoneDigits;
      _currentUserId = session.userId;

      if (localProfile != null) {
        _fullNameController.text = localProfile.fullName;
        _emailController.text = localProfile.email;
        _companyController.text = localProfile.company;
        _businessAddressController.text = localProfile.businessAddress;
        _initialFullName = localProfile.fullName.trim();
        _initialEmail = localProfile.email.trim();
        _initialCompany = localProfile.company.trim();
        _initialBusinessAddress = localProfile.businessAddress.trim();
      }
    });
  }

  // Composes the full E.164 phone from the fixed (read-only on this
  // screen) dial code plus the field's current local digits — the only
  // place this concatenation happens, so it can never run twice.
  String _composePhoneForSubmit() =>
      '${_selectedCountry.dialCode}${_phoneController.text.trim()}';

  // Rebuilds so the Save Changes button's enabled state tracks [_isDirty]
  // as the user types.
  void _handleFormChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    for (final controller in _formControllers) {
      controller.removeListener(_handleFormChanged);
    }
    _usernameController.dispose();
    _phoneController.dispose();
    _fullNameController.dispose();
    _emailController.dispose();
    _companyController.dispose();
    _businessAddressController.dispose();
    _usernameFocusNode.dispose();
    _phoneFocusNode.dispose();
    _fullNameFocusNode.dispose();
    _emailFocusNode.dispose();
    _companyFocusNode.dispose();
    _businessAddressFocusNode.dispose();
    _ownedAuthService?.close();
    super.dispose();
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// Maps a validation failure reason to a neutral, safe, localized message
  /// — never a raw exception/implementation detail.
  String _messageForValidationReason(AvatarImageValidationReason reason) {
    switch (reason) {
      case AvatarImageValidationReason.fileNotFound:
        return context.t('editProfile.fileNotFound');
      case AvatarImageValidationReason.emptyFile:
        return context.t('editProfile.emptyFile');
      case AvatarImageValidationReason.tooLarge:
        return context.t('editProfile.tooLarge');
      case AvatarImageValidationReason.unreadableFile:
        return context.t('editProfile.unreadableFile');
      case AvatarImageValidationReason.unsupportedFormat:
        return context.t('editProfile.unsupportedFormat');
      case AvatarImageValidationReason.corruptImage:
        return context.t('editProfile.corruptImage');
    }
  }

  void _showPermanentlyDeniedSnackBar(AvatarImageSource source) {
    final label = source == AvatarImageSource.camera
        ? context.t('editProfile.cameraSource')
        : context.t('editProfile.gallerySource');
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            context.t('editProfile.accessTurnedOff', params: {'label': label}),
          ),
          action: SnackBarAction(
            label: context.t('editProfile.openSettings'),
            onPressed: () {
              widget.avatarPermissionService.openSettings();
            },
          ),
        ),
      );
  }

  // Camera overlay tap handler: runs the full take-photo/choose-from-gallery
  // -> permission -> pick -> validate -> crop -> preview -> confirm flow.
  // Guarded by `_isAvatarFlowActive` (and the camera button's onPressed
  // being null while active) so repeated taps can't start overlapping
  // operations, for the flow's entire duration — including while the
  // source sheet or preview dialog is simply waiting on the user, not just
  // while `_isAvatarBusy` (the spinner) is true.
  Future<void> _handleChangePhoto() async {
    if (_isAvatarFlowActive) return;
    debugPrint('[AVATAR DEBUG] Change-photo button tapped.');
    setState(() => _isAvatarFlowActive = true);
    try {
      await _runAvatarSelectionFlow();
    } finally {
      if (mounted) {
        setState(() {
          _isAvatarFlowActive = false;
          _isAvatarBusy = false;
        });
      }
    }
  }

  Future<void> _runAvatarSelectionFlow() async {
    // Loops so "Choose Again" from the preview step can restart from
    // source selection without leaving the active/guarded state.
    while (true) {
      debugPrint('[AVATAR DEBUG] Source sheet opened.');
      final source = await _showAvatarSourceSheet();
      if (!mounted || source == null) {
        debugPrint('[AVATAR DEBUG] Source sheet cancelled/dismissed.');
        return;
      }
      debugPrint(
        '[AVATAR DEBUG] Source selected: '
        '${source == AvatarImageSource.camera ? 'Camera' : 'Gallery'}',
      );

      setState(() => _isAvatarBusy = true);
      final validatedPath = await _pickAndValidateImage(source);
      if (!mounted) return;
      if (validatedPath == null) {
        setState(() => _isAvatarBusy = false);
        return;
      }

      final croppedPath = await _cropImage(validatedPath);
      if (!mounted) return;
      if (croppedPath == null) {
        setState(() => _isAvatarBusy = false);
        return;
      }

      // The preview dialog is this screen's own UI waiting on a user
      // choice, not a loading state, so the spinner is hidden while it's
      // open (the camera button stays disabled throughout regardless, via
      // `_isAvatarFlowActive`).
      setState(() => _isAvatarBusy = false);
      debugPrint('[AVATAR DEBUG] Preview opened for: $croppedPath');
      final action = await _showAvatarPreviewDialog(croppedPath);
      if (!mounted) return;

      switch (action) {
        case _AvatarPreviewAction.usePhoto:
          debugPrint('[AVATAR DEBUG] Use Photo selected.');
          setState(() => _isAvatarBusy = true);
          await _applyAvatar(croppedPath);
          return;
        case _AvatarPreviewAction.chooseAgain:
          debugPrint('[AVATAR DEBUG] Choose Again selected.');
          continue;
        case _AvatarPreviewAction.cancel:
          debugPrint('[AVATAR DEBUG] Preview cancelled.');
          return;
      }
    }
  }

  Future<AvatarImageSource?> _showAvatarSourceSheet() {
    return showModalBottomSheet<AvatarImageSource>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              key: const ValueKey('edit-profile-avatar-source-camera'),
              leading: const Icon(Icons.camera_alt_rounded),
              title: Text(context.t('editProfile.takePhoto')),
              onTap: () =>
                  Navigator.of(sheetContext).pop(AvatarImageSource.camera),
            ),
            ListTile(
              key: const ValueKey('edit-profile-avatar-source-gallery'),
              leading: const Icon(Icons.photo_library_rounded),
              title: Text(context.t('editProfile.chooseFromGallery')),
              onTap: () =>
                  Navigator.of(sheetContext).pop(AvatarImageSource.gallery),
            ),
            ListTile(
              key: const ValueKey('edit-profile-avatar-source-cancel'),
              leading: const Icon(Icons.close_rounded),
              title: Text(context.t('common.cancel')),
              onTap: () => Navigator.of(sheetContext).pop(),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // Requests the permission appropriate for [source], then picks and
  // validates an image. Returns the picked image's path once it has passed
  // validation, or null if the user cancelled/denied at any stage — in
  // every null-returning case, user-facing feedback has already been shown
  // (except a plain picker cancel, which is silent by design) and the
  // previous avatar is left untouched.
  Future<String?> _pickAndValidateImage(AvatarImageSource source) async {
    debugPrint(
      '[AVATAR DEBUG] Permission request started for '
      '${source == AvatarImageSource.camera ? 'camera' : 'gallery'}.',
    );
    final permissionStatus = source == AvatarImageSource.camera
        ? await widget.avatarPermissionService.requestCameraPermission()
        : await widget.avatarPermissionService.requestGalleryPermission();
    if (!mounted) return null;
    debugPrint('[AVATAR DEBUG] Permission result: $permissionStatus');

    switch (permissionStatus) {
      case AvatarPermissionStatus.granted:
      case AvatarPermissionStatus.limited:
        break;
      case AvatarPermissionStatus.denied:
        _showSnackBar(
          source == AvatarImageSource.camera
              ? context.t('editProfile.cameraAccessNeeded')
              : context.t('editProfile.galleryAccessNeeded'),
        );
        return null;
      case AvatarPermissionStatus.restricted:
        _showSnackBar(context.t('editProfile.accessRestricted'));
        return null;
      case AvatarPermissionStatus.permanentlyDenied:
        _showPermanentlyDeniedSnackBar(source);
        return null;
    }

    debugPrint('[AVATAR DEBUG] Picker started.');
    PickedAvatarImage? picked;
    try {
      picked = await widget.avatarPickerService.pickImage(source);
    } catch (error) {
      // Technical detail only — never shown to the user.
      debugPrint('Avatar picker failed: $error');
      debugPrint('[AVATAR DEBUG] Picker threw: $error');
      if (mounted) {
        _showSnackBar(context.t('editProfile.pickerFailed'));
      }
      return null;
    }
    if (!mounted) return null;
    if (picked == null) {
      debugPrint('[AVATAR DEBUG] Picker cancelled by user.');
      return null; // User cancelled the platform picker.
    }

    // Sync stat calls deliberately, not the async File.exists()/length():
    // the async dart:io variants route through the real IO-service thread,
    // which a fake-picker widget test's pumpAndSettle() never waits for
    // (there is no injected fake for raw dart:io), causing a timeout. Sync
    // calls run inline on the calling isolate instead, so they can't strand
    // a pump loop that has nothing else pending.
    final pickedFile = File(picked.path);
    final pickedExists = pickedFile.existsSync();
    final pickedLength = pickedExists ? pickedFile.lengthSync() : 0;
    debugPrint('[AVATAR DEBUG] Picker returned a file.');
    debugPrint('[AVATAR DEBUG] Picked file path: ${picked.path}');
    debugPrint('[AVATAR DEBUG] Picked file exists: $pickedExists');
    debugPrint('[AVATAR DEBUG] Picked file size: $pickedLength bytes');

    debugPrint('[AVATAR DEBUG] Image validation started.');
    try {
      await widget.avatarImageProcessor.validate(picked.path);
      debugPrint('[AVATAR DEBUG] Image validation succeeded.');
    } on AvatarImageValidationException catch (error) {
      debugPrint('[AVATAR DEBUG] Image validation failed: ${error.reason}');
      if (mounted) _showSnackBar(_messageForValidationReason(error.reason));
      return null;
    } catch (error) {
      debugPrint('Avatar validation failed: $error');
      debugPrint('[AVATAR DEBUG] Image validation failed: $error');
      if (mounted) {
        _showSnackBar(context.t('editProfile.photoUnusable'));
      }
      return null;
    }

    return picked.path;
  }

  Future<String?> _cropImage(String sourcePath) async {
    debugPrint('[AVATAR DEBUG] Crop started for: $sourcePath');
    try {
      final croppedPath = await widget.avatarCropperService.cropToSquare(
        sourcePath,
        toolbarTitle: context.t('editProfile.cropToolbarTitle'),
      );
      if (croppedPath == null) {
        debugPrint('[AVATAR DEBUG] Crop cancelled by user.');
        return null; // null == user cancelled cropping.
      }

      // Sync stat calls — see the matching comment in
      // _pickAndValidateImage above.
      final croppedFile = File(croppedPath);
      final croppedExists = croppedFile.existsSync();
      final croppedLength = croppedExists ? croppedFile.lengthSync() : 0;
      debugPrint('[AVATAR DEBUG] Crop succeeded.');
      debugPrint('[AVATAR DEBUG] Cropped file path: $croppedPath');
      debugPrint('[AVATAR DEBUG] Cropped file exists: $croppedExists');
      debugPrint('[AVATAR DEBUG] Cropped file size: $croppedLength bytes');
      return croppedPath;
    } catch (error) {
      debugPrint('Avatar crop failed: $error');
      debugPrint('[AVATAR DEBUG] Crop threw: $error');
      if (mounted) {
        _showSnackBar(context.t('editProfile.cropFailed'));
      }
      return null;
    }
  }

  Future<_AvatarPreviewAction> _showAvatarPreviewDialog(
    String croppedPath,
  ) async {
    final action = await showDialog<_AvatarPreviewAction>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        key: const ValueKey('edit-profile-avatar-preview-dialog'),
        title: Text(context.t('editProfile.previewTitle')),
        content: SizedBox(
          width: 160,
          height: 160,
          child: ClipOval(
            child: Image.file(
              File(croppedPath),
              key: const ValueKey('edit-profile-avatar-preview-image'),
              fit: BoxFit.cover,
            ),
          ),
        ),
        actions: [
          TextButton(
            key: const ValueKey('edit-profile-avatar-preview-cancel'),
            onPressed: () =>
                Navigator.of(dialogContext).pop(_AvatarPreviewAction.cancel),
            child: Text(context.t('common.cancel')),
          ),
          TextButton(
            key: const ValueKey('edit-profile-avatar-preview-choose-again'),
            onPressed: () => Navigator.of(
              dialogContext,
            ).pop(_AvatarPreviewAction.chooseAgain),
            child: Text(context.t('editProfile.chooseAgain')),
          ),
          TextButton(
            key: const ValueKey('edit-profile-avatar-preview-use-photo'),
            onPressed: () =>
                Navigator.of(dialogContext).pop(_AvatarPreviewAction.usePhoto),
            child: Text(context.t('editProfile.usePhoto')),
          ),
        ],
      ),
    );
    return action ?? _AvatarPreviewAction.cancel;
  }

  // Confirms the cropped, previewed image as the new avatar. Only reached
  // after the user explicitly taps "Use Photo" — a failed or cancelled
  // attempt at any earlier stage never reaches (or affects) this step.
  // Success is defined solely by the server's response — the local
  // pick/crop/preview flow above never itself counts as a saved avatar.
  Future<void> _applyAvatar(String croppedPath) async {
    debugPrint('[AVATAR DEBUG] Upload started for: $croppedPath');
    final UploadAvatarResult result;
    try {
      result = await _authService.uploadAvatar(File(croppedPath));
    } catch (error) {
      debugPrint('Avatar update failed: $error');
      debugPrint('[AVATAR DEBUG] Upload threw: $error');
      if (mounted) {
        _showSnackBar(context.t('editProfile.photoUpdateFailed'));
      }
      return;
    }
    debugPrint('[AVATAR DEBUG] Upload result type: ${result.runtimeType}');
    if (!mounted) return;

    switch (result) {
      case UploadAvatarSuccess(:final session):
        debugPrint('[AVATAR DEBUG] UI avatar update started.');
        debugPrint(
          '[AVATAR DEBUG] New avatar URL received: ${session.avatarUrl}',
        );
        // Refreshed avatarUrl only — see AuthSession.fromAuthenticatedUser
        // in AuthService.uploadAvatar for every other identity field.
        debugPrint(
          '[AVATAR DEBUG] Avatar controller update + cache eviction '
          'attempted.',
        );
        _avatarController.setAvatarUrl(session.avatarUrl);
        debugPrint(
          '[AVATAR DEBUG] Avatar controller update + cache eviction '
          'completed.',
        );
        debugPrint('[AVATAR DEBUG] Success snackbar shown.');
        _showSnackBar(context.t('editProfile.photoUpdated'));
      case UploadAvatarFailure(type: UploadAvatarFailureType.unauthorized):
        debugPrint('[AVATAR DEBUG] Error snackbar branch: unauthorized.');
        handleUnauthorizedResult(context, _avatarController);
      case UploadAvatarFailure(type: UploadAvatarFailureType.fileNotFound):
        debugPrint('[AVATAR DEBUG] Error snackbar branch: fileNotFound.');
        _showSnackBar(context.t('editProfile.fileNotFound'));
      case UploadAvatarFailure(type: UploadAvatarFailureType.fileTooLarge):
        debugPrint('[AVATAR DEBUG] Error snackbar branch: fileTooLarge.');
        _showSnackBar(context.t('editProfile.tooLarge'));
      case UploadAvatarFailure(type: UploadAvatarFailureType.unsupportedFormat):
        debugPrint('[AVATAR DEBUG] Error snackbar branch: unsupportedFormat.');
        _showSnackBar(context.t('editProfile.unsupportedFormat'));
      case UploadAvatarFailure(
        type: UploadAvatarFailureType.rejectedByServer,
        :final message,
      ):
        debugPrint(
          '[AVATAR DEBUG] Error snackbar branch: rejectedByServer '
          '(message present: ${message != null}).',
        );
        _showSnackBar(message ?? context.t('editProfile.photoUpdateFailed'));
      case UploadAvatarFailure(:final type):
        debugPrint('[AVATAR DEBUG] Error snackbar branch: $type.');
        _showSnackBar(context.t('editProfile.photoUpdateFailed'));
    }
  }

  // Runs the local-profile save (full name/email/company/address, if
  // dirty) and the real identity PATCH (username/phone, if dirty)
  // independently — each only fires the request its own fields actually
  // need, so an unchanged identity never sends an empty PATCH and an
  // unchanged profile section never calls ProfileService pointlessly. Both
  // share one Save Changes button/loading state, per the existing design.
  //
  // The full name/email/company/business-address fields are persisted to
  // LocalCustomerProfileStore unconditionally whenever they're dirty —
  // independent of ProfileService's outcome. ProfileService has no
  // confirmed real backend yet (see UnavailableProfileService), so local
  // storage — not that call — is these fields' actual source of truth;
  // the ProfileService call/message is preserved unchanged alongside it
  // for whenever a real endpoint exists.
  Future<void> _handleSave() async {
    if (_isSaving || !_isDirty) return;

    final isValid = _formKey.currentState?.validate() ?? false;
    if (!isValid) {
      setState(() => _autovalidateMode = AutovalidateMode.onUserInteraction);
      return;
    }

    setState(() {
      _isSaving = true;
      _usernameServerError = null;
      _phoneServerError = null;
    });
    FocusScope.of(context).unfocus();

    String? resultMessage;

    if (_isMockProfileDirty) {
      final request = ProfileUpdateRequest(
        fullName: _fullNameController.text.trim(),
        email: _emailController.text.trim(),
        // This mock/local field has no editable UI of its own anymore —
        // see the class doc comment — so it is passed through unchanged
        // rather than read from a repurposed controller.
        phone: widget.profile.phone,
        company: _companyController.text.trim(),
        businessAddress: _businessAddressController.text.trim(),
      );

      try {
        final result = await widget.service.updateProfile(request);
        if (!mounted) return;
        switch (result.outcome) {
          case ProfileUpdateOutcome.success:
            resultMessage =
                result.message ?? context.t('editProfile.profileUpdated');
          case ProfileUpdateOutcome.failure:
            resultMessage =
                result.message ?? context.t('editProfile.profileSaveFailed');
          case ProfileUpdateOutcome.unavailable:
            resultMessage = context.t('editProfile.profileUpdatesNotConnected');
        }
      } catch (error) {
        // Technical detail only — never the submitted profile fields.
        debugPrint('Profile update failed: $error');
        if (!mounted) return;
        resultMessage = context.t('editProfile.profileSaveFailed');
      }

      // Persisted regardless of ProfileService's outcome above — see this
      // method's doc comment. Moves the dirty-state baseline forward to
      // what was just saved, so the form reads as clean again instead of
      // still reporting (and warning on back navigation about) changes
      // already saved locally.
      final userId = _currentUserId;
      if (userId != null) {
        try {
          await _localProfileStore.save(
            userId,
            LocalCustomerProfile(
              fullName: request.fullName,
              email: request.email,
              company: request.company,
              businessAddress: request.businessAddress,
            ),
          );
          _initialFullName = request.fullName;
          _initialEmail = request.email;
          _initialCompany = request.company;
          _initialBusinessAddress = request.businessAddress;
        } catch (error) {
          debugPrint('Failed to persist local customer profile: $error');
        }
      }
    }

    if (_isIdentityDirty) {
      final usernameChanged =
          _usernameController.text.trim() != _initialUsername;
      final phoneChanged = _phoneController.text.trim() != _initialPhoneDigits;

      final result = await _authService.updateProfile(
        username: usernameChanged ? _usernameController.text.trim() : null,
        phone: phoneChanged ? _composePhoneForSubmit() : null,
      );
      if (!mounted) return;

      switch (result) {
        case UpdateProfileSuccess(:final session):
          _initialUsername = session.username;
          // session.phone is the full E.164 value; re-derive the local
          // digits the same way _loadIdentity does, so the baseline stays
          // consistent with what the field displays.
          _initialPhoneDigits =
              session.phone.startsWith(_selectedCountry.dialCode)
              ? session.phone.substring(_selectedCountry.dialCode.length)
              : session.phone;
          resultMessage = context.t('editProfile.profileUpdated');
        case UpdateProfileFailure(type: UpdateProfileFailureType.unauthorized):
          setState(() => _isSaving = false);
          handleUnauthorizedResult(context, _avatarController);
          return;
        case UpdateProfileFailure(
          type: UpdateProfileFailureType.usernameTaken,
          :final usernameError,
        ):
          setState(
            () => _usernameServerError =
                usernameError ?? context.t('editProfile.usernameTaken'),
          );
        case UpdateProfileFailure(
          type: UpdateProfileFailureType.invalidPhone,
          :final phoneError,
        ):
          setState(
            () => _phoneServerError =
                phoneError ?? context.t('editProfile.phoneInvalidServer'),
          );
        case UpdateProfileFailure():
          resultMessage = context.t('editProfile.profileSaveFailed');
      }
    }

    if (mounted) {
      setState(() => _isSaving = false);
      if (resultMessage != null) _showSnackBar(resultMessage);
    }
  }

  // Logout button tap handler. Clears the authenticated session and routes
  // to Login, removing every authenticated screen from the stack so back
  // navigation (system back / iOS back gesture) can't return to Home,
  // Profile, or any other authenticated screen. Guarded against duplicate
  // taps while a request is in flight. Logout is an explicit
  // session-ending action, not normal back navigation, so it deliberately
  // does not go through `Navigator.pop`/`maybePop` and therefore bypasses
  // this screen's PopScope/unsaved-changes discard flow entirely — it
  // works the same whether the form is dirty or not, and never saves
  // unsaved edits first.
  Future<void> _handleLogout() async {
    if (_isLoggingOut) return;
    setState(() => _isLoggingOut = true);

    try {
      // Attempts best-effort remote revocation, then unconditionally clears
      // the local secure session (see AuthService.logout). Throws
      // SessionStorageException only on an expected secure-storage
      // failure — the secure token is guaranteed to still exist whenever
      // this throws (see SecureAuthSessionStore.clear()'s ordering
      // guarantee), so the catch clause below never clears the avatar or
      // navigates away. A StateError/ArgumentError or other programming
      // defect is deliberately not caught here — it must not be
      // relabeled as this neutral failure.
      await _logoutService.logout();
      if (!mounted) return;

      // Clears the shared avatar state so the next signed-in user on this
      // device never sees this user's avatar. Only reached after the
      // secure session is confirmed cleared above.
      _avatarController.clear();
      if (!mounted) return;

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    } on SessionStorageException {
      if (!mounted) return;
      setState(() => _isLoggingOut = false);
      _showSnackBar(context.t('editProfile.signOutFailed'));
    }
  }

  // Called whenever something (the back button, a system back gesture, or
  // the bottom nav's Home tab, all of which go through `maybePop`) tries to
  // leave this screen while [_isDirty] blocked it via [PopScope.canPop].
  // Confirms the user actually wants to discard unsaved changes before
  // completing the pop; `Navigator.pop` (not `maybePop`) is used here since
  // it leaves unconditionally rather than being blocked again by the same
  // `canPop` check.
  Future<void> _handleAttemptedPop(bool didPop, Object? result) async {
    if (didPop) return;
    final shouldDiscard = await _confirmDiscardChanges();
    if (shouldDiscard && mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<bool> _confirmDiscardChanges() async {
    final shouldDiscard = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        key: const ValueKey('edit-profile-discard-dialog'),
        title: Text(context.t('editProfile.discardChangesTitle')),
        content: Text(context.t('editProfile.discardChangesBody')),
        actions: [
          TextButton(
            key: const ValueKey('edit-profile-discard-cancel'),
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(context.t('editProfile.keepEditing')),
          ),
          TextButton(
            key: const ValueKey('edit-profile-discard-confirm'),
            style: TextButton.styleFrom(foregroundColor: AppColors.dangerRed),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(context.t('editProfile.discard')),
          ),
        ],
      ),
    );
    return shouldDiscard ?? false;
  }

  // Handles bottom tab bar taps. Home returns to the screen this was
  // pushed from; Orders/Support push their screens the same way the rest
  // of the app's bottom nav does. Profile is a no-op: this screen already
  // is the Profile tab's destination, so selecting it again must not push
  // a duplicate instance.
  void _handleBottomNavTap(int tabIndex) {
    switch (tabIndex) {
      case _navIndexHome:
        Navigator.of(context).maybePop();
        break;
      case _navIndexOrders:
        Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const OrdersScreen()));
        break;
      case _navIndexSupport:
        Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const SupportScreen()));
        break;
      case _navIndexProfile:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Blocks a "soft" pop (back button/gesture, or the bottom nav's Home
      // tab — all routed through `maybePop`) while there are unsaved
      // edits, so [_handleAttemptedPop] can confirm before discarding them.
      canPop: !_isDirty,
      onPopInvokedWithResult: _handleAttemptedPop,
      child: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        behavior: HitTestBehavior.opaque,
        child: Scaffold(
          backgroundColor: AppColors.background,
          appBar: _buildAppBar(),
          body: SafeArea(
            top: false,
            child: Column(
              children: [
                Expanded(child: _buildFormBody()),
                CustomBottomNav(
                  currentIndex: _navIndexProfile,
                  onTap: _handleBottomNavTap,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  AppBar _buildAppBar() {
    return AppBar(
      backgroundColor: Colors.white,
      foregroundColor: AppColors.textNavy,
      elevation: 0,
      toolbarHeight: 68,
      titleSpacing: 0,
      leading: IconButton(
        key: const ValueKey('edit-profile-back-button'),
        icon: Transform.flip(
          flipX: Directionality.of(context) == TextDirection.rtl,
          child: const Icon(Icons.arrow_back_rounded),
        ),
        tooltip: context.t('common.back'),
        onPressed: () => Navigator.of(context).maybePop(),
      ),
      title: ClampedTextScale(
        child: Text(
          context.t('editProfile.title'),
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: AppColors.textNavy,
          ),
        ),
      ),
      // Visual-only, matching the reference layout. No menu actions are
      // defined for this icon yet, so it's non-interactive rather than
      // wired to invented behavior.
      actions: const [
        Padding(
          padding: EdgeInsetsDirectional.only(end: 16),
          child: Icon(Icons.more_vert_rounded, color: AppColors.textNavy),
        ),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(color: AppColors.border, height: 1),
      ),
    );
  }

  Widget _buildFormBody() {
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        16,
        24,
        16,
        24 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: ResponsiveMaxWidth(
        child: Form(
          key: _formKey,
          autovalidateMode: _autovalidateMode,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildAvatarSection(),
              const SizedBox(height: 28),
              _buildFormFields(),
              const SizedBox(height: 24),
              _buildDivider(),
              const SizedBox(height: 24),
              _buildSaveButton(),
              const SizedBox(height: 16),
              _buildChangePasswordButton(),
              const SizedBox(height: 32),
              _buildLogoutButton(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAvatarSection() {
    final profile = widget.profile;
    return Center(
      child: Column(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              ListenableBuilder(
                listenable: _avatarController,
                builder: (context, _) {
                  final image = _avatarController.imageProvider;
                  return Container(
                    key: const ValueKey('edit-profile-avatar'),
                    width: 112,
                    height: 112,
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: AppColors.primaryNavy,
                        width: 3,
                      ),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: image != null
                        ? Image(
                            image: image,
                            fit: BoxFit.cover,
                            // Falls back to the initials-style icon instead
                            // of an uncaught decode error if the stored
                            // avatar file is ever missing/corrupted.
                            errorBuilder: (context, error, stackTrace) =>
                                const Icon(
                                  Icons.person,
                                  size: 56,
                                  color: AppColors.grayText,
                                ),
                          )
                        : const Icon(
                            Icons.person,
                            size: 56,
                            color: AppColors.grayText,
                          ),
                  );
                },
              ),
              PositionedDirectional(
                end: -6,
                bottom: -6,
                child: Tooltip(
                  message: context.t('editProfile.changePhotoTooltip'),
                  child: Semantics(
                    button: true,
                    label: context.t('editProfile.changePhotoTooltip'),
                    child: GestureDetector(
                      key: const ValueKey('edit-profile-camera-button'),
                      onTap: _isAvatarFlowActive ? null : _handleChangePhoto,
                      child: Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: AppColors.primaryNavy,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                        child: _isAvatarBusy
                            ? const Padding(
                                padding: EdgeInsets.all(9),
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(
                                Icons.camera_alt_rounded,
                                color: Colors.white,
                                size: 16,
                              ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            context.t('editProfile.ancIdLabel', params: {'id': profile.ancId}),
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppColors.textNavy,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            profile.profileUpdatedLabel,
            style: const TextStyle(fontSize: 13, color: AppColors.grayText),
          ),
        ],
      ),
    );
  }

  Widget _buildFormFields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ContactFormField(
          label: context.t('editProfile.usernameFieldLabel'),
          child: TextFormField(
            key: const ValueKey('edit-profile-username-field'),
            controller: _usernameController,
            focusNode: _usernameFocusNode,
            textInputAction: TextInputAction.next,
            style: const TextStyle(fontSize: 15, color: AppColors.textNavy),
            decoration: _fieldDecoration(errorText: _usernameServerError),
            onFieldSubmitted: (_) => _phoneFocusNode.requestFocus(),
            // Trimmed only — never lowercased or otherwise transformed;
            // the ANC API contract does not require that.
            validator: (value) => validateRequiredField(
              value,
              context.t('editProfile.usernameFieldError'),
            ),
          ),
        ),
        const SizedBox(height: 20),
        ContactFormField(
          label: context.t('editProfile.phoneFieldLabel'),
          child: TextFormField(
            key: const ValueKey('edit-profile-phone-field'),
            controller: _phoneController,
            focusNode: _phoneFocusNode,
            keyboardType: TextInputType.phone,
            textInputAction: TextInputAction.next,
            style: const TextStyle(fontSize: 15, color: AppColors.textNavy),
            // The dial code is fixed to the authenticated user's country
            // (see the class doc comment) — shown as a read-only prefix,
            // never an editable/selectable field, so this screen can never
            // silently change the stored country.
            decoration: _fieldDecoration(errorText: _phoneServerError).copyWith(
              prefixText:
                  '${_selectedCountry.flag} '
                  '${_selectedCountry.dialCode} ',
            ),
            onFieldSubmitted: (_) => _fullNameFocusNode.requestFocus(),
            // Local digits only — the same digits-only contract LoginScreen
            // already enforces for its mobile-number field.
            validator: (value) {
              final trimmed = value?.trim() ?? '';
              if (trimmed.isEmpty) {
                return context.t('validators.phoneRequired');
              }
              if (!RegExp(r'^[0-9]+$').hasMatch(trimmed)) {
                return context.t('validators.phoneInvalid');
              }
              return null;
            },
          ),
        ),
        const SizedBox(height: 20),
        ContactFormField(
          label: context.t('editProfile.fullNameFieldLabel'),
          child: TextFormField(
            key: const ValueKey('edit-profile-full-name-field'),
            controller: _fullNameController,
            focusNode: _fullNameFocusNode,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
            style: const TextStyle(fontSize: 15, color: AppColors.textNavy),
            decoration: _fieldDecoration(),
            onFieldSubmitted: (_) => _emailFocusNode.requestFocus(),
            // Optional, not required: this field legitimately starts blank
            // for any account with no locally-saved profile yet (see the
            // class doc comment), and leaving it blank must never block
            // saving an unrelated identity-only (username/phone) change.
            validator: (_) => null,
          ),
        ),
        const SizedBox(height: 20),
        ContactFormField(
          label: context.t('editProfile.emailFieldLabel'),
          child: TextFormField(
            key: const ValueKey('edit-profile-email-field'),
            controller: _emailController,
            focusNode: _emailFocusNode,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            style: const TextStyle(fontSize: 15, color: AppColors.textNavy),
            decoration: _fieldDecoration(),
            onFieldSubmitted: (_) => _companyFocusNode.requestFocus(),
            // Optional (see the full name field's validator comment above):
            // blank is valid, but a non-blank value is still checked for a
            // plausible email shape.
            validator: _validateOptionalEmail,
          ),
        ),
        const SizedBox(height: 20),
        ContactFormField(
          label: context.t('editProfile.companyFieldLabel'),
          child: TextFormField(
            key: const ValueKey('edit-profile-company-field'),
            controller: _companyController,
            focusNode: _companyFocusNode,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
            style: const TextStyle(fontSize: 15, color: AppColors.textNavy),
            decoration: _fieldDecoration(),
            onFieldSubmitted: (_) => _businessAddressFocusNode.requestFocus(),
            // Optional — see the full name field's validator comment above.
            validator: (_) => null,
          ),
        ),
        const SizedBox(height: 20),
        ContactFormField(
          label: context.t('editProfile.addressFieldLabel'),
          child: TextFormField(
            key: const ValueKey('edit-profile-business-address-field'),
            controller: _businessAddressController,
            focusNode: _businessAddressFocusNode,
            textCapitalization: TextCapitalization.sentences,
            keyboardType: TextInputType.multiline,
            textInputAction: TextInputAction.done,
            minLines: 3,
            maxLines: 5,
            style: const TextStyle(fontSize: 15, color: AppColors.textNavy),
            decoration: _fieldDecoration(),
            // Optional — see the full name field's validator comment above.
            validator: (_) => null,
          ),
        ),
      ],
    );
  }

  // Validates the email field only when it's non-blank — it is optional
  // (see _buildFormFields' full name validator comment), but a value the
  // user did enter is still checked for a plausible email shape, using the
  // same pattern validateEmailField applies elsewhere in the app.
  String? _validateOptionalEmail(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return null;
    if (!emailPattern.hasMatch(trimmed)) {
      return context.t('validators.emailInvalid');
    }
    return null;
  }

  // [errorText], when non-null, surfaces a backend-vetted field error (see
  // _usernameServerError/_phoneServerError) the same way a local
  // [TextFormField.validator] error would — Flutter shows whichever of the
  // two is present, so a fresh local-validator failure on next submit
  // still takes over normally.
  InputDecoration _fieldDecoration({String? errorText}) {
    return InputDecoration(
      filled: true,
      fillColor: AppColors.background,
      errorText: errorText,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.primaryNavy),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.dangerRed),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.dangerRed, width: 1.5),
      ),
    );
  }

  // Thin divider separating the form fields from the Save Changes action,
  // matching the reference layout.
  Widget _buildDivider() {
    return Container(height: 1, color: AppColors.border);
  }

  // Full-width, centered "Save Changes" action, matching the reference
  // layout's button width (same as the form fields above it).
  Widget _buildSaveButton() {
    return Material(
      color: AppColors.primaryNavy,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        key: const ValueKey('edit-profile-save-button'),
        borderRadius: BorderRadius.circular(12),
        onTap: _isSaving || !_isDirty ? null : _handleSave,
        child: Container(
          constraints: const BoxConstraints(minHeight: 52),
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Center(
            child: _isSaving
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Colors.white,
                    ),
                  )
                : Text(
                    context.t('editProfile.saveChanges'),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.3,
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  // Entry point to the Change Password screen — a distinct concern from
  // the profile/identity fields above, kept as its own screen/request
  // rather than crowded into the Save Changes form (see
  // ChangePasswordScreen's class doc comment).
  Widget _buildChangePasswordButton() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: const ValueKey('edit-profile-change-password-button'),
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ChangePasswordScreen(authService: _authService),
          ),
        ),
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          alignment: Alignment.center,
          child: Text(
            context.t('editProfile.changePassword'),
            style: const TextStyle(
              color: AppColors.primaryNavy,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLogoutButton() {
    return Material(
      color: AppColors.dangerRed,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        key: const ValueKey('edit-profile-logout-button'),
        borderRadius: BorderRadius.circular(12),
        onTap: _isLoggingOut ? null : _handleLogout,
        child: SizedBox(
          width: double.infinity,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: Center(
              child: _isLoggingOut
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      context.t('editProfile.logout'),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
