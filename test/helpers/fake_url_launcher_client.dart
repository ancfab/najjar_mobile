// Shared fake UrlLauncherClient for tests that exercise WhatsAppLauncher or
// PhoneLauncher (directly or via SupportScreen) without invoking the real
// url_launcher plugin.

import 'package:anc_fabrics/services/url_launcher_client.dart';

class FakeUrlLauncherClient implements UrlLauncherClient {
  FakeUrlLauncherClient({this.nativeResult, this.webResult, this.telResult});

  /// `true`/`false` to resolve the launch call, or an [Exception] to throw
  /// from it, keyed by which URI scheme is targeted: the native
  /// `whatsapp://` scheme, the `https://wa.me/` web fallback, or a `tel:`
  /// dialer URI.
  final Object? nativeResult;
  final Object? webResult;
  final Object? telResult;

  final List<Uri> attemptedUris = [];

  @override
  Future<bool> launch(Uri uri) async {
    attemptedUris.add(uri);
    final Object? outcome = switch (uri.scheme) {
      'whatsapp' => nativeResult,
      'tel' => telResult,
      _ => webResult,
    };
    if (outcome is Exception) throw outcome;
    return outcome as bool? ?? false;
  }
}
