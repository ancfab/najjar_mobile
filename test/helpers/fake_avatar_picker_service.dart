// Fake AvatarPickerService for tests that exercise the Edit Profile avatar
// flow without depending on the real image_picker platform channel.

import 'dart:async';

import 'package:anc_fabrics/services/avatar_picker_service.dart';

class FakeAvatarPickerService implements AvatarPickerService {
  FakeAvatarPickerService({
    this.resultPath = '/tmp/fake_picked_avatar.jpg',
    this.cancelled = false,
    this.throwError,
    this.pending,
  });

  /// Path resolved as the picked image when not [cancelled] and
  /// [throwError] is null. Defaults to a placeholder path so happy-path
  /// tests don't need to configure a picker at all.
  String? resultPath;

  /// When true, simulates the user cancelling the platform picker
  /// (`pickImage` resolves with null).
  bool cancelled;

  /// When set, `pickImage` throws this instead of resolving.
  Exception? throwError;

  /// When set, `pickImage` awaits this instead of resolving immediately.
  final Completer<PickedAvatarImage?>? pending;

  final List<AvatarImageSource> requestedSources = [];

  @override
  Future<PickedAvatarImage?> pickImage(AvatarImageSource source) async {
    requestedSources.add(source);
    if (pending != null) return pending!.future;
    if (throwError != null) throw throwError!;
    if (cancelled) return null;
    return PickedAvatarImage(resultPath!);
  }
}
