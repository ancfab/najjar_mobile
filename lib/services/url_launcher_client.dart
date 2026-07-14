import 'package:url_launcher/url_launcher.dart' as url_launcher;

/// Thin wrapper around the `url_launcher` plugin's static functions so
/// launch flows (WhatsApp, phone dialer, ...) can be exercised in tests
/// without invoking the real platform plugin.
abstract class UrlLauncherClient {
  Future<bool> launch(Uri uri);
}

class UrlLauncherClientImpl implements UrlLauncherClient {
  const UrlLauncherClientImpl();

  @override
  Future<bool> launch(Uri uri) {
    return url_launcher.launchUrl(
      uri,
      mode: url_launcher.LaunchMode.externalApplication,
    );
  }
}
