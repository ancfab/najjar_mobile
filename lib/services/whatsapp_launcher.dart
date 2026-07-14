import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart' as url_launcher;

import '../utils/phone_number.dart';

/// Thin wrapper around the `url_launcher` plugin's static functions so the
/// Support screen's WhatsApp launch flow can be exercised in tests without
/// invoking the real platform plugin.
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

/// How a [WhatsAppLauncher.open] attempt resolved.
enum WhatsAppLaunchOutcome {
  /// The native WhatsApp app URI was launched successfully.
  launchedNative,

  /// The native URI failed (returned `false` or threw), but the
  /// `https://wa.me/` web fallback launched successfully.
  launchedWeb,

  /// Both the native URI and the web fallback failed or threw.
  failed,

  /// The region had no usable WhatsApp number, so no launch was attempted.
  unavailable,
}

class WhatsAppLaunchResult {
  const WhatsAppLaunchResult(this.outcome, {this.normalizedNumber});

  final WhatsAppLaunchOutcome outcome;
  final String? normalizedNumber;

  bool get succeeded =>
      outcome == WhatsAppLaunchOutcome.launchedNative ||
      outcome == WhatsAppLaunchOutcome.launchedWeb;
}

/// Opens a WhatsApp chat for a given phone number, preferring the native
/// app and falling back to the WhatsApp web link when the native app
/// can't be opened (not installed, launch returns `false`, or throws).
class WhatsAppLauncher {
  const WhatsAppLauncher({
    UrlLauncherClient client = const UrlLauncherClientImpl(),
  }) : _client = client;

  final UrlLauncherClient _client;

  /// Normalizes [rawNumber] and attempts to open a WhatsApp chat with it,
  /// trying the native `whatsapp://` URI first and the `https://wa.me/`
  /// web URI only if the native attempt fails or throws.
  Future<WhatsAppLaunchResult> open(String? rawNumber) async {
    final normalized = normalizeWhatsAppNumber(rawNumber);
    if (normalized == null) {
      return const WhatsAppLaunchResult(WhatsAppLaunchOutcome.unavailable);
    }

    final nativeUri = Uri.parse('whatsapp://send?phone=$normalized');
    try {
      if (await _client.launch(nativeUri)) {
        return WhatsAppLaunchResult(
          WhatsAppLaunchOutcome.launchedNative,
          normalizedNumber: normalized,
        );
      }
    } catch (error) {
      debugPrint('WhatsApp native launch failed, trying web fallback: $error');
    }

    final webUri = Uri.parse('https://wa.me/$normalized');
    try {
      if (await _client.launch(webUri)) {
        return WhatsAppLaunchResult(
          WhatsAppLaunchOutcome.launchedWeb,
          normalizedNumber: normalized,
        );
      }
    } catch (error) {
      debugPrint('WhatsApp web fallback launch failed: $error');
    }

    return WhatsAppLaunchResult(
      WhatsAppLaunchOutcome.failed,
      normalizedNumber: normalized,
    );
  }
}
