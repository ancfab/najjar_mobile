import 'dart:io';

import 'package:flutter/foundation.dart';

import '../config/api_config.dart';
import '../models/auth/auth_session.dart';
import '../models/auth/authenticated_user.dart';
import '../models/auth/change_password_result.dart';
import '../models/auth/login_failure.dart';
import '../models/auth/login_request.dart';
import '../models/auth/login_response.dart';
import '../models/local_customer_profile.dart';
import '../models/auth/session_validation_result.dart';
import '../models/auth/update_profile_result.dart';
import '../models/auth/upload_avatar_result.dart';
import '../utils/image_format_sniffer.dart';
import 'anc_api_client.dart';
import 'anc_api_exceptions.dart';
import 'auth_session_store.dart';
import 'local_customer_profile_store.dart';
import 'logout_service.dart';
import 'secure_auth_session_store.dart';
import 'session_storage_exception.dart';

/// Purpose: Coordinates authentication against the ANC API and persists the
/// resulting secure session.
///
/// Responsibilities:
/// - Build the exact `POST /api/auth/login` request from caller-supplied
///   values plus the fixed [ApiConfig.clientId].
/// - Call the login endpoint through [AncApiClient] and map its typed
///   failures — and the secure-storage failure that can follow a successful
///   call — into the small stable [AuthLoginFailureType] taxonomy.
/// - Persist the resulting [AuthSession] through [AuthSessionStore] and
///   return [AuthLoginSuccess] only once that persistence has completed.
///
/// - Call `GET /auth/me` through [AncApiClient.fetchCurrentUser] to
///   re-validate a persisted session on cold app launch (see
///   [confirmSession]), never trusting a locally stored token alone.
///
/// - Implement explicit, user-initiated logout (see [logout] and
///   [LogoutService]): a best-effort `POST /auth/logout` call followed by an
///   unconditional local secure-session clear. Deliberately separate from
///   passive session expiry (`SessionExpiryCoordinator`/`SessionService`),
///   which must never attempt remote revocation against a token already
///   confirmed invalid.
///
/// Must not:
/// - Contain navigation or widget logic.
/// - Store or log passwords, tokens, or raw API responses.
/// - Communicate directly with Business Central.
/// - Implement token refresh or a timer-based expiry — none exists.
/// - Clear in-memory authenticated-user state (e.g. the avatar) or show UI —
///   [logout]'s caller owns both, the same way `EditProfileScreen` already
///   does for the local-only flow it replaces.
class AuthService implements LogoutService {
  /// Creates an [AuthService] over caller-owned dependencies. [apiClient]
  /// and [sessionStore] are never closed or otherwise disposed by this
  /// instance — the caller retains ownership.
  AuthService({
    required AncApiClient apiClient,
    required AuthSessionStore sessionStore,
    LocalCustomerProfileStore? localProfileStore,
  }) : _apiClient = apiClient,
       _sessionStore = sessionStore,
       _localProfileStore = localProfileStore ?? SecureLocalCustomerProfileStore(),
       _ownsApiClient = false;

  AuthService._owned({
    required AncApiClient apiClient,
    required AuthSessionStore sessionStore,
    LocalCustomerProfileStore? localProfileStore,
  }) : _apiClient = apiClient,
       _sessionStore = sessionStore,
       _localProfileStore = localProfileStore ?? SecureLocalCustomerProfileStore(),
       _ownsApiClient = true;

  /// Production factory: creates and owns its own [AncApiClient] (closed by
  /// [close]) over the real network, and defaults to a real
  /// [SecureAuthSessionStore] unless [sessionStore] is supplied.
  factory AuthService.production({AuthSessionStore? sessionStore}) =>
      AuthService._owned(
        apiClient: AncApiClient(),
        sessionStore: sessionStore ?? SecureAuthSessionStore(),
      );

  final AncApiClient _apiClient;
  final AuthSessionStore _sessionStore;

  /// Local persistence for the customer-profile display fields (full name,
  /// email, company, business address), seeded at login from the account's
  /// own Business Central Customer Details row — see [_seedLocalProfile].
  final LocalCustomerProfileStore _localProfileStore;

  /// Whether this instance created [_apiClient] itself (via
  /// [AuthService.production]) as opposed to receiving a caller-owned one —
  /// only an owned client is closed by [close].
  final bool _ownsApiClient;

  /// Logs in against the ANC API and, on success, persists the resulting
  /// session before returning.
  ///
  /// [country], [phone], and [username] are sent as already
  /// selected/constructed API values — this method does not validate them
  /// against the ANC API's country/dial-code catalogue. [country] and
  /// [username] have accidental outer whitespace trimmed; [phone] and
  /// [password] are sent exactly as supplied, unmodified. The distributor
  /// `client_id` always comes from [ApiConfig.clientId] and cannot be
  /// overridden by the caller.
  Future<AuthLoginResult> login({
    required String country,
    required String phone,
    required String username,
    required String password,
  }) async {
    final trimmedCountry = country.trim();
    final trimmedUsername = username.trim();

    if (trimmedCountry.isEmpty ||
        phone.isEmpty ||
        trimmedUsername.isEmpty ||
        password.isEmpty) {
      return const AuthLoginFailure(AuthLoginFailureType.invalidInput);
    }

    final request = LoginRequest(
      country: trimmedCountry,
      phone: phone,
      username: trimmedUsername,
      clientId: ApiConfig.clientId,
      password: password,
    );

    final LoginResponse response;
    try {
      response = await _apiClient.login(request);
    } on AncHttpException catch (error) {
      return _mapHttpFailure(error);
    } on AncNetworkException {
      return const AuthLoginFailure(AuthLoginFailureType.network);
    } on AncProtocolException {
      return const AuthLoginFailure(AuthLoginFailureType.invalidResponse);
    }

    final session = AuthSession.fromLoginResponse(response);

    try {
      await _sessionStore.save(session);
    } on SessionStorageException {
      return const AuthLoginFailure(AuthLoginFailureType.secureStorage);
    }

    await _seedLocalProfile(session.userId, response.customerDetails);

    return AuthLoginSuccess(session);
  }

  /// Seeds this account's locally-persisted customer profile from the login
  /// response's embedded Business Central Customer Details row, so the
  /// profile screens show the customer's real BC name/email/address from
  /// the very first login instead of empty fields.
  ///
  /// Strictly best-effort and never destructive:
  /// - Nothing happens when the backend sent no `customer_details`.
  /// - An already-saved local profile with any non-blank field is left
  ///   untouched — the user's own edits always win over a re-seed.
  /// - Any storage failure is swallowed; login has already succeeded.
  ///
  /// Field mapping (tenant field names vary in casing — the first present,
  /// non-blank candidate wins; a field with no usable candidate is stored
  /// as an empty string, never a fabricated value):
  /// - full name/company: `customerName`
  /// - email: `email`
  /// - business address: `address`, `address2`, `city`, `postCode` joined.
  Future<void> _seedLocalProfile(
    int userId,
    Map<String, dynamic>? customerDetails,
  ) async {
    if (customerDetails == null) return;

    String pick(List<String> keys) {
      for (final key in keys) {
        final value = customerDetails[key];
        if (value is String && value.trim().isNotEmpty) return value.trim();
      }
      return '';
    }

    final name = pick(['customerName', 'CustomerName', 'name', 'Name']);
    final email = pick(['email', 'Email', 'eMail', 'E_Mail']);
    final addressParts = [
      pick(['address', 'Address']),
      pick(['address2', 'Address2']),
      pick(['city', 'City']),
      pick(['postCode', 'PostCode', 'postalCode']),
    ].where((part) => part.isNotEmpty).toList();
    final businessAddress = addressParts.join(', ');

    if (name.isEmpty && email.isEmpty && businessAddress.isEmpty) return;

    try {
      final existing = await _localProfileStore.load(userId);
      final hasOwnData =
          existing != null &&
          (existing.fullName.trim().isNotEmpty ||
              existing.email.trim().isNotEmpty ||
              existing.company.trim().isNotEmpty ||
              existing.businessAddress.trim().isNotEmpty);
      if (hasOwnData) return;

      await _localProfileStore.save(
        userId,
        LocalCustomerProfile(
          fullName: name,
          email: email,
          company: name,
          businessAddress: businessAddress,
        ),
      );
    } catch (error) {
      // Best-effort enrichment only — never fail a successful login over it.
      debugPrint('Seeding local customer profile failed: $error');
    }
  }

  /// Re-validates a persisted secure session against `GET /auth/me`, per
  /// the app-startup contract in `main.dart`: a locally stored token is
  /// never trusted on its own.
  ///
  /// - No stored session -> [SessionValidationAbsent].
  /// - The stored session cannot even be read (a secure-storage I/O
  ///   failure) -> [SessionValidationStorageFailure]; the session is left
  ///   untouched since nothing is known to safely clear.
  /// - HTTP 200 -> the session is re-persisted with identity fields
  ///   refreshed from the response (see [AuthSession.fromAuthenticatedUser])
  ///   and [SessionValidationValid] is returned. A failure to re-persist is
  ///   not escalated — the freshly confirmed data is still safe to use for
  ///   this launch even if it could not be written back.
  /// - HTTP 401 -> the token is revoked; the secure session is cleared
  ///   (best-effort — see [_clearIgnoringStorageFailure]) and
  ///   [SessionValidationRevoked] is returned.
  /// - A malformed response body -> the secure session is cleared, since it
  ///   cannot be trusted, and [SessionValidationUnusable] is returned.
  /// - A network failure, timeout, or any other unexpected HTTP status ->
  ///   the secure session is left untouched and
  ///   [SessionValidationUnavailable] is returned; this must never be
  ///   treated as an invalid credential.
  Future<SessionValidationResult> confirmSession() async {
    final AuthSession? stored;
    try {
      stored = await _sessionStore.read();
    } on SessionStorageException {
      return const SessionValidationStorageFailure();
    }
    if (stored == null) return const SessionValidationAbsent();

    try {
      final user = await _apiClient.fetchCurrentUser(token: stored.token);
      final updated = AuthSession.fromAuthenticatedUser(
        token: stored.token,
        user: user,
      );
      try {
        await _sessionStore.save(updated);
      } on SessionStorageException {
        // Best-effort refresh only; see doc comment above.
      }
      return SessionValidationValid(updated);
    } on AncHttpException catch (error) {
      if (error.statusCode == 401) {
        await _clearIgnoringStorageFailure();
        return const SessionValidationRevoked();
      }
      return const SessionValidationUnavailable();
    } on AncNetworkException {
      return const SessionValidationUnavailable();
    } on AncProtocolException {
      await _clearIgnoringStorageFailure();
      return const SessionValidationUnusable();
    }
  }

  /// Returns the currently persisted session, if any, **without**
  /// confirming it against the backend — for display/prefill purposes only
  /// (e.g. showing the signed-in user's username/phone/avatar while a
  /// screen builds, before the user has changed anything). A secure-storage
  /// read failure resolves to `null` the same as "no session", since there
  /// is nothing safe to prefill from either way.
  ///
  /// Must never be used to decide whether a user is authenticated — see
  /// [confirmSession] for that; a value returned here could be stale or
  /// (rarely) already revoked server-side.
  Future<AuthSession?> currentSession() async {
    try {
      return await _sessionStore.read();
    } on SessionStorageException {
      return null;
    }
  }

  /// Updates the authenticated user's `username` and/or `phone` against
  /// `PATCH /auth/me`, refreshing and re-persisting the stored session on
  /// success.
  ///
  /// [username] and [phone] have accidental outer whitespace trimmed, then
  /// an empty result is treated the same as not supplying that field. At
  /// least one of the two must resolve to a non-empty value, or this
  /// returns [UpdateProfileFailureType.invalidInput] before any API call —
  /// the backend field this maps to is fixed (`username`/`phone`); this
  /// method never edits `client_id`, `country`, or `bc_customer_no`.
  ///
  /// - No stored session -> [UpdateProfileFailureType.unauthorized]; no
  ///   API call is made.
  /// - HTTP 200 -> the session is re-persisted with identity fields
  ///   refreshed from the response (see [AuthSession.fromAuthenticatedUser],
  ///   the same helper [confirmSession] uses), preserving [AuthSession.token]
  ///   unchanged, and [UpdateProfileSuccess] is returned.
  /// - HTTP 401 -> the stored token is revoked; the secure session is
  ///   cleared (best-effort) and [UpdateProfileFailureType.unauthorized] is
  ///   returned, the same as [confirmSession]'s HTTP 401 handling — this
  ///   method has no dependency on `SessionExpiryCoordinator` (see the
  ///   class doc comment).
  /// - HTTP 422 with `errors.username` -> [UpdateProfileFailureType.usernameTaken]
  ///   with that message. HTTP 422 with `errors.phone` (and no
  ///   `errors.username`) -> [UpdateProfileFailureType.invalidPhone] with
  ///   that message. Any other 422 shape -> [UpdateProfileFailureType.invalidInput].
  /// - A network failure, timeout, or unexpected HTTP status ->
  ///   [UpdateProfileFailureType.network] / [UpdateProfileFailureType.serviceUnavailable]
  ///   respectively; the stored session is left untouched.
  /// - A malformed response body -> [UpdateProfileFailureType.invalidResponse];
  ///   the stored session is left untouched (unlike [confirmSession], this
  ///   is not evidence the *stored* session is unusable — only that this one
  ///   response could not be parsed).
  /// - A failure to re-persist the refreshed session ->
  ///   [UpdateProfileFailureType.secureStorage] — unlike [confirmSession],
  ///   this is surfaced rather than swallowed, since the caller's own edit
  ///   would otherwise silently appear to have not been saved.
  Future<UpdateProfileResult> updateProfile({
    String? username,
    String? phone,
  }) async {
    final trimmedUsername = username?.trim();
    final normalizedUsername =
        (trimmedUsername == null || trimmedUsername.isEmpty)
        ? null
        : trimmedUsername;
    final trimmedPhone = phone?.trim();
    final normalizedPhone = (trimmedPhone == null || trimmedPhone.isEmpty)
        ? null
        : trimmedPhone;

    if (normalizedUsername == null && normalizedPhone == null) {
      return const UpdateProfileFailure(UpdateProfileFailureType.invalidInput);
    }

    final AuthSession? stored;
    try {
      stored = await _sessionStore.read();
    } on SessionStorageException {
      return const UpdateProfileFailure(UpdateProfileFailureType.secureStorage);
    }
    if (stored == null) {
      return const UpdateProfileFailure(UpdateProfileFailureType.unauthorized);
    }

    final AuthenticatedUser user;
    try {
      user = await _apiClient.updateMe(
        token: stored.token,
        username: normalizedUsername,
        phone: normalizedPhone,
      );
    } on AncHttpException catch (error) {
      if (error.statusCode == 401) {
        await _clearIgnoringStorageFailure();
        return const UpdateProfileFailure(
          UpdateProfileFailureType.unauthorized,
        );
      }
      return _mapUpdateProfileHttpFailure(error);
    } on AncNetworkException {
      return const UpdateProfileFailure(UpdateProfileFailureType.network);
    } on AncProtocolException {
      return const UpdateProfileFailure(
        UpdateProfileFailureType.invalidResponse,
      );
    }

    final updated = AuthSession.fromAuthenticatedUser(
      token: stored.token,
      user: user,
    );
    try {
      await _sessionStore.save(updated);
    } on SessionStorageException {
      return const UpdateProfileFailure(UpdateProfileFailureType.secureStorage);
    }

    return UpdateProfileSuccess(updated);
  }

  /// Clears the secure session, swallowing a [SessionStorageException] so a
  /// failure to also delete the local copy never blocks reporting that the
  /// token is confirmed dead/unusable server-side — correctness of that
  /// outcome (never showing Home with it) matters more than surfacing a
  /// storage error mid-validation.
  Future<void> _clearIgnoringStorageFailure() async {
    try {
      await _sessionStore.clear();
    } on SessionStorageException {
      // Intentionally ignored; see doc comment above.
    }
  }

  /// Explicit, user-initiated logout: attempts `POST /auth/logout` on a
  /// best-effort basis, then unconditionally clears the local secure
  /// session — implementing [LogoutService] for callers such as
  /// `EditProfileScreen`.
  ///
  /// Sequence:
  /// 1. Read the stored [AuthSession]. A [SessionStorageException] here
  ///    (the session itself cannot be read) is treated as "no token
  ///    available" for the remote step below — this never creates an
  ///    in-memory token cache, and local clear is still attempted next.
  /// 2. If a token is available, attempt [AncApiClient.logout]. Every
  ///    [AncApiException] outcome — HTTP 401/422/5xx, a timeout, a network
  ///    failure, or a malformed response — is swallowed here: the remote
  ///    result never gates, delays, or blocks the local clear that follows,
  ///    and is never retried.
  /// 3. Unconditionally call [AuthSessionStore.clear]. This is the only
  ///    step whose failure this method surfaces: a thrown
  ///    [SessionStorageException] propagates unchanged (the secure token is
  ///    guaranteed still present per [SecureAuthSessionStore.clear]'s
  ///    ordering guarantee), so the caller must not navigate to Login or
  ///    treat this call as a successful sign-out.
  ///
  /// Never clears in-memory authenticated-user state, shows UI, or
  /// navigates — the caller (see `EditProfileScreen._handleLogout`) owns
  /// all three, exactly as it already does for the local-only flow this
  /// replaces.
  ///
  /// Deliberately never touches this account's locally-persisted customer
  /// profile (see `LocalCustomerProfileStore`): that store is keyed by
  /// `userId` and is meant to survive logout, so the same account finds its
  /// saved full name/email/company/business address restored on a later
  /// login on this device.
  @override
  Future<void> logout() async {
    AuthSession? stored;
    try {
      stored = await _sessionStore.read();
    } on SessionStorageException {
      stored = null;
    }

    final token = stored?.token;
    if (token != null) {
      try {
        await _apiClient.logout(token: token);
      } on AncApiException {
        // Best-effort remote revocation only; see the method doc comment
        // above — no remote outcome may prevent the local clear below.
      }
    }

    await _sessionStore.clear();
  }

  /// Maps a well-formed non-2xx login response to a failure.
  ///
  /// Deterministic rule: HTTP 422 with an `errors.phone` message maps to
  /// [AuthLoginFailureType.invalidPhone]; every other 422 shape (including
  /// `errors.username`, an unknown field, or a malformed/empty body) maps
  /// neutrally to [AuthLoginFailureType.invalidCredentials] — the ANC API
  /// deliberately surfaces wrong password, unknown username/phone, a
  /// deactivated account, and backend misconfiguration identically under
  /// `errors.username`, so none of those can be distinguished or implied
  /// here. HTTP 5xx, and every other unexpected non-success status
  /// (including an unexpected 401 — this endpoint has no session to clear),
  /// map to [AuthLoginFailureType.serviceUnavailable].
  AuthLoginFailure _mapHttpFailure(AncHttpException error) {
    if (error.statusCode == 422) {
      final phoneError = error.validationError?.firstErrorFor('phone');
      if (phoneError != null) {
        return AuthLoginFailure(
          AuthLoginFailureType.invalidPhone,
          phoneError: phoneError,
        );
      }
      return const AuthLoginFailure(AuthLoginFailureType.invalidCredentials);
    }

    return const AuthLoginFailure(AuthLoginFailureType.serviceUnavailable);
  }

  /// Maps a well-formed non-2xx `PATCH /auth/me` response (other than 401,
  /// handled separately in [updateProfile]) to a failure.
  ///
  /// Deterministic rule: HTTP 422 with an `errors.username` message maps to
  /// [UpdateProfileFailureType.usernameTaken]; HTTP 422 with an
  /// `errors.phone` message (and no `errors.username`) maps to
  /// [UpdateProfileFailureType.invalidPhone]; any other 422 shape maps to
  /// [UpdateProfileFailureType.invalidInput]. HTTP 5xx and every other
  /// unexpected non-success status map to
  /// [UpdateProfileFailureType.serviceUnavailable].
  UpdateProfileFailure _mapUpdateProfileHttpFailure(AncHttpException error) {
    if (error.statusCode == 422) {
      final usernameError = error.validationError?.firstErrorFor('username');
      if (usernameError != null) {
        return UpdateProfileFailure(
          UpdateProfileFailureType.usernameTaken,
          usernameError: usernameError,
        );
      }
      final phoneError = error.validationError?.firstErrorFor('phone');
      if (phoneError != null) {
        return UpdateProfileFailure(
          UpdateProfileFailureType.invalidPhone,
          phoneError: phoneError,
        );
      }
      return const UpdateProfileFailure(UpdateProfileFailureType.invalidInput);
    }

    return const UpdateProfileFailure(
      UpdateProfileFailureType.serviceUnavailable,
    );
  }

  /// Changes the authenticated user's password against
  /// `PUT /auth/me/password`.
  ///
  /// [currentPassword], [password], and [passwordConfirmation] are sent
  /// exactly as supplied — never trimmed — the same as [login]'s password
  /// parameter. All three must be non-empty, or this returns
  /// [ChangePasswordFailureType.invalidInput] before any API call.
  ///
  /// - No stored session -> [ChangePasswordFailureType.unauthorized]; no
  ///   API call is made.
  /// - HTTP 200 -> [ChangePasswordSuccess]. Per the confirmed contract this
  ///   endpoint does not rotate or revoke the current bearer token, so the
  ///   stored session is left untouched.
  /// - HTTP 401 -> the stored token is revoked; the secure session is
  ///   cleared (best-effort) and [ChangePasswordFailureType.unauthorized] is
  ///   returned, the same as [confirmSession]/[updateProfile]'s HTTP 401
  ///   handling.
  /// - HTTP 422 with `errors.current_password` ->
  ///   [ChangePasswordFailureType.incorrectCurrentPassword]. HTTP 422 with
  ///   `errors.password` (and no `errors.current_password`) ->
  ///   [ChangePasswordFailureType.weakPassword] with that message. HTTP 422
  ///   with `errors.password_confirmation` (and neither of the above) ->
  ///   [ChangePasswordFailureType.passwordConfirmationMismatch] with that
  ///   message. Any other 422 shape -> [ChangePasswordFailureType.invalidInput].
  /// - A network failure, timeout, or unexpected HTTP status ->
  ///   [ChangePasswordFailureType.network] /
  ///   [ChangePasswordFailureType.serviceUnavailable] respectively.
  /// - A malformed response body -> [ChangePasswordFailureType.invalidResponse].
  Future<ChangePasswordResult> changePassword({
    required String currentPassword,
    required String password,
    required String passwordConfirmation,
  }) async {
    if (currentPassword.isEmpty ||
        password.isEmpty ||
        passwordConfirmation.isEmpty) {
      return const ChangePasswordFailure(
        ChangePasswordFailureType.invalidInput,
      );
    }

    final AuthSession? stored;
    try {
      stored = await _sessionStore.read();
    } on SessionStorageException {
      return const ChangePasswordFailure(
        ChangePasswordFailureType.secureStorage,
      );
    }
    if (stored == null) {
      return const ChangePasswordFailure(
        ChangePasswordFailureType.unauthorized,
      );
    }

    try {
      await _apiClient.changePassword(
        token: stored.token,
        currentPassword: currentPassword,
        password: password,
        passwordConfirmation: passwordConfirmation,
      );
    } on AncHttpException catch (error) {
      if (error.statusCode == 401) {
        await _clearIgnoringStorageFailure();
        return const ChangePasswordFailure(
          ChangePasswordFailureType.unauthorized,
        );
      }
      return _mapChangePasswordHttpFailure(error);
    } on AncNetworkException {
      return const ChangePasswordFailure(ChangePasswordFailureType.network);
    } on AncProtocolException {
      return const ChangePasswordFailure(
        ChangePasswordFailureType.invalidResponse,
      );
    }

    return const ChangePasswordSuccess();
  }

  /// Maps a well-formed non-2xx `PUT /auth/me/password` response (other
  /// than 401, handled separately in [changePassword]) to a failure.
  ///
  /// Deterministic rule: HTTP 422 with an `errors.current_password` message
  /// maps to [ChangePasswordFailureType.incorrectCurrentPassword]; HTTP 422
  /// with an `errors.password` message (and no `errors.current_password`)
  /// maps to [ChangePasswordFailureType.weakPassword]; HTTP 422 with an
  /// `errors.password_confirmation` message (and neither of the above) maps
  /// to [ChangePasswordFailureType.passwordConfirmationMismatch] — both
  /// field names are confirmed by the documented contract
  /// (`password`/`password_confirmation` are the exact request keys), not
  /// guessed. Any other 422 shape maps to
  /// [ChangePasswordFailureType.invalidInput]. HTTP 5xx and every other
  /// unexpected non-success status map to
  /// [ChangePasswordFailureType.serviceUnavailable].
  ChangePasswordFailure _mapChangePasswordHttpFailure(AncHttpException error) {
    if (error.statusCode == 422) {
      final currentPasswordError = error.validationError?.firstErrorFor(
        'current_password',
      );
      if (currentPasswordError != null) {
        return const ChangePasswordFailure(
          ChangePasswordFailureType.incorrectCurrentPassword,
        );
      }
      final passwordError = error.validationError?.firstErrorFor('password');
      if (passwordError != null) {
        return ChangePasswordFailure(
          ChangePasswordFailureType.weakPassword,
          passwordError: passwordError,
        );
      }
      final confirmationError = error.validationError?.firstErrorFor(
        'password_confirmation',
      );
      if (confirmationError != null) {
        return ChangePasswordFailure(
          ChangePasswordFailureType.passwordConfirmationMismatch,
          passwordError: confirmationError,
        );
      }
      return const ChangePasswordFailure(
        ChangePasswordFailureType.invalidInput,
      );
    }

    return const ChangePasswordFailure(
      ChangePasswordFailureType.serviceUnavailable,
    );
  }

  /// Uploads [avatar] as the authenticated user's avatar against
  /// `POST /auth/me/avatar`, refreshing and re-persisting the stored
  /// session (with the new `avatarUrl`) on success. Per the confirmed
  /// contract, a successful upload replaces and deletes the previous
  /// avatar server-side — there is no separate remove-avatar endpoint, so
  /// this is the only way the avatar ever changes.
  ///
  /// - No file at [avatar]'s path -> [UploadAvatarFailureType.fileNotFound];
  ///   no API call is made.
  /// - A file larger than [ApiConfig.avatarMaxUploadBytes] ->
  ///   [UploadAvatarFailureType.fileTooLarge]; no API call is made — this
  ///   is a client-side pre-check against the documented 5 MB limit, not a
  ///   guess at a backend rule.
  /// - A file whose leading bytes don't match jpg/png/webp (see
  ///   [hasSupportedAvatarUploadSignature] — never decided by the file's
  ///   extension alone) -> [UploadAvatarFailureType.unsupportedFormat]; no
  ///   API call is made. In practice every avatar this app ever produces
  ///   has already been through `ImageCropperAvatarCropperService`, which
  ///   fixes its output to JPEG regardless of the original picked format —
  ///   this check is defense-in-depth for [avatar] arguments constructed
  ///   any other way, not a live gap in the pick→crop→upload flow.
  /// - No stored session -> [UploadAvatarFailureType.unauthorized]; no API
  ///   call is made.
  /// - HTTP 200 -> the session is re-persisted with identity fields
  ///   (including `avatarUrl`) refreshed from the response (see
  ///   [AuthSession.fromAuthenticatedUser], the same helper
  ///   [confirmSession]/[updateProfile] use), preserving
  ///   [AuthSession.token] unchanged, and [UploadAvatarSuccess] is
  ///   returned.
  /// - HTTP 401 -> the stored token is revoked; the secure session is
  ///   cleared (best-effort) and [UploadAvatarFailureType.unauthorized] is
  ///   returned, the same as [confirmSession]/[updateProfile]/
  ///   [changePassword]'s HTTP 401 handling.
  /// - HTTP 422 with `errors.avatar` ->
  ///   [UploadAvatarFailureType.rejectedByServer] with that message. Any
  ///   other 422 shape also maps to [UploadAvatarFailureType.rejectedByServer],
  ///   with no message.
  /// - A network failure, timeout, or unexpected HTTP status ->
  ///   [UploadAvatarFailureType.network] /
  ///   [UploadAvatarFailureType.serviceUnavailable] respectively; the
  ///   stored session is left untouched.
  /// - A malformed response body -> [UploadAvatarFailureType.invalidResponse];
  ///   the stored session is left untouched (same reasoning as
  ///   [updateProfile]'s handling of this case).
  /// - A failure to re-persist the refreshed session ->
  ///   [UploadAvatarFailureType.secureStorage] — surfaced rather than
  ///   swallowed, for the same reason as [updateProfile].
  Future<UploadAvatarResult> uploadAvatar(File avatar) async {
    debugPrint('[AVATAR DEBUG] AuthService.uploadAvatar entered.');
    debugPrint('[AVATAR DEBUG] Image path received: ${avatar.path}');

    final exists = await avatar.exists();
    debugPrint('[AVATAR DEBUG] Image file exists: $exists');
    if (!exists) {
      debugPrint(
        '[AVATAR DEBUG] Result classification: fileNotFound (local check).',
      );
      return const UploadAvatarFailure(UploadAvatarFailureType.fileNotFound);
    }

    final length = await avatar.length();
    debugPrint('[AVATAR DEBUG] Image file length: $length bytes');
    if (length > ApiConfig.avatarMaxUploadBytes) {
      debugPrint(
        '[AVATAR DEBUG] Result classification: fileTooLarge (local check).',
      );
      return const UploadAvatarFailure(UploadAvatarFailureType.fileTooLarge);
    }
    if (!hasSupportedAvatarUploadSignature(await avatar.readAsBytes())) {
      debugPrint(
        '[AVATAR DEBUG] Result classification: unsupportedFormat '
        '(local check).',
      );
      return const UploadAvatarFailure(
        UploadAvatarFailureType.unsupportedFormat,
      );
    }

    final AuthSession? stored;
    try {
      stored = await _sessionStore.read();
    } on SessionStorageException {
      debugPrint(
        '[AVATAR DEBUG] Result classification: secureStorage '
        '(session read failed).',
      );
      return const UploadAvatarFailure(UploadAvatarFailureType.secureStorage);
    }
    debugPrint(
      '[AVATAR DEBUG] Local authenticated session exists: ${stored != null}',
    );
    if (stored == null) {
      debugPrint(
        '[AVATAR DEBUG] Result classification: unauthorized '
        '(no stored session).',
      );
      return const UploadAvatarFailure(UploadAvatarFailureType.unauthorized);
    }
    // Never printed: stored.token itself — only whether one is present.
    debugPrint(
      '[AVATAR DEBUG] Token present: ${stored.token.isNotEmpty} '
      '(value never logged).',
    );

    final AuthenticatedUser user;
    try {
      debugPrint('[AVATAR DEBUG] Delegating request to AncApiClient.');
      user = await _apiClient.uploadAvatar(
        token: stored.token,
        filePath: avatar.path,
      );
      debugPrint('[AVATAR DEBUG] Result received from AncApiClient: success.');
    } on AncHttpException catch (error) {
      debugPrint(
        '[AVATAR DEBUG] Result received from AncApiClient: '
        'AncHttpException (status ${error.statusCode}).',
      );
      if (error.statusCode == 401) {
        debugPrint('[AVATAR DEBUG] Result classification: unauthorized.');
        debugPrint('[AVATAR DEBUG] Clearing local session: true.');
        await _clearIgnoringStorageFailure();
        return const UploadAvatarFailure(UploadAvatarFailureType.unauthorized);
      }
      final failure = _mapUploadAvatarHttpFailure(error);
      debugPrint('[AVATAR DEBUG] Result classification: ${failure.type}.');
      return failure;
    } on AncNetworkException catch (error) {
      debugPrint(
        '[AVATAR DEBUG] Result received from AncApiClient: '
        'AncNetworkException: $error.',
      );
      debugPrint('[AVATAR DEBUG] Result classification: network.');
      return const UploadAvatarFailure(UploadAvatarFailureType.network);
    } on AncProtocolException catch (error) {
      debugPrint(
        '[AVATAR DEBUG] Result received from AncApiClient: '
        'AncProtocolException: $error.',
      );
      debugPrint('[AVATAR DEBUG] Result classification: invalidResponse.');
      return const UploadAvatarFailure(UploadAvatarFailureType.invalidResponse);
    }

    final updated = AuthSession.fromAuthenticatedUser(
      token: stored.token,
      user: user,
    );
    debugPrint('[AVATAR DEBUG] AuthenticatedUser returned: true.');
    try {
      await _sessionStore.save(updated);
    } on SessionStorageException {
      debugPrint(
        '[AVATAR DEBUG] Result classification: secureStorage '
        '(session save failed).',
      );
      return const UploadAvatarFailure(UploadAvatarFailureType.secureStorage);
    }

    debugPrint('[AVATAR DEBUG] Result classification: success.');
    return UploadAvatarSuccess(updated);
  }

  /// Maps a well-formed non-2xx `POST /auth/me/avatar` response (other
  /// than 401, handled separately in [uploadAvatar]) to a failure.
  ///
  /// Deterministic rule: HTTP 422 always maps to
  /// [UploadAvatarFailureType.rejectedByServer], carrying the first
  /// `errors.avatar` message when present. HTTP 5xx and every other
  /// unexpected non-success status map to
  /// [UploadAvatarFailureType.serviceUnavailable].
  UploadAvatarFailure _mapUploadAvatarHttpFailure(AncHttpException error) {
    if (error.statusCode == 422) {
      return UploadAvatarFailure(
        UploadAvatarFailureType.rejectedByServer,
        message: error.validationError?.firstErrorFor('avatar'),
      );
    }

    return const UploadAvatarFailure(
      UploadAvatarFailureType.serviceUnavailable,
    );
  }

  /// Closes the underlying [AncApiClient], but only when this instance
  /// created it (via [AuthService.production]); a caller-supplied client is
  /// left open for the caller to manage. Safe to call more than once.
  void close() {
    if (_ownsApiClient) _apiClient.close();
  }
}
