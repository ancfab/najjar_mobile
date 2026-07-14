import 'package:flutter/foundation.dart';

import '../utils/phone_number.dart';
import 'url_launcher_client.dart';

/// How a [PhoneLauncher.call] attempt resolved.
enum PhoneLaunchOutcome {
  /// The native dialer was opened with the number prefilled.
  launched,

  /// The region had no usable hotline number, so no launch was attempted.
  unavailable,

  /// The dialer URI failed to launch (returned `false` or threw).
  failed,
}

class PhoneLaunchResult {
  const PhoneLaunchResult(this.outcome, {this.normalizedNumber});

  final PhoneLaunchOutcome outcome;
  final String? normalizedNumber;

  bool get succeeded => outcome == PhoneLaunchOutcome.launched;
}

/// Opens the device's native phone dialer prefilled with a given hotline
/// number. The dialer is opened, not the call placed — the user still has
/// to press call themselves, so no `CALL_PHONE` permission is needed.
class PhoneLauncher {
  const PhoneLauncher({
    UrlLauncherClient client = const UrlLauncherClientImpl(),
  }) : _client = client;

  final UrlLauncherClient _client;

  /// Normalizes [rawNumber] and attempts to open the native dialer with it
  /// prefilled via a `tel:` URI.
  Future<PhoneLaunchResult> call(String? rawNumber) async {
    final normalized = normalizePhoneNumberForTel(rawNumber);
    if (normalized == null) {
      return const PhoneLaunchResult(PhoneLaunchOutcome.unavailable);
    }

    final uri = Uri.parse('tel:$normalized');
    try {
      if (await _client.launch(uri)) {
        return PhoneLaunchResult(
          PhoneLaunchOutcome.launched,
          normalizedNumber: normalized,
        );
      }
    } catch (error) {
      debugPrint('Phone dialer launch failed: $error');
    }

    return PhoneLaunchResult(
      PhoneLaunchOutcome.failed,
      normalizedNumber: normalized,
    );
  }
}
