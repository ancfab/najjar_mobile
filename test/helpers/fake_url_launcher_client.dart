// Shared fake UrlLauncherClient for tests that exercise WhatsAppLauncher
// (directly or via SupportScreen) without invoking the real url_launcher
// plugin.

import 'package:anc_fabrics/services/whatsapp_launcher.dart';

class FakeUrlLauncherClient implements UrlLauncherClient {
  FakeUrlLauncherClient({this.nativeResult, this.webResult});

  /// `true`/`false` to resolve the launch call, or an [Exception] to throw
  /// from it, keyed by whether the URI targets the native `whatsapp://`
  /// scheme or the `https://wa.me/` web fallback.
  final Object? nativeResult;
  final Object? webResult;

  final List<Uri> attemptedUris = [];

  @override
  Future<bool> launch(Uri uri) async {
    attemptedUris.add(uri);
    final isNative = uri.scheme == 'whatsapp';
    final outcome = isNative ? nativeResult : webResult;
    if (outcome is Exception) throw outcome;
    return outcome as bool? ?? false;
  }
}
