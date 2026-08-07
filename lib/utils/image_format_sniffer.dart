// Purpose: Detects an image file's real format from its leading bytes
// (a "magic number"/signature check), so callers never trust a filename
// extension alone — a renamed non-image file, or an image saved under the
// wrong extension, is not decided by its name.
//
// Responsibilities:
// - Offer one signature check per format this app ever needs to
//   recognize, each a pure function over already-read bytes.
//
// Must not:
// - Read a file itself — callers own I/O; these functions only inspect
//   bytes already in memory.

import 'dart:typed_data';

/// True if [bytes] starts with the JPEG signature (`FF D8 FF`).
bool isJpeg(Uint8List bytes) =>
    bytes.length >= 3 &&
    bytes[0] == 0xFF &&
    bytes[1] == 0xD8 &&
    bytes[2] == 0xFF;

/// True if [bytes] starts with the PNG signature
/// (`89 50 4E 47 0D 0A 1A 0A`, checked through the first 4 bytes here —
/// enough to distinguish PNG from every other format this app accepts).
bool isPng(Uint8List bytes) =>
    bytes.length >= 4 &&
    bytes[0] == 0x89 &&
    bytes[1] == 0x50 &&
    bytes[2] == 0x4E &&
    bytes[3] == 0x47;

/// True if [bytes] is a RIFF container carrying a `WEBP` fourCC
/// (`"RIFF"....`"WEBP"`).
bool isWebp(Uint8List bytes) =>
    bytes.length >= 12 &&
    bytes[0] == 0x52 &&
    bytes[1] == 0x49 &&
    bytes[2] == 0x46 &&
    bytes[3] == 0x46 &&
    bytes[8] == 0x57 &&
    bytes[9] == 0x45 &&
    bytes[10] == 0x42 &&
    bytes[11] == 0x50;

/// True if [bytes] is an ISO base media file carrying an `ftyp` box whose
/// brand starts a HEIC/HEIF family value (box size (4 bytes) + `"ftyp"` +
/// brand, e.g. `heic`/`heix`/`mif1`).
bool isHeic(Uint8List bytes) =>
    bytes.length >= 12 &&
    bytes[4] == 0x66 &&
    bytes[5] == 0x74 &&
    bytes[6] == 0x79 &&
    bytes[7] == 0x70;

/// True if [bytes] matches any format this app's avatar *picker* pipeline
/// accepts pre-crop (JPEG/PNG/WEBP/HEIC) — the cropper transcodes any of
/// these to JPEG, so this broader set is only ever checked before cropping.
bool hasSupportedAvatarSourceSignature(Uint8List bytes) =>
    isJpeg(bytes) || isPng(bytes) || isWebp(bytes) || isHeic(bytes);

/// True if [bytes] matches a format the ANC API's avatar-upload endpoint
/// accepts (jpg/jpeg/png/webp — no HEIC) — checked post-crop, immediately
/// before upload.
bool hasSupportedAvatarUploadSignature(Uint8List bytes) =>
    isJpeg(bytes) || isPng(bytes) || isWebp(bytes);
