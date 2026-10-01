import 'package:flutter/foundation.dart';

import 'url_launcher_client.dart';

/// How a [MapsLauncher.openLocation] attempt resolved.
enum MapsLaunchOutcome {
  /// A maps app (or the browser) was opened on the location.
  launched,

  /// The query was empty, so no launch was attempted.
  unavailable,

  /// The launch was attempted and failed or threw.
  failed,
}

class MapsLaunchResult {
  const MapsLaunchResult(this.outcome);

  final MapsLaunchOutcome outcome;

  bool get succeeded => outcome == MapsLaunchOutcome.launched;
}

/// Opens one of ANC's own office locations in whichever maps app the device
/// hands an `https://www.google.com/maps/search/` link to — Google Maps when
/// installed, Apple Maps or the browser otherwise.
///
/// Deliberately a plain web link rather than a `comgooglemaps://` scheme or
/// an embedded map SDK: the link needs no extra iOS query scheme, no
/// third-party SDK, and — because it only ever carries ANC's own address —
/// no location permission and no change to the app's privacy disclosures.
/// The user's own position is never read; the maps app itself handles
/// "directions from here" if the user asks for it there.
class MapsLauncher {
  const MapsLauncher({
    UrlLauncherClient client = const UrlLauncherClientImpl(),
  }) : _client = client;

  final UrlLauncherClient _client;

  /// Opens a maps search for [parts] joined into one query (e.g. an office
  /// name, its street address and its city). Blank/null parts are dropped,
  /// so a location with no verified name still searches cleanly on its
  /// address alone.
  Future<MapsLaunchResult> openLocation(List<String?> parts) async {
    final query = parts
        .whereType<String>()
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .join(', ');
    if (query.isEmpty) {
      return const MapsLaunchResult(MapsLaunchOutcome.unavailable);
    }

    final uri = Uri.https('www.google.com', '/maps/search/', {
      'api': '1',
      'query': query,
    });
    try {
      if (await _client.launch(uri)) {
        return const MapsLaunchResult(MapsLaunchOutcome.launched);
      }
    } catch (error) {
      debugPrint('Maps launch failed: $error');
    }
    return const MapsLaunchResult(MapsLaunchOutcome.failed);
  }
}
