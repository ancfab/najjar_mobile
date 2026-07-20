// Shared fixture for tests that need real, decodable image bytes on disk
// (e.g. to exercise `FileImage`/`Image.file` avatar rendering).
//
// Two distinct hazards live here, and both matter:
//
// 1. Deliberately invalid bytes (e.g. `[0, 1, 2, 3]`) leave the platform
//    image codec's behavior on malformed input undefined in practice.
//    [validAvatarPngBytes] is a minimal, genuinely valid 1x1 PNG instead.
// 2. `testWidgets` bodies run inside a fake-async zone that drives time by
//    manually pumping frames, not the real event loop. Real OS/engine-level
//    async work — real `dart:io` file I/O, and real `dart:ui` image
//    decoding — depends on genuine asynchronous callbacks that fake-async
//    pumping cannot reliably wait out: on this environment, awaiting a
//    plain `File.writeAsBytes` (let alone the image decode a rendered
//    `FileImage` triggers afterwards) directly in a `testWidgets` body has
//    been observed to hang until the test's timeout instead of completing.
//    [writeAndPrecacheAvatarFile] does both inside `tester.runAsync`, which
//    runs its callback on the real event loop instead, so they reliably
//    complete before the widget tree is pumped again.

import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// A minimal valid 1x1 PNG's bytes, captured once from Flutter's own
/// `dart:ui` `Canvas`/`Picture.toImage`/`Image.toByteData` pipeline (not
/// hand-authored) so it is guaranteed byte-correct.
const List<int> validAvatarPngBytes = <int>[
  137,
  80,
  78,
  71,
  13,
  10,
  26,
  10,
  0,
  0,
  0,
  13,
  73,
  72,
  68,
  82,
  0,
  0,
  0,
  1,
  0,
  0,
  0,
  1,
  8,
  6,
  0,
  0,
  0,
  31,
  21,
  196,
  137,
  0,
  0,
  0,
  1,
  115,
  82,
  71,
  66,
  0,
  174,
  206,
  28,
  233,
  0,
  0,
  0,
  4,
  115,
  66,
  73,
  84,
  8,
  8,
  8,
  8,
  124,
  8,
  100,
  136,
  0,
  0,
  0,
  13,
  73,
  68,
  65,
  84,
  8,
  153,
  99,
  200,
  73,
  254,
  255,
  31,
  0,
  5,
  219,
  2,
  206,
  75,
  82,
  117,
  250,
  0,
  0,
  0,
  0,
  73,
  69,
  78,
  68,
  174,
  66,
  96,
  130,
];

/// Writes [bytes] to [path] and precaches the result as a [FileImage] using
/// [context] to build an [ImageConfiguration] — see the file-level doc
/// comment for why both steps need to happen for real, off the fake-async
/// clock. Must be called from inside `tester.runAsync`.
///
/// Once this completes, any [FileImage] resolving the same file path
/// elsewhere in the widget tree (e.g. the one `CircleAvatar`/`Image`/
/// `DecorationImage` builds internally) hits Flutter's image cache — keyed
/// by file path, not object identity — and resolves instantly instead of
/// decoding again.
Future<File> writeAndPrecacheAvatarFile({
  required String path,
  required List<int> bytes,
  required BuildContext context,
}) async {
  final file = await File(path).writeAsBytes(bytes);
  await precacheImage(FileImage(file), context);
  return file;
}
