import 'package:flutter/foundation.dart';

import 'url_launcher_client.dart';

/// How an [EmailLauncher.send] attempt resolved.
enum EmailLaunchOutcome {
  /// The device's email app was opened with a prefilled draft.
  launched,

  /// No recipient address was supplied, so no launch was attempted.
  unavailable,

  /// The `mailto:` URI failed to launch (returned `false` or threw).
  failed,
}

class EmailLaunchResult {
  const EmailLaunchResult(this.outcome);

  final EmailLaunchOutcome outcome;

  bool get succeeded => outcome == EmailLaunchOutcome.launched;
}

/// Opens the device's email app prefilled with a `mailto:` draft. The email
/// app is opened, not sent — the user still has to press send themselves.
class EmailLauncher {
  const EmailLauncher({
    UrlLauncherClient client = const UrlLauncherClientImpl(),
  }) : _client = client;

  final UrlLauncherClient _client;

  Future<EmailLaunchResult> send({
    required String? to,
    String? subject,
    String? body,
  }) async {
    final trimmedTo = to?.trim() ?? '';
    if (trimmedTo.isEmpty) {
      return const EmailLaunchResult(EmailLaunchOutcome.unavailable);
    }

    final uri = Uri(
      scheme: 'mailto',
      path: trimmedTo,
      queryParameters: {
        if (subject != null && subject.trim().isNotEmpty) 'subject': subject,
        if (body != null && body.trim().isNotEmpty) 'body': body,
      },
    );

    try {
      if (await _client.launch(uri)) {
        return const EmailLaunchResult(EmailLaunchOutcome.launched);
      }
    } catch (error) {
      debugPrint('Email app launch failed: $error');
    }

    return const EmailLaunchResult(EmailLaunchOutcome.failed);
  }
}
